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
    .target(name: "LiveQAKit", path: "scripts/qa/Sources/LiveQAKit"),
    .executableTarget(
      name: "qa-helper",
      dependencies: ["DockOverlayKit", "LiveQAKit"],
      path: "scripts/qa/Sources/qa-helper"
    ),
    .target(
      name: "DockOverlayKitTestSupport",
      dependencies: ["DockOverlayKit"],
      path: "Tests/DockOverlayKitTestSupport"
    ),
    .testTarget(
      name: "DockOverlayKitTests",
      dependencies: ["DockOverlayKit", "DockOverlayKitTestSupport"]
    ),
    .testTarget(name: "DrowsyDockCoreTests", dependencies: ["DrowsyDockCore"]),
    .testTarget(
      name: "LiveQAKitTests",
      dependencies: ["DockOverlayKit", "LiveQAKit"],
      exclude: ["Fixtures"]
    ),
    .testTarget(
      name: "DrowsyDockTests",
      dependencies: [
        "DockOverlayKit", "DockOverlayKitTestSupport", "DrowsyDock", "DrowsyDockCore",
      ],
      exclude: ["Snapshots"]
    ),
  ]
)
