import Foundation

public protocol FanHardware: AnyObject {
  func snapshot() throws -> Snapshot
  func apply(_ targets: [Int: Double]) throws
  func restoreAutomatic() throws
}
extension SMC: FanHardware {}

/// Serialized by the helper's queue. Hardware access and recovery are injectable for tests.
public final class ControlSession {
  private let hardware: FanHardware
  private let beginOverride: () throws -> Void
  private let endOverride: () throws -> Void
  private let clock: () -> TimeInterval
  private var controller = FanController()
  private var request = HelperRequest(mode: .automatic)
  private var lastHeartbeat: TimeInterval = 0
  private var overriding = false
  public private(set) var recoveryPending: Bool
  public private(set) var failure: String?
  public var mode: ControlMode { request.mode }

  public init(
    hardware: FanHardware, recoveryPending: Bool = false,
    beginOverride: @escaping () throws -> Void = {}, endOverride: @escaping () throws -> Void = {},
    clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
  ) {
    self.hardware = hardware
    self.recoveryPending = recoveryPending
    self.overriding = recoveryPending
    self.beginOverride = beginOverride
    self.endOverride = endOverride
    self.clock = clock
  }

  public func command(
    _ request: HelperRequest, uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) -> HelperReply {
    if request.statusOnly == true { return HelperReply(mode: mode, error: failure) }
    let started = clock()
    do {
      if request.mode == .automatic {
        // An explicit command also lets the user recover a retained override.
        release(force: true)
        return HelperReply(mode: mode, error: failure)
      }
      guard !recoveryPending else { throw FanError("Apple-control restoration is still pending.") }
      let snapshot = try hardware.snapshot()
      if request.mode == .manual {
        guard request.fractions.count == snapshot.fans.count,
          request.fractions.allSatisfy({ $0.isFinite && (0...1).contains($0) })
        else {
          throw FanError("Invalid manual targets.")
        }
      }
      self.request = request
      lastHeartbeat = uptime
      // Validate inputs before marking ownership or writing anything.
      let targets = try controller.targets(snapshot, mode: request.mode, manual: request.fractions)
      if !overriding {
        try beginOverride()  // durable recovery marker precedes the first hardware write
        overriding = true
      }
      if let targets { try hardware.apply(targets) }
      let acquisitionDuration = max(0, clock() - started)
      lastHeartbeat = uptime + acquisitionDuration
      // Do not treat firmware acquisition time as a missed temperature sample.
      if acquisitionDuration >= 6 { controller.reset() }
      failure = nil
    } catch {
      failure = error.localizedDescription
      release(preserveFailure: true)
    }
    return HelperReply(mode: mode, error: failure)
  }

  public func tick(uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    if recoveryPending {
      release()
      return
    }
    guard mode != .automatic else { return }
    let elapsed = uptime - lastHeartbeat
    guard elapsed >= 0, elapsed < 8 else {
      release()
      return
    }
    do {
      let snapshot = try hardware.snapshot()
      if let targets = try controller.targets(snapshot, mode: mode, manual: request.fractions) {
        try hardware.apply(targets)
      }
      failure = nil
    } catch {
      failure = error.localizedDescription
      release(preserveFailure: true)
    }
  }

  public func release(preserveFailure: Bool = false, force: Bool = false) {
    request = HelperRequest(mode: .automatic)
    controller.reset()
    guard overriding || recoveryPending || force else { return }
    do {
      try hardware.restoreAutomatic()
      try endOverride()
      overriding = false
      recoveryPending = false
      if !preserveFailure { failure = nil }
    } catch {
      recoveryPending = true
      let original = preserveFailure ? failure : nil
      failure = "Apple automatic restoration failed: \(error.localizedDescription)"
      if let original { failure = original + " " + failure! }
    }
  }
}
