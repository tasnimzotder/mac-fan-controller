import Foundation

public enum FanReadback {
  public static func wait(
    deadline: TimeInterval,
    clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
    sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
    cancelled: () -> Bool = { false },
    matches: () -> Bool, failure: () -> String
  ) throws {
    while true {
      guard !cancelled() else { throw FanError("Fan-control request cancelled.") }
      guard clock() < deadline else { throw FanError(failure()) }
      if matches() { return }
      sleep(min(0.1, max(0, deadline - clock())))
    }
  }
}
