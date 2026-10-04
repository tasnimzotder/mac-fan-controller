import Foundation

/// Temperature feedback supplements the preset curve; output is a fraction of fan range.
/// Positive error means too hot, so this uses cooling-action PID (positive measurement D).
struct ThermalPID {
  struct Tuning {
    let setpoint: Double
    let kp: Double
    let ki: Double
    let kd: Double

    static func preset(_ mode: ControlMode) -> Tuning? {
      switch mode {
      case .performance: return Tuning(setpoint: 65, kp: 0.012, ki: 0.0008, kd: 0.025)
      case .balanced: return Tuning(setpoint: 75, kp: 0.010, ki: 0.0006, kd: 0.020)
      case .quiet: return Tuning(setpoint: 82, kp: 0.008, ki: 0.0004, kd: 0.015)
      default: return nil
      }
    }
  }

  private(set) var integral = 0.0
  private(set) var derivative = 0.0
  private var previousTemperature: Double?
  private var previousError: Double?
  private var previousDemand: Double?

  mutating func update(
    temperature: Double, dt: Double, baseline: Double, tuning: Tuning,
    deliveredFraction: Double?, emergency: Bool
  ) -> Double {
    let error = temperature - tuning.setpoint
    let slope = previousTemperature.map { (temperature - $0) / dt } ?? 0
    // Derivative on measurement avoids a kick when the temperature setpoint changes.
    derivative += (slope - derivative) * (1 - exp(-dt / 3))
    let p = tuning.kp * error
    let d = tuning.kd * derivative
    let delta = tuning.ki * (error + (previousError ?? error)) * 0.5 * dt
    let candidate = min(0.20, max(0, integral + delta))
    let candidateCorrection = p + candidate + d
    let outputSaturated = baseline + candidateCorrection >= 1 || candidateCorrection >= 0.35
    let rampLimited = deliveredFraction.map {
      (previousDemand ?? $0) > $0 + 0.04
    } ?? false
    // Allow unwinding, but never accumulate positive error against output/ramp limits.
    if emergency {
      integral = 0
    } else if delta <= 0 || (!outputSaturated && !rampLimited) {
      integral = candidate
    }
    let correction = min(0.35, max(0, p + integral + d))
    let demand = min(1, max(baseline, baseline + correction))
    previousTemperature = temperature
    previousError = error
    previousDemand = demand
    return demand
  }
}
