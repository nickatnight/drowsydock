// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "DrowsyDock",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "DrowsyDock", targets: ["DrowsyDock"]),
    // The live QA helper for scripts/qa-live.sh. scripts/bundle.sh builds only DrowsyDock.
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
    .testTarget(name: "DockOverlayKitTests", dependencies: ["DockOverlayKit"]),
    .testTarget(name: "DrowsyDockCoreTests", dependencies: ["DrowsyDockCore"]),
    .testTarget(
      name: "LiveQAKitTests",
      dependencies: ["DockOverlayKit", "LiveQAKit"],
      exclude: ["Fixtures"]
    ),
    .testTarget(
      name: "DrowsyDockTests",
      dependencies: ["DockOverlayKit", "DrowsyDock", "DrowsyDockCore"],
      exclude: ["Snapshots"]
    ),
  ]
)
