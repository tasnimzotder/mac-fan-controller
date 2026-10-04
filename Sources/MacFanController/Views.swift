import Charts
import FanCore
import SwiftUI

struct ContentView: View {
  @ObservedObject var model: AppModel
  let onQuit: () -> Void
  @State private var tab = 0
  @State private var selectedHistoryDate: Date?
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Image(systemName: "fanblades.fill")
          .font(.system(size: 25, weight: .medium)).foregroundStyle(.mint)
          .frame(width: 48, height: 48)
          .background(.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        VStack(alignment: .leading, spacing: 3) {
          Text("Mac Fan Controller").font(.headline)
          Text(
            model.demo
              ? "Demo · simulated readings"
              : (model.recoveryUnconfirmed
                ? "Apple-control recovery unconfirmed"
            : (model.busy ? model.controlProgress : model.mode.title))
          ).font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Label(
          model.demo
            ? "Demo"
            : (model.recoveryUnconfirmed
              ? "Check helper"
            : (model.busy ? "Updating" : (model.snapshot == nil ? "Waiting" : "Live"))),
          systemImage: model.demo ? "play.rectangle" : (model.busy ? "clock" : "waveform.path")
        )
        .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(.quaternary, in: Capsule())
      }.padding(20)
      Picker("Screen", selection: $tab) {
        Text("Control").tag(0)
        Text("History").tag(1)
        Text("Settings").tag(2)
      }.labelsHidden().pickerStyle(.segmented).padding(.horizontal, 20).padding(.bottom, 16)
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if let error = model.error {
            Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout)
              .foregroundStyle(
                .orange
              ).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(
                .orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
          }
          switch tab {
          case 1: historyView
          case 2: settingsView
          default: controlView
          }
        }.padding(.horizontal, 20).padding(.bottom, 20)
      }
      Divider()
      HStack {
        Text(
          model.snapshot.map { "Updated \($0.date.formatted(date:.omitted,time:.standard))" }
            ?? "Waiting for sensors"
        ).font(.caption2).foregroundStyle(.secondary)
        Spacer()
        Button("Quit", action: onQuit).buttonStyle(.plain).font(.caption).accessibilityIdentifier(
          "quit")
      }.padding(14)
    }.frame(width: 440, height: 610)
  }
  private var controlView: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 12) {
        metric(
          "HOTTEST CPU / GPU",
          value: model.snapshot?.hottest.map { String(format: "%.0f", $0) } ?? "—", unit: "°C",
          symbol: "thermometer.medium")
        metric(
          "FASTEST FAN",
          value: model.snapshot?.fans.map(\.rpm).max().map { String(format: "%.0f", $0) } ?? "—",
          unit: "RPM", symbol: "fanblades")
      }
      if model.snapshot?.fans.isEmpty == true {
        Label(
          "No hardware fans detected. Temperature monitoring remains available.",
          systemImage: "info.circle"
        ).font(.callout).foregroundStyle(.secondary)
      }
      VStack(alignment: .leading, spacing: 10) {
        Text("COOLING MODE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
          ForEach(ControlMode.allCases, id: \.self) { mode in
            Button {
              model.setMode(mode)
            } label: {
              HStack(spacing: 8) {
                Image(systemName: modeSymbol(mode)).frame(width: 18)
                Text(mode.title).font(.caption.weight(.medium))
                Spacer(minLength: 0)
                if model.mode == mode && !model.recoveryUnconfirmed {
                  Image(systemName: "checkmark.circle.fill")
                }
              }.padding(11).frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(
                  model.mode == mode && !model.recoveryUnconfirmed ? Color.mint : Color.primary
                )
                .background(
                  model.mode == mode && !model.recoveryUnconfirmed
                    ? Color.mint.opacity(0.12) : Color.secondary.opacity(0.07),
                  in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay(
                  RoundedRectangle(cornerRadius: 10)
                    .stroke(
                      model.mode == mode && !model.recoveryUnconfirmed
                        ? Color.mint.opacity(0.4) : Color.clear, lineWidth: 1))
            }.buttonStyle(.plain)
              .disabled(model.busy || (mode != .automatic && !controlReady))
              .accessibilityIdentifier("mode-\(mode.rawValue)")
              .accessibilityAddTraits(
                model.mode == mode && !model.recoveryUnconfirmed ? [.isSelected] : [])
          }
        }
        if !model.demo && !model.helperRegistered && model.snapshot?.fans.isEmpty == false {
          Button("Enable fan control in Settings") { tab = 2 }
            .font(.caption).buttonStyle(.link)
        }
        if !model.demo && model.snapshot?.fans.isEmpty == false
          && (model.snapshot?.completeSensorReadings != true || model.snapshot?.hottest == nil)
        {
          Label(
            "Waiting for complete CPU/GPU temperature readings.", systemImage: "thermometer.medium"
          )
          .font(.caption).foregroundStyle(.secondary)
        }
        Text(
          model.recoveryUnconfirmed
            ? "The helper has not confirmed recovery. Retry Apple automatic to verify fan state."
            : modeDescription
        ).font(.caption).foregroundStyle(.secondary)
        if model.busy {
          HStack {
            ProgressView(model.controlProgress).controlSize(.small)
            Spacer()
            Button("Cancel") { model.cancelControlRequest() }
          }
        }
      }
      ForEach(model.snapshot?.fans ?? []) { fan in
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Label("Fan \(fan.id + 1)", systemImage: "fanblades").font(.subheadline.weight(.medium))
            Spacer()
            Text("\(Int(fan.rpm)) RPM").font(.system(.subheadline, design: .monospaced))
          }
          ProgressView(value: min(1, max(0, fan.rpm / max(1, fan.maximum)))).tint(.mint)
          HStack {
            Text("\(Int(fan.minimum))–\(Int(fan.maximum)) RPM").font(.caption2).foregroundStyle(
              .secondary)
            Spacer()
            Text(fan.mode == 1 ? "Manual" : (fan.mode == 0 || fan.mode == 3 ? "System" : "Unknown"))
              .font(.caption2).foregroundStyle(.secondary)
          }
          if fan.mode == 1 {
            Text("Target \(Int(fan.target)) RPM").font(.caption).foregroundStyle(.secondary)
          } else if fan.rpm == 0 {
            Text("Stopped by macOS while cool").font(.caption).foregroundStyle(.secondary)
          }
          if model.mode == .manual {
            Slider(value: manualBinding(fan.id), in: 0...1) {
              Text("Fan \(fan.id+1) speed")
            } onEditingChanged: { editing in
              if !editing { model.updateManual() }
            }
            Text(
              "Requested \(Int(fan.minimum+(fan.maximum-fan.minimum)*manualBinding(fan.id).wrappedValue)) RPM"
            ).font(.caption)
          }
        }.padding(14).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
      }
      if model.mode == .manual {
        Toggle("Sync fans by percentage of their range", isOn: $model.settings.syncFans).onChange(
          of: model.settings.syncFans
        ) { _ in model.updateManual() }.font(.caption)
      }
      if [.performance, .balanced, .quiet].contains(model.mode) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Temperature curve").font(.caption.weight(.medium))
          Chart(FanController.curve(model.mode), id: \.temperature) { point in
            LineMark(
              x: .value("Temperature °C", point.temperature),
              y: .value("Fan range %", point.fraction * 100)
            ).foregroundStyle(.mint)
          }.chartYScale(domain: 0...100).frame(height: 100)
          Text("Fast ramp-up · 15 s cooling hold · slow ramp-down").font(.caption2).foregroundStyle(
            .secondary)
        }
      }
      Button("Return to Apple automatic") { model.setMode(.automatic) }.disabled(model.busy)
        .accessibilityIdentifier("apple-automatic")
    }
  }
  private var controlReady: Bool {
    if model.demo { return true }
    guard model.helperRegistered, let snapshot = model.snapshot else { return false }
    return !snapshot.fans.isEmpty && snapshot.fans.allSatisfy(\.controllable)
      && snapshot.completeSensorReadings && snapshot.hottest != nil
  }
  private func modeSymbol(_ mode: ControlMode) -> String {
    switch mode {
    case .automatic: return "apple.logo"
    case .performance: return "bolt.fill"
    case .balanced: return "scale.3d"
    case .quiet: return "leaf"
    case .turbo: return "wind"
    case .manual: return "slider.horizontal.3"
    }
  }
  private var modeDescription: String {
    switch model.mode {
    case .automatic:
      return "macOS manages fan speeds. This is the default at launch and after sleep."
    case .performance:
      return "Earlier cooling for sustained workloads. Reaches full fan range at 80°C."
    case .balanced: return "A gradual ramp that balances fan noise and temperature."
    case .quiet: return "A later ramp for quieter operation. Thermal safeguards remain active."
    case .manual:
      return "Choose each fan’s target. High temperatures and thermal pressure override low speeds."
    case .turbo:
      return "Runs every fan at its hardware maximum for maximum cooling."
    }
  }
  private func metric(_ label: String, value: String, unit: String, symbol: String) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack {
        Image(systemName: symbol).foregroundStyle(.mint)
        Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
      }
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(value).font(.system(size: 29, weight: .medium, design: .rounded)).monospacedDigit()
        Text(unit).font(.caption).foregroundStyle(.secondary)
      }
    }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(
      .quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
  }
  private func manualBinding(_ id: Int) -> Binding<Double> {
    let index = model.settings.syncFans ? 0 : id
    return Binding(
      get: {
        model.settings.manualFractions.indices.contains(index)
          ? model.settings.manualFractions[index] : 0.5
      },
      set: { value in
        while model.settings.manualFractions.count <= index {
          model.settings.manualFractions.append(0.5)
        }
        model.settings.manualFractions[index] = value
        model.updateManual()
      })
  }
  private var historyView: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Temperature & fan history").font(.headline)
      Picker("Time range", selection: $model.historyHours) {
        ForEach([1, 6, 24, 168, 720].filter { $0 <= model.settings.historyDays * 24 }, id: \.self) { hours in
          Text(hours < 24 ? "\(hours)h" : (hours == 24 ? "24h" : "\(hours / 24)d")).tag(hours)
        }
      }.pickerStyle(.segmented).labelsHidden().onChange(of: model.historyHours) { _ in
        selectedHistoryDate = nil
        model.loadHistory()
      }
      Text("Peak readings per time bucket. Gaps mean missing samples. Stored only on this Mac.")
        .font(.caption).foregroundStyle(.secondary)
      if model.history.isEmpty { ContentUnavailableFallback() }
      else {
        historyChart(temperature: true)
        historyChart(temperature: false)
      }
    }.onAppear { model.loadHistory() }
  }
  private struct PlotReading: Identifiable {
    let point: HistoryPoint
    let segment: Int
    var id: Int64 { point.id }
  }
  private var plotReadings: [PlotReading] {
    let gap = max(120, ceil(Double(model.historyHours) * 3600 / 720 / 60) * 120)
    var segment = 0
    var previous: HistoryPoint?
    return model.history.map { point in
      if let previous, point.date.timeIntervalSince(previous.date) > gap
        || previous.temperature == nil || point.temperature == nil { segment += 1 }
      previous = point
      return PlotReading(point: point, segment: segment)
    }
  }
  private var nearestHistoryPoint: HistoryPoint? {
    guard let selectedHistoryDate else { return nil }
    return model.history.min {
      abs($0.date.timeIntervalSince(selectedHistoryDate)) < abs($1.date.timeIntervalSince(selectedHistoryDate))
    }
  }
  private func historyChart(temperature: Bool) -> some View {
    let unit = temperature ? "°C" : "RPM"
    let values = model.history.compactMap { temperature ? $0.temperature : $0.rpm }
    let minimumValue: Double = values.min() ?? 40
    let maximumValue: Double = values.max() ?? (temperature ? 60 : 0)
    let roundedMinimum = floor(minimumValue / 5.0) * 5.0 - 5.0
    let roundedMaximum = ceil(maximumValue / 5.0) * 5.0 + 5.0
    let hardwareMaximum: Double = model.snapshot?.fans.map(\.maximum).max() ?? 0
    let maximumRPM = max(maximumValue, hardwareMaximum)
    let roundedRPM = ceil(maximumRPM / 1000.0) * 1000.0
    let lower: Double = temperature ? max(0.0, roundedMinimum) : 0.0
    let upper: Double = temperature
      ? max(lower + 15.0, roundedMaximum) : max(1000.0, roundedRPM)
    let end = model.snapshot?.date ?? Date()
    let start = end.addingTimeInterval(-Double(model.historyHours) * 3600)
    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(temperature ? "Hottest CPU / GPU" : "Fastest fan").font(.subheadline.weight(.medium))
        Spacer()
        if let point = nearestHistoryPoint, let value = temperature ? point.temperature : point.rpm {
          Text("\(Int(value.rounded())) \(unit) · \(point.date.formatted(date: .omitted, time: .shortened))")
            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
      }
      Chart {
        ForEach(plotReadings) { reading in
          if let value = temperature ? reading.point.temperature : reading.point.rpm {
            LineMark(x: .value("Time", reading.point.date), y: .value(unit, value),
              series: .value("Segment", reading.segment))
              .foregroundStyle(temperature ? Color.orange : Color.mint)
            if model.history.count == 1 {
              PointMark(x: .value("Time", reading.point.date), y: .value(unit, value))
                .foregroundStyle(temperature ? Color.orange : Color.mint)
            }
          }
        }
        if let point = nearestHistoryPoint, let value = temperature ? point.temperature : point.rpm {
          RuleMark(x: .value("Selected time", point.date)).foregroundStyle(Color.secondary.opacity(0.4))
          PointMark(x: .value("Time", point.date), y: .value(unit, value))
            .foregroundStyle(temperature ? Color.orange : Color.mint)
        }
      }
      .chartXScale(domain: start...end).chartYScale(domain: lower...upper).chartLegend(.hidden)
      .chartXAxis {
        AxisMarks(values: .automatic(desiredCount: 4)) { value in
          AxisGridLine()
          AxisValueLabel {
            if let date = value.as(Date.self) {
              Text(date, format: model.historyHours > 24
                ? .dateTime.month(.abbreviated).day() : .dateTime.hour().minute())
            }
          }
        }
      }
      .chartYAxis {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
          AxisGridLine()
          AxisValueLabel {
            if let number = value.as(Double.self) { Text("\(Int(number)) \(unit)") }
          }
        }
      }
      .chartOverlay { proxy in
        GeometryReader { geometry in
          Color.clear.contentShape(Rectangle()).onContinuousHover { phase in
            switch phase {
            case .active(let location):
              let frame: Anchor<CGRect>?
              if #available(macOS 14, *) { frame = proxy.plotFrame }
              else { frame = proxy.plotAreaFrame }
              if let frame {
                let bounds = geometry[frame]
                selectedHistoryDate = bounds.contains(location)
                  ? proxy.value(atX: location.x - bounds.minX, as: Date.self) : nil
              }
            case .ended: selectedHistoryDate = nil
            }
          }
        }
      }.frame(height: 180)
      .accessibilityLabel(temperature ? "CPU and GPU temperature history in degrees Celsius" : "Highest fan speed history in RPM")
    }.padding(12).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
  }
  private var settingsView: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Image(systemName: "gearshape.fill").foregroundStyle(.mint)
        VStack(alignment: .leading, spacing: 4) {
          Text("Preferences").font(.headline)
          Text("Display, history, and fan-control access").font(.caption).foregroundStyle(
            .secondary)
        }
      }
      Text("Menu bar").font(.subheadline.weight(.semibold))
      Toggle("Show temperature", isOn: $model.settings.showTemperature)
      Toggle("Show fan RPM", isOn: $model.settings.showRPM)
      Toggle("Show each fan", isOn: $model.settings.showBothFans).disabled(!model.settings.showRPM)
      Divider()
      Toggle(
        "Launch at login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) })
      ).disabled(model.demo)
      Picker("Keep history", selection: $model.settings.historyDays) {
        Text("1 day").tag(1)
        Text("7 days").tag(7)
        Text("30 days").tag(30)
      }
      Divider()
      Text("Fan-control helper").font(.headline)
      Label(
        model.helperStatus,
        systemImage: model.helperRegistered ? "checkmark.shield" : "shield.lefthalf.filled"
      )
      .font(.caption.weight(.medium))
      .foregroundStyle(model.helperRegistered ? Color.mint : Color.secondary)
      .padding(10).frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
      Text(
        "Administrator approval enables fan writes. Monitoring works without it. The helper returns to Apple control if the app heartbeat stops."
      ).font(.caption).foregroundStyle(.secondary)
      HStack {
        Button("Enable helper") { model.installHelper() }.disabled(
          model.demo || model.busy || model.snapshot?.fans.isEmpty == true)
        Button("Remove helper") { model.uninstallHelper() }.disabled(
          model.demo || !model.helperRegistered || model.busy)
      }
      Text("Every launch starts in Apple automatic. Use one fan-control app at a time.").font(
        .caption
      ).foregroundStyle(.secondary)
      Divider()
      HStack {
        Text("App version")
        Spacer()
        Text(
          Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Development build"
        )
        .textSelection(.enabled)
        .accessibilityIdentifier("app-version")
      }.font(.caption).foregroundStyle(.secondary)
    }.onChange(of: model.settings) { _ in model.saveSettings() }
  }
}
struct ContentUnavailableFallback: View {
  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: "chart.xyaxis.line").font(.largeTitle)
      Text("History will appear as readings arrive.").font(.callout)
    }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 35)
  }
}
