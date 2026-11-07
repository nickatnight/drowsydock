// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "DrowsyDock",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "DrowsyDock", targets: ["DrowsyDock"])
  ],
  dependencies: [],
  targets: [
    .target(name: "DockOverlayKit"),
    .target(name: "DrowsyDockCore"),
    .executableTarget(
      name: "DrowsyDock",
      dependencies: ["DockOverlayKit", "DrowsyDockCore"]
    ),
    .testTarget(name: "DockOverlayKitTests", dependencies: ["DockOverlayKit"]),
    .testTarget(name: "DrowsyDockCoreTests", dependencies: ["DrowsyDockCore"]),
  ]
)
