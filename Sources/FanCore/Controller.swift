import Foundation

public struct CurvePoint: Equatable {
  public var temperature: Double
  public var fraction: Double
}
public struct FanController {
  private var filtered: Double?
  private var previousTemperature: Double?
  private var previousDate: Date?
  private var lastTargets: [Int: Double] = [:]
  private var coolingSince: [Int: Date] = [:]
  private var previousMode: ControlMode?
  public init() {}
  public static func curve(_ mode: ControlMode) -> [CurvePoint] {
    let values: [(Double, Double)]
    switch mode {
    case .performance: values = [(40, 0.15), (50, 0.30), (60, 0.55), (70, 0.80), (80, 1)]
    case .balanced: values = [(40, 0.05), (50, 0.10), (60, 0.25), (70, 0.50), (80, 0.75), (90, 1)]
    case .quiet: values = [(50, 0), (65, 0.15), (75, 0.35), (85, 0.70), (92, 1)]
    case .turbo: values = [(0, 1), (125, 1)]
    default: values = [(40, 0), (80, 1)]
    }
    return values.map { CurvePoint(temperature: $0.0, fraction: $0.1) }
  }
  public static func fraction(temperature: Double, mode: ControlMode) -> Double {
    let points = curve(mode)
    if temperature <= points[0].temperature { return points[0].fraction }
    for pair in zip(points, points.dropFirst()) where temperature <= pair.1.temperature {
      let t = (temperature - pair.0.temperature) / (pair.1.temperature - pair.0.temperature)
      return pair.0.fraction + t * (pair.1.fraction - pair.0.fraction)
    }
    return 1
  }
  public mutating func reset() { self = FanController() }
  // nil means release to Apple; zero RPM is never requested in forced mode.
  public mutating func targets(
    _ snapshot: Snapshot, mode: ControlMode, manual: [Double] = [], now: Date = Date()
  ) throws -> [Int: Double]? {
    if mode == .automatic {
      reset()
      return nil
    }
    guard !snapshot.fans.isEmpty,
      snapshot.fans.allSatisfy({ $0.controllable && $0.rpm.isFinite && $0.rpm >= 0 })
    else {
      throw FanError("Fan limits unavailable; returning to Apple automatic.")
    }
    guard snapshot.completeSensorReadings,
      snapshot.sensors.allSatisfy({
        $0.temperature.isFinite && $0.temperature > 0 && $0.temperature < 125
      }), let raw = snapshot.hottest, raw.isFinite, raw > 0,
      raw < 125,
      now.timeIntervalSince(snapshot.date) < 6, now.timeIntervalSince(snapshot.date) > -2
    else {
      throw FanError("Temperature readings unavailable or stale; returning to Apple automatic.")
    }
    let changedMode = previousMode != mode
    if changedMode {
      reset()
      previousMode = mode
    }
    let dt = previousDate.map { snapshot.date.timeIntervalSince($0) } ?? 1
    guard dt > 0, dt <= 6 else {
      reset()
      throw FanError("Sampling interrupted; returning to Apple automatic.")
    }
    let old = filtered ?? raw
    // 2 s rising time constant, 10 s falling; raw temperature still drives emergency cooling.
    let tau = raw > old ? 2.0 : 10.0
    let temperature = old + (raw - old) * (1 - exp(-dt / tau))
    filtered = temperature
    let trend = previousTemperature.map { max(0, (raw - $0) / dt) } ?? 0
    previousTemperature = raw
    previousDate = snapshot.date
    let emergency = raw >= 95 || snapshot.thermalState >= 2
    // Short bounded lookahead anticipates rapidly increasing load, not a PID integral.
    let predicted = max(raw, temperature) + min(5, trend * 2)
    let proportion = Self.fraction(temperature: predicted, mode: mode)
    var targets: [Int: Double] = [:]
    for (index, fan) in snapshot.fans.enumerated() {
      if mode == .manual {
        guard manual.indices.contains(index), manual[index].isFinite,
          (0...1).contains(manual[index])
        else { throw FanError("Invalid manual fan target.") }
      }
      let amount = mode == .manual ? manual[index] : proportion
      let desired = emergency ? fan.maximum : fan.minimum + (fan.maximum - fan.minimum) * amount
      let previous = lastTargets[fan.id] ?? max(fan.minimum, fan.rpm)
      var target = desired
      if !emergency && mode != .turbo {
        if changedMode && desired <= previous {
          target = desired
        } else if desired < previous - 150 {
          if coolingSince[fan.id] == nil { coolingSince[fan.id] = snapshot.date }
          if snapshot.date.timeIntervalSince(coolingSince[fan.id]!) < 15 {
            target = previous
          } else {
            target = max(desired, previous - 100 * dt)
          }
        } else if desired > previous + 150 {
          coolingSince[fan.id] = nil
          target = min(desired, previous + 1200 * dt)
        } else {
          coolingSince[fan.id] = nil
          target = changedMode ? desired : previous
        }
      }
      targets[fan.id] = min(fan.maximum, max(fan.minimum, target.rounded()))
    }
    lastTargets = targets
    return targets
  }
}
