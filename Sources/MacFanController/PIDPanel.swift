import FanCore
import Foundation
import SwiftUI

struct PIDPanel: View {
  let telemetry: PIDTelemetry?
  let mode: ControlMode
  let demo: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label("Live PID", systemImage: "waveform.path").font(.subheadline.weight(.medium))
        Spacer()
        if let pid = telemetry {
          Text(pid.date.formatted(date: .omitted, time: .standard))
            .font(.caption2).foregroundStyle(.secondary)
        }
      }
      if let pid = telemetry {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
          metric("Temperature · filtered", String(format: "%.1f °C", pid.temperature))
          metric("Setpoint", String(format: "%.1f °C", pid.setpoint))
          metric("Error", String(format: "%+.2f °C", pid.error))
          metric("Temperature rate", String(format: "%+.3f °C/s", pid.temperatureRate))
        }
        HStack(spacing: 12) {
          metric("Kp · /°C", String(format: "%.4f", pid.kp))
          metric("Ki · /(°C·s)", String(format: "%.4f", pid.ki))
          metric("Kd · s/°C", String(format: "%.4f", pid.kd))
        }
        HStack(spacing: 12) {
          metric("P contribution", percent(pid.proportional))
          metric("I contribution", percent(pid.integral))
          metric("D contribution", percent(pid.derivative))
        }
        HStack(spacing: 12) {
          metric("Curve", percent(pid.baseline))
          metric("PID correction", percent(pid.correction))
          metric("Demand", percent(pid.demand))
        }
        ForEach(pid.appliedTargets.keys.sorted(), id: \.self) { id in
          HStack {
            Text("Fan \(id + 1) target")
            Spacer()
            Text("\(Int(pid.appliedTargets[id] ?? 0)) RPM").monospacedDigit()
          }.font(.caption)
        }
        if pid.emergency {
          Label("Emergency cooling · maximum RPM", systemImage: "exclamationmark.triangle")
            .font(.caption).foregroundStyle(.orange)
        } else if pid.integrationLimited || pid.outputLimited {
          Text(pid.integrationLimited ? "Integral limited by safety or ramp bounds" : "Output limited")
            .font(.caption).foregroundStyle(.secondary)
        }
        Text(String(format: "Raw %.1f °C · sample %.3f s", pid.rawTemperature, pid.sampleInterval))
          .font(.caption2).foregroundStyle(.secondary)
        Text("Percentages use each fan’s RPM range. Demand precedes ramp limits; targets include them.")
          .font(.caption2).foregroundStyle(.secondary)
      } else {
        Text(inactiveMessage).font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(12)
    .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
  }

  private var inactiveMessage: String {
    if demo { return "Demo mode has no live helper PID readings." }
    switch mode {
    case .performance, .balanced, .quiet: return "Waiting for fresh PID readings from the helper…"
    case .turbo: return "Turbo requests maximum RPM; PID is inactive."
    case .manual: return "Manual uses your selected speeds; PID is inactive."
    case .automatic: return "Select Quiet, Balanced, or Performance to see live PID readings."
    }
  }

  private func percent(_ value: Double) -> String {
    String(format: "%+.1f%%", value * 100)
  }

  private func metric(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label).font(.caption2).foregroundStyle(.secondary)
      Text(value).font(.system(.caption, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.8)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
