import XCTest
@testable import FanCore

final class ReadbackTests: XCTestCase {
  func testDelayedFirmwareReadbackIsAccepted() throws {
    var now = 0.0
    try FanReadback.wait(deadline: 1, clock: { now }, sleep: { now += $0 },
      matches: { now >= 0.3 }, failure: { "not settled" })
    XCTAssertGreaterThanOrEqual(now, 0.3)
    XCTAssertLessThan(now, 1)
  }
  func testRefusedWriteRemainsAnErrorAtDeadline() {
    var now = 0.0
    XCTAssertThrowsError(try FanReadback.wait(
      deadline: 1, clock: { now }, sleep: { now += $0 },
      matches: { false }, failure: { "firmware refused" }))
    XCTAssertEqual(now, 1, accuracy: 0.001)
  }
  func testCancelledControlNeverAcceptsReadback() {
    XCTAssertThrowsError(try FanReadback.wait(
      deadline: 1, clock: { 0 }, cancelled: { true },
      matches: { XCTFail("cancelled request must not read hardware"); return true },
      failure: { "not settled" }))
  }
}
