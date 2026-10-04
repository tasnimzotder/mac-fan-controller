// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "MacFanController", platforms: [.macOS(.v13)],
  products: [
    .executable(name: "mac-fan-controller", targets: ["MacFanController"]),
    .executable(name: "mfc-helper", targets: ["FanHelper"]),
  ],
  targets: [
    .systemLibrary(name: "CSQLite"),
    .target(
      name: "CSMC", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("Security")]),
    .target(name: "FanCore", dependencies: ["CSQLite", "CSMC"]),
    .executableTarget(name: "MacFanController", dependencies: ["FanCore"]),
    .executableTarget(name: "FanHelper", dependencies: ["FanCore"]),
    .testTarget(name: "FanCoreTests", dependencies: ["FanCore"]),
  ])
