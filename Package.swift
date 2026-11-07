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
    .target(name: "SleepyBatteryCore"),
    .executableTarget(
      name: "SleepyBattery",
      dependencies: ["DockOverlayKit", "SleepyBatteryCore"]
    ),
    .testTarget(name: "DockOverlayKitTests", dependencies: ["DockOverlayKit"]),
    .testTarget(name: "SleepyBatteryCoreTests", dependencies: ["SleepyBatteryCore"]),
  ]
)
