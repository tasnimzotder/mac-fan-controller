import XCTest
@testable import FanCore

final class ThermalPIDTests: XCTestCase {
  private let tuning = ThermalPID.Tuning(setpoint: 70, kp: 0.01, ki: 0.001, kd: 0.02)

  func testIntegralUsesTrapezoidalElapsedTime() {
    var pid = ThermalPID()
    _ = pid.update(temperature: 72, dt: 1, baseline: 0.2, tuning: tuning,
                   deliveredFraction: nil, emergency: false)
    XCTAssertEqual(pid.integral, 0.002, accuracy: 1e-10)
    _ = pid.update(temperature: 74, dt: 2, baseline: 0.2, tuning: tuning,
                   deliveredFraction: nil, emergency: false)
    XCTAssertEqual(pid.integral, 0.008, accuracy: 1e-10)
  }

  func testDerivativeRespondsToMeasurementNotSetpoint() {
    var pid = ThermalPID()
    _ = pid.update(temperature: 72, dt: 1, baseline: 0.2, tuning: tuning,
                   deliveredFraction: nil, emergency: false)
    let changed = ThermalPID.Tuning(setpoint: 60, kp: 0.01, ki: 0.001, kd: 0.02)
    _ = pid.update(temperature: 72, dt: 1, baseline: 0.2, tuning: changed,
                   deliveredFraction: nil, emergency: false)
    XCTAssertEqual(pid.derivative, 0)
    _ = pid.update(temperature: 76, dt: 1, baseline: 0.2, tuning: changed,
                   deliveredFraction: nil, emergency: false)
    XCTAssertEqual(pid.derivative, 4 * (1 - exp(-1.0 / 3)), accuracy: 1e-10)
  }

  func testSaturationAndRampLimitPreventWindup() {
    var saturated = ThermalPID()
    var ramped = ThermalPID()
    for _ in 0..<300 {
      let full = saturated.update(temperature: 80, dt: 1, baseline: 1, tuning: tuning,
                                  deliveredFraction: 1, emergency: false)
      XCTAssertEqual(full, 1)
      _ = ramped.update(temperature: 80, dt: 1, baseline: 0.5, tuning: tuning,
                        deliveredFraction: 0.1, emergency: false)
    }
    XCTAssertEqual(saturated.integral, 0)
    XCTAssertEqual(ramped.integral, 0.01, accuracy: 1e-10)
  }

  func testSustainedErrorBuildsCoolingAndColdReadingsUnwind() {
    var pid = ThermalPID()
    let first = pid.update(temperature: 75, dt: 1, baseline: 0.2, tuning: tuning,
                           deliveredFraction: nil, emergency: false)
    var last = first
    for _ in 0..<20 {
      last = pid.update(temperature: 75, dt: 1, baseline: 0.2, tuning: tuning,
                        deliveredFraction: nil, emergency: false)
    }
    XCTAssertGreaterThan(last, first)
    for _ in 0..<100 {
      last = pid.update(temperature: 50, dt: 1, baseline: 0.2, tuning: tuning,
                        deliveredFraction: nil, emergency: false)
    }
    XCTAssertEqual(pid.integral, 0)
    XCTAssertEqual(last, 0.2)
  }

  func testEmergencyClearsIntegral() {
    var pid = ThermalPID()
    _ = pid.update(temperature: 75, dt: 1, baseline: 0.2, tuning: tuning,
                   deliveredFraction: nil, emergency: false)
    XCTAssertGreaterThan(pid.integral, 0)
    _ = pid.update(temperature: 96, dt: 1, baseline: 1, tuning: tuning,
                   deliveredFraction: 1, emergency: true)
    XCTAssertEqual(pid.integral, 0)
  }
}
