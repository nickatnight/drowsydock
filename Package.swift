// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "SleepyBattery",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "SleepyBattery", targets: ["SleepyBattery"])
  ],
  dependencies: [],
  targets: [
    .target(name: "DockOverlayKit"),
    .target(name: "DrowsyDockCore"),
    .executableTarget(
      name: "SleepyBattery",
      dependencies: ["DockOverlayKit", "DrowsyDockCore"]
    ),
    .testTarget(name: "DockOverlayKitTests", dependencies: ["DockOverlayKit"]),
    .testTarget(name: "DrowsyDockCoreTests", dependencies: ["DrowsyDockCore"]),
  ]
)
