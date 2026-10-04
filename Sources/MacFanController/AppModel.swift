import AppKit
import FanCore
import ServiceManagement
import SwiftUI

@MainActor final class AppModel: ObservableObject {
  @Published var snapshot: Snapshot?
  @Published var settings = Settings()
  @Published var mode = ControlMode.automatic
  @Published var history: [HistoryPoint] = []
  @Published var error: String?
  @Published var helperStatus = "Not installed"
  @Published var busy = false
  @Published private(set) var controlProgress = "Requesting fan control…"
  @Published var recoveryUnconfirmed = false
  private var requestFailure: ((String) -> Void)?
  @Published var loginEnabled = false
  var onUpdate: (() -> Void)?
  private let monitor = Monitor()
  private var storage: Storage?
  private var connection: NSXPCConnection?
  private var timer: Timer?
  private var pending = false
  private var lastRecord = Date.distantPast
  private var sleepObserver: NSObjectProtocol?
  private var wakeObserver: NSObjectProtocol?
  private var sleeping = false
  let demo = CommandLine.arguments.contains("--demo")
  private var demoTick = 0
  private var service: SMAppService { .daemon(plistName: helperLabel + ".plist") }
  init() {
    let base =
      ProcessInfo.processInfo.environment["MFC_DATA_DIR"]
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support/Mac Fan Controller"
      ).path
    do {
      storage = try Storage(path: base + "/" + (demo ? "demo.sqlite3" : "fan-controller.sqlite3"))
      settings = try storage!.settings()
    } catch { self.error = error.localizedDescription }
    loginEnabled = SMAppService.mainApp.status == .enabled
    refreshHelperStatus()
    sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.sleeping = true
        if self?.pending == true {
          self?.connection?.invalidate()
          self?.requestFailure?(
            "Sleep cancelled fan acquisition; Apple-control recovery is unconfirmed.")
        } else {
          self?.setMode(.automatic)
        }
      }
    }
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.sleeping = false
        self?.mode = .automatic
        if self?.recoveryUnconfirmed == true && self?.service.status == .enabled {
          self?.setMode(.automatic)
        }
        self?.poll()
      }
    }
    if demo, let storage,
      (try? storage.history(since: Date().addingTimeInterval(-86400)))?.isEmpty == true
    {
      for minute in 1...120 {
        let t = 58 + sin(Double(minute) / 10) * 12
        try? storage.record(
          Snapshot(
            date: Date().addingTimeInterval(-Double(minute) * 60),
            fans: [Fan(id: 0, rpm: 2000 + (t - 46) * 80, minimum: 1350, maximum: 5349)],
            sensors: [Sensor(id: "CPU", temperature: t)]), retentionDays: settings.historyDays)
      }
    }
    poll()
    timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.poll() }
    }
  }
  func refreshHelperStatus() {
    if demo {
      helperStatus = "Demo · simulated hardware"
      return
    }
    switch service.status {
    case .enabled: helperStatus = "Enabled"
    case .requiresApproval: helperStatus = "Approval needed in System Settings"
    case .notRegistered: helperStatus = "Not installed"
    case .notFound: helperStatus = "Helper not found"
    @unknown default: helperStatus = "Unknown"
    }
  }
  func installHelper() {
    guard !demo, !busy, !pending else { return }
    do {
      if service.status != .enabled { try service.register() }
      refreshHelperStatus()
      if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    if service.status == .enabled {
      controlProgress = "Connecting to helper…"
      busy = true
        send(.init(mode: .automatic))
      }
    } catch { self.error = error.localizedDescription }
  }
  func uninstallHelper() {
    setMode(.automatic) { [weak self] success in
      guard let self, success else { return }
      do {
        self.connection?.invalidate()
        self.connection = nil
        try self.service.unregister()
        self.refreshHelperStatus()
      } catch { self.error = error.localizedDescription }
    }
  }
  func setLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      loginEnabled = SMAppService.mainApp.status == .enabled
    } catch { self.error = error.localizedDescription }
  }
  func saveSettings() {
    do {
      try storage?.save(settings)
      onUpdate?()
    } catch { self.error = error.localizedDescription }
  }
  func setMode(_ value: ControlMode, completion: ((Bool) -> Void)? = nil) {
    if demo {
      mode = value
      completion?(true)
      return
    }
    guard !busy, !pending else {
      completion?(false)
      return
    }
    if value != .automatic {
      guard NSRunningApplication.runningApplications(
        withBundleIdentifier: "com.crystalidea.macsfancontrol"
      ).isEmpty else {
        error = "Quit Macs Fan Control before enabling fan control; both apps write the same firmware keys."
        completion?(false)
        return
      }
      guard let snapshot, !snapshot.fans.isEmpty, snapshot.fans.allSatisfy(\.controllable),
        snapshot.hottest != nil
      else {
        error = "Fan control needs valid fan and CPU/GPU readings."
        completion?(false)
        return
      }
      guard service.status == .enabled else {
        error = "Enable the fan helper in Settings first."
        completion?(false)
        return
      }
    }
    if value == .automatic && connection == nil && service.status != .enabled {
      if recoveryUnconfirmed {
        error =
          "Recovery is unconfirmed. Enable the helper to verify Apple automatic before quitting."
        completion?(false)
        return
      }
      mode = .automatic
      completion?(true)
      return
    }
    controlProgress = value == .automatic ? "Returning to Apple automatic…"
      : (mode == .automatic ? "Requesting fan control…" : "Applying preset…")
    busy = true
    send(.init(mode: value, fractions: manualFractions()), completion: completion)
  }
  private func manualFractions() -> [Double] {
    (snapshot?.fans ?? []).enumerated().map { index, _ in
      let i = settings.syncFans ? 0 : index
      return settings.manualFractions.indices.contains(i) ? settings.manualFractions[i] : 0.5
    }
  }
  func updateManual() {
    saveSettings()
    if !demo && mode == .manual && !pending {
      send(.init(mode: .manual, fractions: manualFractions()))
    }
  }
  private func connect() throws -> NSXPCConnection {
    if let connection { return connection }
    let peer = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/mfc-helper")
    let c = NSXPCConnection(machServiceName: helperLabel, options: .privileged)
    c.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)
    c.setCodeSigningRequirement(try signingRequirement(for: peer))
    c.invalidationHandler = { [weak self, weak c] in
      Task { @MainActor in
        guard let self, let c, self.connection === c else { return }
        self.connection = nil
        self.recoveryUnconfirmed = true
        if let failure = self.requestFailure {
          failure("Helper disconnected. Apple-control recovery is not confirmed.")
        } else {
          self.mode = .automatic
          self.error = "Helper disconnected. Apple-control recovery is not confirmed."
          self.onUpdate?()
        }
      }
    }
    c.interruptionHandler = { [weak self, weak c] in
      Task { @MainActor in
        guard let self, let c, self.connection === c else { return }
        c.invalidate()
      }
    }
    c.resume()
    connection = c
    return c
  }
  private func send(_ request: HelperRequest, completion: ((Bool) -> Void)? = nil) {
    guard !demo else {
      completion?(true)
      return
    }
    guard !pending else {
      completion?(false)
      return
    }
    pending = true
    // Complete at most once; stale replies cannot change a later request.
    let token = UUID()
    activeRequest = token
    let finish: (HelperReply?, String?) -> Void = { [weak self] response, message in
      Task { @MainActor in
        guard let self, self.activeRequest == token else { return }
        self.activeRequest = nil
        self.requestFailure = nil
        self.pending = false
        self.busy = false
        if let response, !(self.sleeping && response.mode != .automatic) {
          self.recoveryUnconfirmed = response.error?.contains("restoration failed") == true
          self.mode = response.mode
          self.error = response.error
          completion?(response.error == nil)
        } else {
          self.recoveryUnconfirmed = true
          self.mode = .automatic
          self.error =
            message ?? "Sleep cancelled fan acquisition; Apple-control recovery is unconfirmed."
          self.connection?.invalidate()
          self.connection = nil
          completion?(false)
        }
        self.onUpdate?()
      }
    }
    requestFailure = { message in finish(nil, message) }
    do {
      let c = try connect()
      guard
        let proxy = c.remoteObjectProxyWithErrorHandler({ finish(nil, $0.localizedDescription) })
          as? FanHelperProtocol
      else { throw FanError("Helper connection failed.") }
      proxy.command(try JSONEncoder().encode(request)) { data in
        do { finish(try JSONDecoder().decode(HelperReply.self, from: data), nil) } catch {
          finish(nil, "Invalid helper response.")
        }
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + FanAcquisition.requestTimeout) {
        finish(nil, "Helper timed out; awaiting Apple-control recovery.")
      }
    } catch { finish(nil, error.localizedDescription) }
  }
  private var activeRequest: UUID?
  private var reading = false
  func poll() {
    refreshHelperStatus()
    guard !sleeping, !reading else { return }
    if mode != .automatic && !pending && !demo {
      send(.init(mode: mode, fractions: manualFractions()))
    } else if recoveryUnconfirmed && !pending && !demo && service.status == .enabled {
      send(.init(mode: .automatic, statusOnly: true))
    }
    if demo {
      demoTick += 1
      let t = 58 + sin(Double(demoTick) / 7) * 8
      let s = Snapshot(
        fans: [
          Fan(id: 0, rpm: 2550, minimum: 1350, maximum: 5349),
          Fan(id: 1, rpm: 2750, minimum: 1458, maximum: 5777),
        ], sensors: [Sensor(id: "CPU", temperature: t), Sensor(id: "GPU", temperature: t - 4)])
      accept(s)
      return
    }
    reading = true
    monitor.read { [weak self] result in
      Task { @MainActor in
        guard let self else { return }
        self.reading = false
        switch result {
        case .success(let snapshot): self.accept(snapshot)
        case .failure(let error):
          self.snapshot = nil
          self.error = error.localizedDescription
          if self.mode != .automatic { self.setMode(.automatic) }
          self.onUpdate?()
        }
      }
    }
  }
  private func accept(_ s: Snapshot) {
    snapshot = s
    if Date().timeIntervalSince(lastRecord) >= 10 {
      lastRecord = Date()
      do {
        try storage?.record(s, retentionDays: settings.historyDays)
        history =
          try storage?.history(
            since: Date().addingTimeInterval(-86400 * Double(settings.historyDays))) ?? []
      } catch { self.error = error.localizedDescription }
    }
    onUpdate?()
  }
  var trayTitle: String {
    var parts: [String] = []
    if settings.showTemperature {
      parts.append(snapshot?.hottest.map { String(format: "%.0f°", $0) } ?? "—°")
    }
    if settings.showRPM {
      if let fans = snapshot?.fans, !fans.isEmpty {
        let values = settings.showBothFans ? fans.map(\.rpm) : [fans.map(\.rpm).max()!]
        parts.append(values.map { String(format: "%.0f", $0) }.joined(separator: "/") + " rpm")
      } else {
        parts.append("— rpm")
      }
    }
    return parts.joined(separator: " · ")
  }
  func quit(_ completion: @escaping (Bool) -> Void) {
    if mode == .automatic && connection == nil && !recoveryUnconfirmed {
      timer?.invalidate()
      completion(true)
      return
    }
    setMode(.automatic) { [weak self] success in
      if success { self?.timer?.invalidate() }
      completion(success)
    }
  }
}

// All SMC reads belong to this one queue; UI code never touches its connection.
private final class Monitor: @unchecked Sendable {
  private let queue = DispatchQueue(label: "fan-monitor", qos: .utility)
  private var smc: SMC?
  func read(_ completion: @escaping (Result<Snapshot, Error>) -> Void) {
    queue.async {
      do {
        if self.smc == nil { self.smc = try SMC() }
        completion(.success(try self.smc!.snapshot()))
      } catch { completion(.failure(error)) }
    }
  }
}
