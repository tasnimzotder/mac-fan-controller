import FanCore
import Foundation
import ServiceManagement

@MainActor enum Maintenance {
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
            try service.unregister()
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
