import AppKit
import FanCore
import Foundation
import ServiceManagement

@MainActor enum Maintenance {
  /// Exercise the authenticated helper for twenty seconds, then explicitly release control.
  static func verifyPerformance(presets: Bool = false) {
    guard NSRunningApplication.runningApplications(
      withBundleIdentifier: "com.tasnimzotder.mac-fan-controller"
    ).allSatisfy({ $0.processIdentifier == ProcessInfo.processInfo.processIdentifier }),
      NSRunningApplication.runningApplications(
        withBundleIdentifier: "com.crystalidea.macsfancontrol"
      ).isEmpty
    else {
      fputs("Quit both fan-control GUIs before verifying Performance.\n", stderr)
      exit(1)
    }
    let connection = NSXPCConnection(machServiceName: helperLabel, options: .privileged)
    connection.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)
    do {
      try connection.setCodeSigningRequirement(signingRequirement(
        for: Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/mfc-helper")))
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    connection.resume()
    func command(_ mode: ControlMode) async throws {
      let data = try JSONEncoder().encode(HelperRequest(mode: mode))
      let response: Data = try await withCheckedThrowingContinuation { continuation in
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
          continuation.resume(throwing: error)
        }) as? FanHelperProtocol else {
          continuation.resume(throwing: FanError("Helper connection failed."))
          return
        }
        proxy.command(data) { continuation.resume(returning: $0) }
      }
      let reply = try JSONDecoder().decode(HelperReply.self, from: response)
      guard reply.mode == mode, reply.error == nil else {
        throw FanError(reply.error ?? "Helper changed control mode.")
      }
    }
    Task { @MainActor in
      var failure: Error?
      do {
        let hardware = try SMC()
        let modes: [ControlMode] = presets ? [.quiet, .balanced, .performance, .turbo] : [.performance]
        for mode in modes {
          for _ in 0..<(presets ? 2 : 10) {
            try await command(mode)
            try await Task.sleep(nanoseconds: 2_000_000_000)
            let snapshot = try hardware.snapshot()
            guard !snapshot.fans.isEmpty, snapshot.fans.allSatisfy({
              $0.mode == 1 && ($0.minimum...$0.maximum).contains($0.target)
            }) else { throw FanError("Firmware lost manual mode or its target.") }
            if mode == .turbo {
              guard snapshot.fans.allSatisfy({ abs($0.target - $0.maximum) < 100 }) else {
                throw FanError("Turbo target did not reach the hardware maximum.")
              }
            }
            print(mode.title + ": " + snapshot.fans.map {
              "fan \($0.id + 1) \(Int($0.rpm)) RPM, target \(Int($0.target))"
            }.joined(separator: "; "))
          }
        }
      } catch { failure = error }
      do {
        try await command(.automatic)
        let hardware = try SMC()
        guard try hardware.snapshot().fans.allSatisfy({ $0.mode == 0 || $0.mode == 3 }),
          hardware.number("Ftst") != 1
        else { throw FanError("Apple automatic readback failed.") }
        print("Apple automatic and firmware unlock release verified.")
      } catch { failure = error }
      connection.invalidate()
      if let failure { fputs("Verification failed: \(failure.localizedDescription)\n", stderr); exit(1) }
      print(presets ? "All cooling presets and Turbo verified." : "Performance remained active for twenty seconds.")
      exit(0)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
      connection.invalidate()
      fputs("Verification timed out; helper watchdog will restore Apple control.\n", stderr)
      exit(1)
    }
    RunLoop.current.run()
  }

  /// Refresh a stale launchd signature pin only when firmware already owns all fans.
  static func restoreAutomatic() {
    guard getuid() == 0 else {
      fputs("Automatic recovery requires administrator authorization.\n", stderr)
      exit(1)
    }
    do {
      try SMC().restoreAutomatic()
      print("Apple automatic modes, zero targets, and unlock release verified.")
    } catch {
      fputs("Automatic recovery failed: \(error.localizedDescription)\n", stderr)
      exit(1)
    }
  }

  static func repairHelper(register: Bool = true) {
    Task { @MainActor in
      do {
        guard NSRunningApplication.runningApplications(
          withBundleIdentifier: "com.tasnimzotder.mac-fan-controller"
        ).allSatisfy({ $0.processIdentifier == ProcessInfo.processInfo.processIdentifier }) else {
          throw FanError("Quit Mac Fan Controller before repairing its helper.")
        }
        let hardware = try SMC()
        let snapshot = try hardware.snapshot()
        guard snapshot.fans.allSatisfy({ $0.mode == 0 || $0.mode == 3 }),
          snapshot.fans.allSatisfy({ hardware.number("F\($0.id)Tg") == 0 }),
          hardware.number("Ftst") != 1
        else { throw FanError("Repair aborted: fans must be in Apple automatic mode.") }
        let service = SMAppService.daemon(plistName: helperLabel + ".plist")
        if service.status != .notRegistered && service.status != .notFound {
          try await service.unregister()
        }
        if !register {
          print("Apple automatic verified; helper unregistered for update.")
          exit(0)
        }
        do { try service.register() } catch {
          guard service.status == .requiresApproval else { throw error }
        }
        if service.status == .requiresApproval {
          SMAppService.openSystemSettingsLoginItems()
          print("Helper registered; approval required in System Settings.")
        } else {
          guard service.status == .enabled else { throw FanError("Helper registration is not enabled.") }
          print("Apple automatic verified; helper registration refreshed.")
        }
        exit(0)
      } catch {
        fputs("Cannot repair helper: \(error.localizedDescription)\n", stderr)
        exit(1)
      }
    }
    RunLoop.current.run()
  }

  static func unregisterHelper() {
    let service = SMAppService.daemon(plistName: helperLabel + ".plist")
    guard service.status != .notRegistered && service.status != .notFound else {
      print("Fan helper is not registered.")
      return
    }
    // Always verify release before removing the watchdog. Quit the running GUI first.
    let connection = NSXPCConnection(machServiceName: helperLabel, options: .privileged)
    connection.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)
    do {
      try connection.setCodeSigningRequirement(
        signingRequirement(
          for: Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/mfc-helper")))
    } catch {
      fputs("\(error.localizedDescription)\n", stderr)
      exit(1)
    }
    connection.resume()
    guard
      let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
        fputs("Cannot remove helper: \(error.localizedDescription). Quit the app first.\n", stderr)
        exit(1)
      }) as? FanHelperProtocol
    else { exit(1) }
    do {
      proxy.command(try JSONEncoder().encode(HelperRequest(mode: .automatic))) { data in
        Task { @MainActor in
          do {
            let reply = try JSONDecoder().decode(HelperReply.self, from: data)
            guard reply.mode == .automatic, reply.error == nil else {
              throw FanError(reply.error ?? "Automatic restoration not confirmed.")
            }
            connection.invalidate()
            try await service.unregister()
            print("Apple automatic restored; helper unregistered.")
            exit(0)
          } catch {
            fputs("Cannot remove helper: \(error.localizedDescription)\n", stderr)
            exit(1)
          }
        }
      }
    } catch {
      fputs("\(error.localizedDescription)\n", stderr)
      exit(1)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + FanAcquisition.requestTimeout) {
      fputs("Helper timed out. Removal aborted; watchdog remains installed.\n", stderr)
      exit(1)
    }
    RunLoop.current.run()
  }
}
