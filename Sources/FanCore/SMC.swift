import CSMC
import Darwin
import Foundation

public final class SMC {
  private var connection: UInt32 = 0
  private var sensorKeys: [String] = []
  public var controlCancelled: () -> Bool = { false }
  public init() throws {
    let result = mfc_open(&connection)
    guard result == 0 else { throw FanError("AppleSMC unavailable (\(result)).") }
    // Probe CPU/GPU keys for the generation, without restricting fan control
    // to particular models. Key meanings can differ between generations.
    let generation = Int(Self.chip.dropFirst("Apple M".count).prefix(while: { $0.isNumber }))
    sensorKeys = (generation.flatMap { Self.controlSensorKeys[$0] } ?? []).sorted()
      .filter { number($0) != nil }
  }
  static let controlSensorKeys: [Int: [String]] = [
    1: [
      "Tg05", "Tg0D", "Tg0L", "Tg0T", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0H", "Tp0L", "Tp0P",
      "Tp0T", "Tp0X", "Tp0b",
    ],
    2: [
      "Tg0f", "Tg0j", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j", "Tp1h",
      "Tp1l", "Tp1p", "Tp1t",
    ],
    3: [
      "Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf14",
      "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A", "Tf44", "Tf49", "Tf4A", "Tf4B",
      "Tf4D", "Tf4E",
    ],
    4: [
      "Te05", "Te09", "Te0H", "Te0S", "Tg0G", "Tg0H", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j",
      "Tg0k", "Tg1U", "Tg1k", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e",
    ],
    5: [
      "Tg0U", "Tg0X", "Tg0d", "Tg0g", "Tg0j", "Tg1Y", "Tg1c", "Tg1g", "Tp00", "Tp04", "Tp08",
      "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j",
      "Tp0m", "Tp0p", "Tp0u", "Tp0y",
    ],
  ]
  public static var supportsControl: Bool {
    var arm64: Int32 = 0
    var size = MemoryLayout<Int32>.size
    return sysctlbyname("hw.optional.arm64", &arm64, &size, nil, 0) == 0 && arm64 == 1
  }

  public static var chip: String {
    var size = 0
    guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else {
      return "Unknown"
    }
    var bytes = [CChar](repeating: 0, count: size)
    guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else {
      return "Unknown"
    }
    return String(cString: bytes)
  }
  public static var isKnownFanless: Bool {
    var size = 0
    guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return false }
    var bytes = [CChar](repeating: 0, count: size)
    guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return false }
    return ["Mac14,2", "Mac14,15", "Mac15,12", "Mac15,13"].contains(String(cString: bytes))
  }
  deinit { mfc_close(connection) }
  private func value(_ key: String) throws -> (bytes: [UInt8], type: String) {
    guard key.utf8.count == 4 else { throw FanError("Invalid SMC key.") }
    var bytes = [UInt8](repeating: 0, count: 32)
    var size: UInt32 = 0
    var type: UInt32 = 0
    let result = mfc_read(connection, key, &bytes, &size, &type)
    guard result == 0 else { throw FanError("SMC read \(key) failed (\(result)).") }
    let typeBytes = (0..<4).map { UInt8((type >> (24 - $0 * 8)) & 255) }
    return (Array(bytes.prefix(Int(size))), String(decoding: typeBytes, as: UTF8.self))
  }
  public func number(_ key: String) -> Double? {
    guard let value = try? value(key) else { return nil }
    let b = value.bytes
    switch value.type {
    case "flt ":
      guard b.count == 4 else { return nil }
      let bits = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
      return Double(Float(bitPattern: bits))
    case "ui8 ": return b.first.map(Double.init)
    case "ui16":
      guard b.count == 2 else { return nil }
      return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
    case "ui32":
      guard b.count == 4 else { return nil }
      return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
    case "sp78":
      guard b.count == 2 else { return nil }
      return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256
    case "fpe2":
      guard b.count == 2 else { return nil }
      return Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4
    default: return nil
    }
  }
  private func modeKey(_ id: Int) -> String { number("F\(id)md") == nil ? "F\(id)Md" : "F\(id)md" }
  public func snapshot() throws -> Snapshot {
    guard let count = number("FNum") ?? (Self.isKnownFanless ? 0 : nil), count.isFinite, count >= 0,
      count <= 9, count == count.rounded()
    else { throw FanError("Fan count unavailable.") }
    let fans = try (0..<Int(count)).map { id -> Fan in
      guard let rpm = number("F\(id)Ac"), rpm.isFinite, rpm >= 0, rpm < 15000,
        let minimum = number("F\(id)Mn"), let maximum = number("F\(id)Mx"),
        minimum.isFinite, minimum >= 0, maximum.isFinite, maximum >= minimum, maximum < 15000,
        let mode = number(modeKey(id)), [0.0, 1.0, 3.0].contains(mode)
      else {
        throw FanError("Fan \(id+1) readings unavailable.")
      }
      let target = number("F\(id)Tg") ?? 0
      guard target.isFinite, target >= 0, target < 15000 else {
        throw FanError("Fan \(id+1) target reading is invalid.")
      }
      return Fan(
        id: id, rpm: rpm, minimum: minimum, maximum: maximum, target: target,
        mode: Int(mode))
    }
    let sensors = sensorKeys.compactMap { key -> Sensor? in
      guard let t = number(key), t.isFinite, t > 0, t < 125 else { return nil }
      return Sensor(id: key, temperature: t)
    }
    return Snapshot(
      fans: fans, sensors: sensors, thermalState: ProcessInfo.processInfo.thermalState.rawValue,
      completeSensorReadings: !sensorKeys.isEmpty && sensors.count == sensorKeys.count)
  }
  private func write(_ key: String, bytes: [UInt8]) throws {
    let result = mfc_write(connection, key, bytes, UInt32(bytes.count))
    guard result == 0 else { throw FanError("SMC write \(key) failed (\(result)).") }
  }
  private func writeNumber(_ key: String, _ number: Double) throws {
    let current = try value(key)
    guard number.isFinite else { throw FanError("Non-finite SMC target.") }
    switch current.type {
    case "ui8 ":
      guard (0...255).contains(number) else { throw FanError("Invalid mode.") }
      try write(key, bytes: [UInt8(number)])
    case "flt ":
      var f = Float(number)
      try withUnsafeBytes(of: &f) { try write(key, bytes: Array($0)) }
    case "fpe2":
      guard (0...16383).contains(number) else { throw FanError("Invalid RPM.") }
      let n = UInt16(number * 4)
      try write(key, bytes: [UInt8(n >> 8), UInt8(n & 255)])
    default: throw FanError("Unsupported SMC data type for \(key).")
    }
  }
  public func apply(_ targets: [Int: Double]) throws {
    guard Self.supportsControl else {
      throw FanError("Fan control requires an Apple Silicon Mac.")
    }
    let snapshot = try snapshot()
    guard !snapshot.fans.isEmpty else { throw FanError("No hardware fans detected.") }
    guard snapshot.completeSensorReadings, snapshot.hottest != nil else {
      throw FanError("CPU/GPU temperature readings unavailable.")
    }
    guard Set(targets.keys) == Set(snapshot.fans.map(\.id)) else {
      throw FanError("Incomplete fan targets.")
    }
    let deadline = ProcessInfo.processInfo.systemUptime + FanAcquisition.timeout
    for fan in snapshot.fans {
      guard let target = targets[fan.id], target.isFinite, fan.controllable,
        (fan.minimum...fan.maximum).contains(target)
      else { throw FanError("Target outside hardware limits.") }
      let key = modeKey(fan.id)
      try FanAcquisition.acquire(
        deadline: deadline, cancelled: controlCancelled,
        readMode: { self.number(key) }, writeManual: { try self.writeNumber(key, 1) },
        readUnlock: { self.number("Ftst") }, writeUnlock: { try self.writeNumber("Ftst", 1) })
      // The unlock can take seconds. Recheck temperature before issuing a low target.
      let fresh = try self.snapshot()
      guard fresh.completeSensorReadings, let hottest = fresh.hottest else {
        throw FanError("Sensors incomplete after fan-mode handshake.")
      }
      let effectiveTarget = hottest >= 95 || fresh.thermalState >= 2 ? fan.maximum : target
      guard !controlCancelled() else { throw FanError("Fan-control request cancelled.") }
      guard ProcessInfo.processInfo.systemUptime < deadline else {
        throw FanError("Fan-control acquisition deadline expired before target write.")
      }
      try writeNumber("F\(fan.id)Tg", effectiveTarget)
      try FanReadback.wait(
        deadline: deadline + 2, cancelled: controlCancelled,
        matches: {
          guard let actual = self.number("F\(fan.id)Tg") else { return false }
          return abs(actual - effectiveTarget) < 100 && self.number(key) == 1
        }, failure: {
          "Fan \(fan.id + 1) target readback failed: expected \(effectiveTarget), got \(self.number("F\(fan.id)Tg") ?? -1)."
        })
    }
  }
  public func restoreAutomatic() throws {
    guard let count = number("FNum"), count.isFinite, (0...9).contains(count),
      count == count.rounded() else {
      throw FanError("Cannot restore: fan count unavailable.")
    }
    var errors: [String] = []
    for id in 0..<Int(count) {
      do {
        let key = modeKey(id)
        if number(key) == 1 { try writeNumber(key, 0) }
      } catch { errors.append(error.localizedDescription) }
    }
    if number("Ftst") == 1 {
      do { try writeNumber("Ftst", 0) } catch { errors.append(error.localizedDescription) }
    }
    // Mode and unlock writes settle asynchronously. Release every override before
    // checking, so the thermal manager can finish handing control back to firmware.
    let deadline = ProcessInfo.processInfo.systemUptime + 4
    try FanReadback.wait(
      deadline: deadline,
      matches: {
        (0..<Int(count)).allSatisfy { id in
          guard let mode = self.number(self.modeKey(id)), mode == 0 || mode == 3 else {
            return false
          }
          return true
        } && self.number("Ftst") != 1
      }, failure: {
        var failures = errors
        for id in 0..<Int(count) {
          if ![0.0, 3.0].contains(self.number(self.modeKey(id)) ?? -1) {
            failures.append("Fan \(id + 1) automatic-mode readback failed.")
          }
        }
        if self.number("Ftst") == 1 { failures.append("Thermal-manager unlock is still held.") }
        return failures.isEmpty ? "Automatic-mode verification timed out." : failures.joined(separator: " ")
      })
    // Never request zero RPM while manual mode is still settling.
    for id in 0..<Int(count) {
      if let target = number("F\(id)Tg"), target != 0 {
        try writeNumber("F\(id)Tg", 0)
      }
    }
    try FanReadback.wait(deadline: deadline, matches: {
      (0..<Int(count)).allSatisfy { id in
        self.number("F\(id)Tg") == nil || self.number("F\(id)Tg") == 0
      }
    }, failure: { "Forced fan target clearing did not settle." })
  }
}
