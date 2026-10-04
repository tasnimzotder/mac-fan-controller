import Darwin
import FanCore
import Foundation
import MachO
import OSLog

final class Helper: NSObject, NSXPCListenerDelegate, FanHelperProtocol {
  private let queue = DispatchQueue(label: "fan-control", qos: .userInitiated)
  private let session: ControlSession
  private var timer: DispatchSourceTimer?
  private let logger = Logger(subsystem: "com.tasnimzotder.mac-fan-controller", category: "helper")
  private var owner: NSXPCConnection?
  private let cancellation: ControlCancellation
  init(session: ControlSession, cancellation: ControlCancellation) {
    self.cancellation = cancellation
    self.session = session
    super.init()
    timer = DispatchSource.makeTimerSource(queue: queue)
    timer?.schedule(deadline: .now(), repeating: 1)
    timer?.setEventHandler { [weak self] in self?.session.tick() }
    timer?.resume()
  }
  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection)
    -> Bool
  {
    guard connection.effectiveUserIdentifier != 0 else { return false }
    connection.exportedInterface = NSXPCInterface(with: FanHelperProtocol.self)
    connection.exportedObject = self
    // Single controller lease. Prevent a second legitimate instance racing the first.
    let lease = UUID()
    let accepted = queue.sync { () -> Bool in
      guard owner == nil else { return false }
      owner = connection
      cancellation.begin(lease)
      return true
    }
    guard accepted else { return false }
    connection.invalidationHandler = { [weak self, weak connection] in
      guard let self else { return }
      self.cancellation.cancel(lease)
      self.queue.async {
        if self.owner === connection {
          self.owner = nil
          self.session.release()
        }
      }
    }
    connection.interruptionHandler = connection.invalidationHandler
    connection.resume()
    return true
  }
  func command(_ data: Data, reply: @escaping (Data) -> Void) {
    queue.async {
      do {
        guard data.count < 4096 else { throw FanError("Request too large.") }
        let request = try JSONDecoder().decode(HelperRequest.self, from: data)
        let started = ProcessInfo.processInfo.systemUptime
        self.logger.notice("Control request: \(request.mode.rawValue, privacy: .public)")
        let response = self.session.command(request)
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        self.logger.notice(
          "Control response after \(elapsed, privacy: .public)s: \(response.error ?? "success", privacy: .public)"
        )
        reply((try? JSONEncoder().encode(response)) ?? Data())
        return
      } catch {
        self.session.release()
      }
      let response = HelperReply(mode: self.session.mode, error: "Invalid helper request.")
      reply((try? JSONEncoder().encode(response)) ?? Data())
    }
  }
  func shutdown() { queue.sync { session.release() } }
}

guard getuid() == 0 else {
  fputs("Fan helper must run via its authorized launch daemon.\n", stderr)
  exit(1)
}
do {
  let smc = try SMC()
  let cancellation = ControlCancellation()
  smc.controlCancelled = { cancellation.cancelled }
  let directory = URL(
    fileURLWithPath: "/Library/Application Support/Mac Fan Controller", isDirectory: true)
  try FileManager.default.createDirectory(
    at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
  let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
  guard attributes[.type] as? FileAttributeType == .typeDirectory,
    (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0
  else { throw FanError("Recovery directory must be a root-owned directory.") }
  try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
  let marker = directory.appendingPathComponent("override.pending")
  let session = ControlSession(
    hardware: smc, recoveryPending: FileManager.default.fileExists(atPath: marker.path),
    beginOverride: {
      try Data("1\n".utf8).write(to: marker, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
      let handle = try FileHandle(forWritingTo: marker)
      try handle.synchronize()
      try handle.close()
    },
    endOverride: {
      if FileManager.default.fileExists(atPath: marker.path) {
        try FileManager.default.removeItem(at: marker)
      }
    })
  let delegate = Helper(session: session, cancellation: cancellation)
  let listener = NSXPCListener(machServiceName: helperLabel)
  // launchd may supply a relative argv[0] for a BundleProgram.
  // Resolve the loaded executable instead of interpreting it against the daemon's cwd.
  var pathSize: UInt32 = 0
  _ = _NSGetExecutablePath(nil, &pathSize)
  var executablePath = [CChar](repeating: 0, count: Int(pathSize))
  guard _NSGetExecutablePath(&executablePath, &pathSize) == 0 else {
    throw FanError("Cannot resolve helper executable path.")
  }
  let executable = URL(fileURLWithPath: String(cString: executablePath))
    .resolvingSymlinksInPath().deletingLastPathComponent()
    .appendingPathComponent("mac-fan-controller")
  listener.setConnectionCodeSigningRequirement(try signingRequirement(for: executable))
  listener.delegate = delegate
  signal(SIGTERM, SIG_IGN)
  signal(SIGINT, SIG_IGN)
  let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
  let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
  termination.setEventHandler {
    cancellation.set(true)
    delegate.shutdown()
    exit(0)
  }
  termination.resume()
  interrupt.setEventHandler {
    cancellation.set(true)
    delegate.shutdown()
    exit(0)
  }
  interrupt.resume()
  listener.resume()
  withExtendedLifetime((delegate, termination, interrupt)) { RunLoop.current.run() }
} catch {
  Logger(subsystem: "com.tasnimzotder.mac-fan-controller", category: "helper")
    .error("Helper startup failed: \(error.localizedDescription, privacy: .public)")
  fputs("\(error.localizedDescription)\n", stderr)
  exit(1)
}
