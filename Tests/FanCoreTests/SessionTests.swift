import XCTest

@testable import FanCore

private final class Hardware: FanHardware {
  var writes = 0, restores = 0
  var writeFails = false, restoreFails = false, readingsFail = false
  var temperature = 65.0
  var sequence = 0
  var onApply: (() -> Void)?
  func snapshot() throws -> Snapshot {
    if readingsFail { throw FanError("sensor read failed") }
    sequence += 1
    return Snapshot(
      date: Date().addingTimeInterval(Double(sequence) * 0.001),
      fans: [Fan(id: 0, rpm: 2000, minimum: 1350, maximum: 5349)],
      sensors: [Sensor(id: "CPU", temperature: temperature)])
  }
  func apply(_ targets: [Int: Double]) throws {
    writes += 1
    onApply?()
    if writeFails { throw FanError("firmware rejected target") }
  }
  func restoreAutomatic() throws {
    restores += 1
    if restoreFails { throw FanError("restoration failed") }
  }
}
final class SessionTests: XCTestCase {
  func testSlowAcquisitionGetsLeaseAfterCompletion() {
    let hardware = Hardware()
    var time = 10.0
    hardware.onApply = { time = 19 }
    let session = ControlSession(hardware: hardware, clock: { time })
    XCTAssertNil(session.command(.init(mode: .performance), uptime: 10).error)
    session.tick(uptime: 20)
    XCTAssertEqual(session.mode, .performance)
    session.tick(uptime: 27)
    XCTAssertEqual(session.mode, .automatic)
    XCTAssertEqual(hardware.restores, 1)
  }
  func testIdleSessionDoesNotChangeOtherAppsFanState() {
    let hardware = Hardware()
    let session = ControlSession(hardware: hardware, clock: { 0 })
    session.tick(uptime: 10)
    session.release()
    XCTAssertEqual(hardware.writes, 0)
    XCTAssertEqual(hardware.restores, 0)
  }
  func testHeartbeatExpiryRestoresAndStopsWriting() {
    let hardware = Hardware()
    let session = ControlSession(hardware: hardware, clock: { 0 })
    XCTAssertNil(session.command(.init(mode: .performance), uptime: 10).error)
    session.tick(uptime: 17)
    XCTAssertEqual(hardware.writes, 2)
    session.tick(uptime: 18)
    XCTAssertEqual(session.mode, .automatic)
    XCTAssertEqual(hardware.restores, 1)
    session.tick(uptime: 30)
    XCTAssertEqual(hardware.writes, 2)
  }
  func testRecoveryMarkerIsWrittenBeforeHardwareAndRemovedAfterRestore() {
    let hardware = Hardware()
    var marked = false
    let session = ControlSession(
      hardware: hardware,
      beginOverride: {
        XCTAssertEqual(hardware.writes, 0)
        marked = true
      },
      endOverride: {
        XCTAssertGreaterThan(hardware.restores, 0)
        marked = false
      })
    _ = session.command(.init(mode: .performance), uptime: 10)
    XCTAssertTrue(marked)
    session.release()
    XCTAssertFalse(marked)
  }
  func testJournalFailurePreventsFanWrites() {
    let hardware = Hardware()
    let session = ControlSession(hardware: hardware, beginOverride: { throw FanError("disk full") })
    let response = session.command(.init(mode: .performance), uptime: 10)
    XCTAssertNotNil(response.error)
    XCTAssertEqual(response.mode, .automatic)
    XCTAssertEqual(hardware.writes, 0)
  }
  func testPartialWriteFailureRestores() {
    let hardware = Hardware()
    hardware.writeFails = true
    let session = ControlSession(hardware: hardware, clock: { 0 })
    let response = session.command(.init(mode: .performance), uptime: 10)
    XCTAssertNotNil(response.error)
    XCTAssertEqual(response.mode, .automatic)
    XCTAssertEqual(hardware.restores, 1)
  }
  func testFailedRestorationIsRetriedAndNeverClaimsSuccess() {
    let hardware = Hardware()
    let session = ControlSession(hardware: hardware, clock: { 0 })
    _ = session.command(.init(mode: .performance), uptime: 10)
    hardware.restoreFails = true
    session.release()
    XCTAssertTrue(session.recoveryPending)
    XCTAssertNotNil(session.failure)
    let writes = hardware.writes
    let response = session.command(.init(mode: .manual, fractions: [0.3]), uptime: 11)
    XCTAssertNotNil(response.error)
    XCTAssertEqual(hardware.writes, writes)
    hardware.restoreFails = false
    session.tick(uptime: 12)
    XCTAssertFalse(session.recoveryPending)
    XCTAssertEqual(hardware.writes, writes)
  }
  func testStartupRecoveryIsReadOnlyUntilOverrideWasRecorded() {
    let hardware = Hardware()
    let session = ControlSession(hardware: hardware, recoveryPending: true)
    session.tick(uptime: 10)
    XCTAssertEqual(hardware.restores, 1)
    XCTAssertEqual(hardware.writes, 0)
    XCTAssertFalse(session.recoveryPending)
  }
  func testSensorFailureDuringControlReleases() {
    let hardware = Hardware()
    let session = ControlSession(hardware: hardware, clock: { 0 })
    _ = session.command(.init(mode: .performance), uptime: 10)
    hardware.readingsFail = true
    session.tick(uptime: 11)
    XCTAssertEqual(session.mode, .automatic)
    XCTAssertEqual(hardware.restores, 1)
    XCTAssertNotNil(session.failure)
  }
  func testMalformedManualRequestNeverWrites() {
    let hardware = Hardware()
    let session = ControlSession(hardware: hardware, clock: { 0 })
    let response = session.command(.init(mode: .manual, fractions: [-1]), uptime: 10)
    XCTAssertNotNil(response.error)
    XCTAssertEqual(hardware.writes, 0)
  }
  func testExplicitAppleModeIsVerified() {
    let hardware = Hardware()
    hardware.restoreFails = true
    let session = ControlSession(hardware: hardware, clock: { 0 })
    let response = session.command(.init(mode: .automatic), uptime: 10)
    XCTAssertNotNil(response.error)
    XCTAssertTrue(session.recoveryPending)
  }
}
