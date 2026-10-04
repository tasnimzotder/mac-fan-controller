import XCTest

@testable import FanCore

final class ControllerTests: XCTestCase {
  func testIdlePresetsRequestDifferentSpeeds() throws {
    let date = Date()
    var results: [ControlMode: [Int: Double]] = [:]
    for mode in [ControlMode.quiet, .balanced, .performance] {
      var controller = FanController()
      results[mode] = try XCTUnwrap(controller.targets(sample(43, at: date), mode: mode, now: date))
    }
    for fan in fans {
      XCTAssertGreaterThan(results[.performance]![fan.id]!, results[.balanced]![fan.id]!)
      XCTAssertGreaterThan(results[.balanced]![fan.id]!, results[.quiet]![fan.id]!)
    }
  }
  func testTurboImmediatelyUsesEachFansMaximum() throws {
    var controller = FanController()
    let date = Date()
    let targets = try XCTUnwrap(controller.targets(sample(40, at: date), mode: .turbo, now: date))
    for fan in fans { XCTAssertEqual(targets[fan.id], fan.maximum) }
    let later = date.addingTimeInterval(1)
    let quiet = try XCTUnwrap(controller.targets(sample(40, at: later), mode: .quiet, now: later))
    for fan in fans { XCTAssertEqual(quiet[fan.id], fan.minimum) }
  }
  func testTurboStillRejectsMissingTemperatureReadings() {
    var controller = FanController()
    XCTAssertThrowsError(try controller.targets(Snapshot(fans: fans, sensors: []), mode: .turbo))
  }

  func testPresetChangeClearsAccumulatedFeedback() throws {
    let start = Date()
    var warm = FanController()
    for second in 0..<90 {
      let date = start.addingTimeInterval(Double(second))
      _ = try warm.targets(sample(77, at: date), mode: .balanced, now: date)
    }
    let date = start.addingTimeInterval(90)
    let switched = try warm.targets(sample(77, at: date), mode: .quiet, now: date)
    var fresh = FanController()
    let expected = try fresh.targets(sample(77, at: date), mode: .quiet, now: date)
    XCTAssertEqual(switched, expected)
  }

  func testSyntheticThermalPlantStaysBoundedAndPresetsSeparate() throws {
    // Deliberately simple first-order plant; a regression model, not Mac calibration.
    var finalTemperatures: [ControlMode: Double] = [:]
    for mode in [ControlMode.performance, .balanced, .quiet] {
      var controller = FanController()
      var temperature = 45.0
      var rpm = fans[0].minimum
      let start = Date()
      var settled: [Double] = []
      for second in 0..<900 {
        let date = start.addingTimeInterval(Double(second))
        let fan = Fan(id: 0, rpm: rpm, minimum: fans[0].minimum, maximum: fans[0].maximum)
        let reading = Snapshot(date: date, fans: [fan], sensors: [Sensor(id: "CPU", temperature: temperature)])
        let targets = try XCTUnwrap(controller.targets(reading, mode: mode, now: date))
        let target = try XCTUnwrap(targets[0])
        XCTAssertTrue((fan.minimum...fan.maximum).contains(target))
        rpm += (target - rpm) * (1 - exp(-1.0 / 2))
        let fraction = (rpm - fan.minimum) / (fan.maximum - fan.minimum)
        temperature += 2 - (0.02 + 0.05 * fraction) * (temperature - 30)
        XCTAssertLessThan(temperature, 95)
        if second >= 800 { settled.append(temperature) }
      }
      XCTAssertLessThan(settled.max()! - settled.min()!, 3)
      finalTemperatures[mode] = temperature
    }
    XCTAssertLessThan(finalTemperatures[.performance]!, finalTemperatures[.balanced]!)
    XCTAssertLessThan(finalTemperatures[.balanced]!, finalTemperatures[.quiet]!)
  }

  private let fans = [
    Fan(id: 0, rpm: 2000, minimum: 1350, maximum: 5349),
    Fan(id: 1, rpm: 2000, minimum: 1458, maximum: 5777),
  ]
  private func sample(_ temperature: Double, at date: Date, thermal: Int = 0) -> Snapshot {
    Snapshot(
      date: date, fans: fans, sensors: [Sensor(id: "CPU", temperature: temperature)],
      thermalState: thermal)
  }
  func testAutomaticDoesNotNeedSensorsOrFans() throws {
    var c = FanController()
    XCTAssertNil(try c.targets(Snapshot(fans: [], sensors: []), mode: .automatic))
  }
  func testPerformanceCurveIsMonotonicAndEarlierThanBalanced() {
    for t in 40...100 {
      XCTAssertGreaterThanOrEqual(
        FanController.fraction(temperature: Double(t), mode: .performance),
        FanController.fraction(temperature: Double(t - 1), mode: .performance))
      XCTAssertGreaterThanOrEqual(
        FanController.fraction(temperature: Double(t), mode: .performance),
        FanController.fraction(temperature: Double(t), mode: .balanced))
    }
    XCTAssertEqual(FanController.fraction(temperature: 80, mode: .performance), 1)
    XCTAssertEqual(
      FanController.fraction(temperature: 55, mode: .performance), 0.425, accuracy: 0.0001)
  }
  func testStartupRampIsBoundedAndDifferentFanRangesAreRespected() throws {
    var c = FanController()
    let date = Date()
    let targets = try XCTUnwrap(c.targets(sample(80, at: date), mode: .performance, now: date))
    for fan in fans {
      XCTAssertLessThanOrEqual(targets[fan.id]!, fan.rpm + 1200)
      XCTAssertGreaterThanOrEqual(targets[fan.id]!, fan.minimum)
    }
  }
  func testEmergencyBypassesRampAndManualTargets() throws {
    for thermal in [0, 2, 3] {
      var c = FanController()
      let date = Date()
      let targets = try XCTUnwrap(
        c.targets(
          sample(thermal == 0 ? 96 : 65, at: date, thermal: thermal), mode: .manual,
          manual: [0, 0], now: date))
      for fan in fans { XCTAssertEqual(targets[fan.id], fan.maximum) }
    }
  }
  func testManualDoesNotPermitStoppedFans() throws {
    var c = FanController()
    let date = Date()
    let targets = try XCTUnwrap(
      c.targets(sample(40, at: date), mode: .manual, manual: [0, 0], now: date))
    for fan in fans { XCTAssertGreaterThanOrEqual(targets[fan.id]!, fan.minimum) }
  }
  func testStaleFutureMissingAndInvalidTemperaturesFail() {
    let date = Date()
    for s in [
      sample(60, at: date.addingTimeInterval(-7)), sample(60, at: date.addingTimeInterval(3)),
      sample(.nan, at: date), sample(130, at: date), Snapshot(date: date, fans: fans, sensors: []),
      Snapshot(
        date: date, fans: fans, sensors: [Sensor(id: "CPU", temperature: 60)],
        completeSensorReadings: false),
    ] {
      var c = FanController()
      XCTAssertThrowsError(try c.targets(s, mode: .performance, now: date))
    }
  }
  func testInvalidManualFractionsFail() {
    for values in [[], [0.5], [-1, 0], [0, 1.1], [Double.nan, 0]] {
      var c = FanController()
      let date = Date()
      XCTAssertThrowsError(
        try c.targets(sample(60, at: date), mode: .manual, manual: values, now: date))
    }
  }
  func testCoolingHoldAndSlowDecreaseAreIndependentPerFan() throws {
    var c = FanController()
    let start = Date()
    let high = try XCTUnwrap(c.targets(sample(96, at: start), mode: .performance, now: start))
    var previous = high
    for second in 1...30 {
      let date = start.addingTimeInterval(Double(second))
      let targets = try XCTUnwrap(c.targets(sample(35, at: date), mode: .performance, now: date))
      for fan in fans {
        XCTAssertLessThanOrEqual(targets[fan.id]!, previous[fan.id]!)
        XCTAssertGreaterThanOrEqual(targets[fan.id]!, previous[fan.id]! - 100)
        if second <= 15 { XCTAssertEqual(targets[fan.id], high[fan.id]) }
      }
      previous = targets
    }
    XCTAssertLessThan(previous[0]!, high[0]!)
    XCTAssertLessThan(previous[1]!, high[1]!)
  }
  func testSamplingGapReleasesInsteadOfResumingOldTargets() throws {
    var c = FanController()
    let date = Date()
    _ = try c.targets(sample(60, at: date), mode: .performance, now: date)
    let later = date.addingTimeInterval(10)
    XCTAssertThrowsError(try c.targets(sample(60, at: later), mode: .performance, now: later))
  }
  func testBadLimitsAndFanlessFail() {
    for fans in [
      [], [Fan(id: 0, rpm: 0, minimum: 0, maximum: 0)],
      [Fan(id: 0, rpm: 2000, minimum: 6000, maximum: 5000)],
    ] {
      var c = FanController()
      XCTAssertThrowsError(
        try c.targets(
          Snapshot(fans: fans, sensors: [Sensor(id: "CPU", temperature: 50)]), mode: .performance))
    }
  }
  func testCoolingHoldRestartsAfterADeadbandRecovery() throws {
    var c = FanController()
    let start = Date()
    // Start at emergency maximum while already in manual mode.
    let high = try XCTUnwrap(
      c.targets(sample(96, at: start), mode: .manual, manual: [1, 1], now: start))
    for second in 2...10 {
      let date = start.addingTimeInterval(Double(second))
      _ = try c.targets(sample(50, at: date), mode: .manual, manual: [0, 0], now: date)
    }
    let neutral = start.addingTimeInterval(11)
    _ = try c.targets(sample(50, at: neutral), mode: .manual, manual: [1, 1], now: neutral)
    for second in 12...25 {
      let date = start.addingTimeInterval(Double(second))
      let targets = try XCTUnwrap(
        c.targets(sample(50, at: date), mode: .manual, manual: [0, 0], now: date))
      XCTAssertEqual(targets, high)
    }
  }
  func testFractionalHardwareLimitsAreNotExceededByRounding() throws {
    for fraction in [0.0, 1.0] {
      var c = FanController()
      let fan = Fan(id: 0, rpm: 4000, minimum: 1350.4, maximum: 4000.7)
      let targets = try XCTUnwrap(
        c.targets(
          Snapshot(fans: [fan], sensors: [Sensor(id: "CPU", temperature: 50)]), mode: .manual,
          manual: [fraction]))
      XCTAssertTrue((fan.minimum...fan.maximum).contains(targets[0]!))
    }
  }

}
