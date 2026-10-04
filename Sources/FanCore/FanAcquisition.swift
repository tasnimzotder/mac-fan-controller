import Foundation

public enum FanAcquisition {
  public static let timeout: TimeInterval = 10
  public static let requestTimeout: TimeInterval = 20
  public static func acquire(
    deadline: TimeInterval,
    clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
    sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
    cancelled: () -> Bool,
    readMode: () -> Double?, writeManual: () throws -> Void,
    readUnlock: () -> Double?, writeUnlock: () throws -> Void
  ) throws {
    func check() throws {
      guard !cancelled() else { throw FanError("Fan-control request cancelled.") }
      guard clock() < deadline else {
        throw FanError("Firmware did not grant manual fan control within ten seconds.")
      }
    }
    try check()
    if readMode() == 1 { return }
    do {
      try writeManual()
      if readMode() == 1 { return }
    } catch {}
    try check()
    guard let unlock = readUnlock() else {
      throw FanError("Firmware refused manual mode and provides no fan-control unlock key.")
    }
    try check()
    if unlock != 1 { try writeUnlock() }
    while true {
      try check()
      do {
        try writeManual()
        if readMode() == 1 { return }
      } catch {}
      sleep(min(0.1, max(0, deadline - clock())))
    }
  }
}

/// XPC can cancel acquisition without waiting for the hardware queue.
public final class ControlCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var value = true
  private var lease: UUID?
  public init() {}
  public var cancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
  public func set(_ value: Bool) {
    lock.lock()
    defer { lock.unlock() }
    self.value = value
  }
  public func begin(_ lease: UUID) {
    lock.lock()
    defer { lock.unlock() }
    self.lease = lease
    value = false
  }
  public func cancel(_ lease: UUID) {
    lock.lock()
    defer { lock.unlock() }
    if self.lease == lease { value = true }
  }
}
