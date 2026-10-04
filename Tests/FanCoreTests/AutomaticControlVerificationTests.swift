import XCTest
@testable import FanCore

final class AutomaticControlVerificationTests: XCTestCase {
  private let automatic: [String: Double] = [
    "FNum": 2, "Ftst": 0, "F0Md": 3, "F1Md": 0, "F0Tg": 0, "F1Tg": 0, "F0Mx": 5349, "F1Mx": 5777,
  ]

  func testCompleteAutomaticStateAllowsRemovalWithoutHelper() throws {
    try AutomaticControlVerification.verify { automatic[$0] }
  }

  func testFirmwareOwnedNonzeroTargetsAreAllowed() throws {
    var values = automatic
    values["F0Md"] = 0
    values["F1Md"] = 0
    values["F0Tg"] = 1350
    values["F1Tg"] = 1458
    try AutomaticControlVerification.verify { values[$0] }
    values["F0Md"] = 1
    XCTAssertThrowsError(try AutomaticControlVerification.verify { values[$0] })
  }

  func testInitialRegistrationCanSupportFirmwareWithoutUnlockKey() throws {
    var values = automatic
    values.removeValue(forKey: "Ftst")
    XCTAssertThrowsError(try AutomaticControlVerification.verify { values[$0] })
    try AutomaticControlVerification.verify(readNumber: { values[$0] }, allowMissingUnlock: true)
    values["Ftst"] = 1
    XCTAssertThrowsError(try AutomaticControlVerification.verify(
      readNumber: { values[$0] }, allowMissingUnlock: true))
  }

  func testLowercaseModeKeysAreSupported() throws {
    var values = automatic
    values["F0md"] = values.removeValue(forKey: "F0Md")
    values["F1md"] = values.removeValue(forKey: "F1Md")
    try AutomaticControlVerification.verify { values[$0] }
  }

  func testMissingReadbacksBlockRemoval() {
    for key in automatic.keys {
      var values = automatic
      values.removeValue(forKey: key)
      XCTAssertThrowsError(try AutomaticControlVerification.verify { values[$0] }, key)
    }
  }

  func testOverridesAndInvalidValuesBlockRemoval() {
    for (key, value) in [("Ftst", 1.0), ("F0Md", 1), ("F1Tg", 6000),
                         ("FNum", .nan), ("FNum", 1.5), ("FNum", -1),
                         ("FNum", 10), ("F0Tg", .nan), ("F1Md", .infinity)] {
      var values = automatic
      values[key] = value
      XCTAssertThrowsError(try AutomaticControlVerification.verify { values[$0] }, key)
    }
  }
}
