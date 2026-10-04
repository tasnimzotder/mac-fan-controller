import Foundation
import FanCore

/// Only the installed bundle may manage Service Management records. Development and
/// backup copies share its identifier and must not replace the BTM parent association.
enum InstalledApp {
  static var isCurrentBundleInstalled: Bool {
    Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
      == "/Applications/Mac Fan Controller.app"
  }

  static func requireInstalledBundle() throws {
    guard isCurrentBundleInstalled else {
      throw FanError("Use Mac Fan Controller in /Applications to manage the fan helper.")
    }
  }
}
