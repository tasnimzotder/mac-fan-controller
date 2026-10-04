import AppKit
import FanCore
import SwiftUI

@main struct MacFanApplication {
  @MainActor static func main() {
    if CommandLine.arguments.contains("--unregister-helper") {
      Maintenance.unregisterHelper()
      return
    }
    if CommandLine.arguments.contains("--probe") {
      do {
        let snapshot = try SMC().snapshot()
        print(String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self))
      } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
      }
      return
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(CommandLine.arguments.contains("--qa-window") ? .regular : .accessory)
    withExtendedLifetime(delegate) { app.run() }
  }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem?
  private let popover = NSPopover()
  private var model: AppModel?
  private var quitApproved = false
  private var qaWindow: NSWindow?
  func applicationDidFinishLaunching(_ notification: Notification) {
    let duplicates = NSRunningApplication.runningApplications(
      withBundleIdentifier: "com.tasnimzotder.mac-fan-controller"
    ).filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    if !duplicates.isEmpty {
      quitApproved = true
      NSApp.terminate(nil)
      return
    }
    let model = AppModel()
    self.model = model
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem?.button?.target = self
    statusItem?.button?.action = #selector(toggle)
    statusItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    popover.behavior = .transient
    popover.contentSize = NSSize(width: 440, height: 610)
    popover.contentViewController = NSHostingController(
      rootView: ContentView(model: model, onQuit: { [weak self] in self?.quit() }))
    model.onUpdate = { [weak self] in self?.update() }
    update()
    if CommandLine.arguments.contains("--qa-window") {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 440, height: 610), styleMask: [.titled, .closable],
        backing: .buffered, defer: false)
      window.title = "Mac Fan Controller"
      window.contentView = NSHostingView(
        rootView: ContentView(model: model, onQuit: { [weak self] in self?.quit() }))
      window.center()
      window.makeKeyAndOrderFront(nil)
      qaWindow = window
      NSApp.activate(ignoringOtherApps: true)
    } else if CommandLine.arguments.contains("--show") || model.demo {
      DispatchQueue.main.async { [weak self] in self?.show() }
    }
  }
  private func update() {
    guard let model, let button = statusItem?.button else { return }
    button.image = NSImage(
      systemSymbolName: "fanblades", accessibilityDescription: "Mac Fan Controller")
    button.imagePosition = .imageLeading
    button.title = model.trayTitle
    button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    button.toolTip =
      "Mac Fan Controller · \(model.recoveryUnconfirmed ? "Recovery unconfirmed" : model.mode.title)"
  }
  @objc private func toggle() {
    if NSApp.currentEvent?.type == .rightMouseUp {
      let menu = NSMenu()
      menu.addItem(withTitle: "Open Mac Fan Controller", action: #selector(show), keyEquivalent: "")
        .target = self
      menu.addItem(
        withTitle: "Return to Apple automatic", action: #selector(automatic), keyEquivalent: ""
      ).target = self
      menu.addItem(.separator())
      menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
      statusItem?.menu = menu
      statusItem?.button?.performClick(nil)
      statusItem?.menu = nil
    } else {
      popover.isShown ? popover.performClose(nil) : show()
    }
  }
  @objc private func automatic() { model?.setMode(.automatic) }
  @objc private func show() {
    guard let button = statusItem?.button else { return }
    NSApp.activate(ignoringOtherApps: true)
    if !popover.isShown {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    popover.contentViewController?.view.window?.makeKey()
  }
  @objc private func quit() {
    model?.quit { [weak self] success in
      if success {
        self?.quitApproved = true
        NSApp.terminate(nil)
      } else {
        self?.show()
      }
    }
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if quitApproved { return .terminateNow }
    model?.quit { success in sender.reply(toApplicationShouldTerminate: success) }
    return .terminateLater
  }
}
