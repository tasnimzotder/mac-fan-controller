import XCTest

@testable import FanCore

final class AcquisitionTests: XCTestCase {
  func testOldConnectionCannotCancelNewLease() {
    let cancellation = ControlCancellation()
    let old = UUID()
    let current = UUID()
    cancellation.begin(old)
    cancellation.cancel(old)
    XCTAssertTrue(cancellation.cancelled)
    cancellation.begin(current)
    cancellation.cancel(old)
    XCTAssertFalse(cancellation.cancelled)
    cancellation.cancel(current)
    XCTAssertTrue(cancellation.cancelled)
  }
  func testSlowFirmwareAcquisitionUsesSharedDeadline() throws {
    var time = 0.0
    var mode = 3.0
    var unlock = 0.0
    var unlockWrites = 0
    try FanAcquisition.acquire(
      deadline: 10, clock: { time }, sleep: { time += $0 }, cancelled: { false },
      readMode: { mode },
      writeManual: {
        guard unlock == 1 && time >= 6 else { throw FanError("protected mode") }
        mode = 1
      }, readUnlock: { unlock },
      writeUnlock: {
        unlock = 1
        unlockWrites += 1
      })
    XCTAssertGreaterThanOrEqual(time, 6)
    XCTAssertLessThan(time, 10)
    XCTAssertEqual(unlockWrites, 1)
    // The second fan cannot restart the global ten-second deadline.
    XCTAssertThrowsError(
      try FanAcquisition.acquire(
        deadline: 10, clock: { time }, sleep: { time += $0 }, cancelled: { false },
        readMode: { 3 }, writeManual: { throw FanError("still protected") },
        readUnlock: { unlock }, writeUnlock: { XCTFail("unlock is global") }))
    XCTAssertEqual(time, 10, accuracy: 0.001)
  }
  func testDisconnectCancelsFurtherModeWrites() {
    var time = 0.0
    var writes = 0
    let cancellation = ControlCancellation()
    cancellation.set(false)
    XCTAssertThrowsError(
      try FanAcquisition.acquire(
        deadline: 10, clock: { time },
        sleep: {
          time += $0
          cancellation.set(true)
        }, cancelled: { cancellation.cancelled }, readMode: { 3 },
        writeManual: {
          writes += 1
          throw FanError("protected")
        },
        readUnlock: { 1 }, writeUnlock: { XCTFail("already unlocked") }))
    XCTAssertEqual(writes, 2)
    XCTAssertLessThan(time, 1)
  }
  func testDirectModeRequiresReadbackAndNoUnlockWhenSuccessful() throws {
    var mode = 0.0
    try FanAcquisition.acquire(
      deadline: 10, clock: { 0 }, cancelled: { false }, readMode: { mode },
      writeManual: { mode = 1 },
      readUnlock: {
        XCTFail("direct mode works")
        return nil
      },
      writeUnlock: { XCTFail("direct mode works") })
    XCTAssertEqual(mode, 1)
  }
  func testMissingUnlockDoesNotSpinOrPretendSuccess() {
    XCTAssertThrowsError(
      try FanAcquisition.acquire(
        deadline: 10, clock: { 0 }, sleep: { _ in XCTFail("no unlock") },
        cancelled: { false }, readMode: { 3 }, writeManual: {},
        readUnlock: { nil }, writeUnlock: { XCTFail("missing unlock") }))
  }
}
