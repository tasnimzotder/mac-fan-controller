import CSMC
import Darwin
import Foundation

public final class SMC {
  private var connection: UInt32 = 0
  private var sensorKeys: [String] = []
  public init() throws {
    let result = mfc_open(&connection)
    guard result == 0 else { throw FanError("AppleSMC unavailable (\(result)).") }
    // Restrict control input to known CPU/GPU keys, not unrelated battery/board sensors.
    let known: [String]
    switch Self.chip {
    case let chip where chip.hasPrefix("Apple M2"):
      known = [
        "Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f",
        "Tp0j", "Tg0f", "Tg0j",
      ]
    case let chip where chip.hasPrefix("Apple M3"):
      known = [
        "Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44",
        "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E", "Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28",
        "Tf29", "Tf2A",
      ]
    default: known = []  // Unknown models stay read-only until their sensors are validated.
    }
    sensorKeys = known.sorted().filter { number($0) != nil }
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
  public static var supportsControl: Bool { ["Apple M2 Pro", "Apple M3 Pro"].contains(chip) }
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
      count <= 9
    else { throw FanError("Fan count unavailable.") }
    let fans = try (0..<Int(count)).map { id -> Fan in
      guard let rpm = number("F\(id)Ac"), rpm.isFinite, rpm >= 0,
        let minimum = number("F\(id)Mn"), let maximum = number("F\(id)Mx"),
        let mode = number(modeKey(id)), mode.isFinite
      else {
        throw FanError("Fan \(id+1) readings unavailable.")
      }
      return Fan(
        id: id, rpm: rpm, minimum: minimum, maximum: maximum, target: number("F\(id)Tg") ?? 0,
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
      throw FanError("Fan writes are currently restricted to M2 Pro and M3 Pro Macs.")
    }
    let snapshot = try snapshot()
    guard Set(targets.keys) == Set(snapshot.fans.map(\.id)) else {
      throw FanError("Incomplete fan targets.")
    }
    for fan in snapshot.fans {
      guard let target = targets[fan.id], target.isFinite, fan.controllable,
        (fan.minimum...fan.maximum).contains(target)
      else { throw FanError("Target outside hardware limits.") }
      let key = modeKey(fan.id)
      if number(key) != 1 {
        do { try writeNumber(key, 1) } catch {
          // M3 thermal-manager handshake. No thermal daemon is killed or disabled.
          if number("Ftst") != 1 {
            try writeNumber("Ftst", 1)
            Thread.sleep(forTimeInterval: 3)
          }
          // Keep the handshake bounded so heartbeat and restoration stay responsive.
          var lastError: Error?
          for _ in 0..<15 {
            do {
              try writeNumber(key, 1)
              lastError = nil
              break
            } catch {
              lastError = error
              Thread.sleep(forTimeInterval: 0.1)
            }
          }
          if let lastError { throw lastError }
        }
        guard number(key) == 1 else { throw FanError("Firmware refused manual fan mode.") }
      }
      // The unlock can take seconds. Recheck temperature before issuing a low target.
      let fresh = try self.snapshot()
      guard fresh.completeSensorReadings, let hottest = fresh.hottest else {
        throw FanError("Sensors incomplete after fan-mode handshake.")
      }
      let effectiveTarget = hottest >= 95 || fresh.thermalState >= 2 ? fan.maximum : target
      try writeNumber("F\(fan.id)Tg", effectiveTarget)
      guard let actual = number("F\(fan.id)Tg"), abs(actual - effectiveTarget) < 100 else {
        throw FanError("Fan target readback failed.")
      }
    }
  }
  public func restoreAutomatic() throws {
    guard let count = number("FNum"), count.isFinite, (0...9).contains(count) else {
      throw FanError("Cannot restore: fan count unavailable.")
    }
    var errors: [String] = []
    for id in 0..<Int(count) {
      do {
        let key = modeKey(id)
        if number(key) == 1 { try writeNumber(key, 0) }
        guard let mode = number(key), mode == 0 || mode == 3 else {
          throw FanError("Fan \(id+1) automatic-mode readback failed.")
        }
        // Firmware automatic mode ignores the forced target; clear it after releasing mode.
        if let target = number("F\(id)Tg"), target != 0 { try writeNumber("F\(id)Tg", 0) }
      } catch { errors.append(error.localizedDescription) }
    }
    if number("Ftst") == 1 {
      do { try writeNumber("Ftst", 0) } catch { errors.append(error.localizedDescription) }
    }
    if number("Ftst") == 1 { errors.append("Thermal-manager unlock is still held.") }
    guard errors.isEmpty else { throw FanError(errors.joined(separator: " ")) }
  }
}
