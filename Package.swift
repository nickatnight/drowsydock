// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "DrowsyDock",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "DrowsyDock", targets: ["DrowsyDock"]),
    .executable(name: "qa-helper", targets: ["qa-helper"]),
  ],
  dependencies: [],
  targets: [
    .target(name: "DockOverlayKit"),
    .target(name: "DrowsyDockCore"),
    .executableTarget(
      name: "DrowsyDock",
      dependencies: ["DockOverlayKit", "DrowsyDockCore"]
    ),
    .target(name: "LiveQAKit"),
    .executableTarget(name: "qa-helper", dependencies: ["DockOverlayKit", "LiveQAKit"]),
    .target(name: "DockOverlayKitTestSupport", dependencies: ["DockOverlayKit"]),
    .testTarget(
      name: "DockOverlayKitTests",
      dependencies: ["DockOverlayKit", "DockOverlayKitTestSupport"]
    ),
    .testTarget(name: "DrowsyDockCoreTests", dependencies: ["DrowsyDockCore"]),
    .testTarget(
      name: "LiveQAKitTests",
      dependencies: ["DockOverlayKit", "DrowsyDockCore", "LiveQAKit"],
      exclude: ["Fixtures"]
    ),
    .testTarget(
      name: "DrowsyDockTests",
      dependencies: [
        "DockOverlayKit", "DockOverlayKitTestSupport", "DrowsyDock", "DrowsyDockCore", "LiveQAKit",
      ],
      exclude: ["Snapshots"]
    ),
  ]
)
