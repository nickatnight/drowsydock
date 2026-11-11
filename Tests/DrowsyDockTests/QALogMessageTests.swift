import CoreGraphics
import DockOverlayKit
import DrowsyDockCore
import Foundation
import XCTest

@testable import DrowsyDock

// scripts/qa/live-functions.sh names every app line its scenarios wait for as a `log_…` pattern.
// These tests run the app's code with the QA log's mirror recording, and require every pattern to
// match a line the app really logs.
@MainActor
final class QALogMessageTests: XCTestCase {
  private static let liveFunctions = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "../../scripts/qa/live-functions.sh")

  private var logged: [String] = []

  private func recordTheMirror() {
    MirroredLogger.mirror = { [unowned self] _, _, message in logged.append(message) }
    addTeardownBlock { MirroredLogger.mirror = nil }
  }

  private func scriptPatterns() throws -> [String: String] {
    let script = try String(contentsOf: Self.liveFunctions, encoding: .utf8)
    var patterns: [String: String] = [:]
    for line in script.split(separator: "\n") {
      guard let match = line.wholeMatch(of: #/log_([a-z_]+)='([^']*)'/#) else { continue }
      patterns[String(match.output.1)] = String(match.output.2)
    }
    return patterns
  }

  private func coordinator(showing presentation: OverlayPresentation) -> AppCoordinator {
    let tracker = FakeDockTracker()
    let coordinator = AppCoordinator(
      battery: BatteryMonitor(
        source: FakePowerSource(BatteryReading(clampingPercentage: 46, powerState: .discharging)),
        clock: TestClock()
      ),
      overlay: MascotOverlay(catScene: MascotScene(clock: TestClock())),
      readsAccessibilityGrant: { true },
      makeDockTracker: { onPresentationChange in
        tracker.onPresentationChange = onPresentationChange
        return tracker
      }
    )
    addTeardownBlock { coordinator.overlay.show(nil) }
    KeepAlive.keep(coordinator)
    coordinator.startDockTracking()
    tracker.present(presentation)
    return coordinator
  }

  // Runs every app path that logs a line the script waits for, except the Accessibility-only
  // ones, whose messages come from the same functions their call sites use.
  private func appLines() -> [String] {
    recordTheMirror()
    let dock = DockFixture.left
    let perch = dock.perch(for: MascotOverlay.spriteSize)

    let falling = coordinator(showing: .shown(perch, on: dock))
    falling.battery.simulate(.discharging(percentage: 15))
    falling.battery.simulate(.discharging(percentage: 5))
    falling.battery.simulate(.real)
    let hidden = coordinator(showing: .hidden)
    hidden.battery.simulate(.discharging(percentage: 15))
    hidden.battery.simulate(.discharging(percentage: 5))

    let tracker = DockTracker(spriteSize: MascotOverlay.spriteSize) { _ in }
    for presentation in [OverlayPresentation.shown(perch, on: dock), .fadedOut(perch, on: dock)] {
      tracker.present(presentation)
    }
    tracker.present(.hidden)

    return logged + [
      DockTracker.observingListMessage(DockTracker.listNotifications),
      DockTracker.dockRelaunched,
      DockTracker.listDestroyed,
      AppCoordinator.dockGeometryMessage(dock),
      AppCoordinator.dockGeometryMessage(autoHiddenDock),
    ]
  }

  private var autoHiddenDock: DockGeometry {
    DockGeometry(
      listFrame: AXRect(
        CGRect(x: DockFixture.offscreenOffset + 373, y: 982, width: 766, height: 79)
      ),
      iconFrames: [],
      layout: DisplayLayout(primary: DockFixture.display)
    )
  }

  private func matches(_ pattern: String, _ message: String) throws -> Bool {
    let expression = try NSRegularExpression(pattern: pattern)
    let range = NSRange(message.startIndex..., in: message)
    return expression.firstMatch(in: message, range: range) != nil
  }

  func testEveryPatternTheScriptWaitsForMatchesALineTheAppLogs() throws {
    let patterns = try scriptPatterns()
    let lines = appLines()
    // The scenarios add these to a pattern: the overlay's state, or the side of the Dock.
    let suffixes: [String: [String]] = [
      "overlay": ["shown", "fadedOut", "hidden"],
      "dock_geometry": [".*left"],
    ]
    XCTAssertEqual(
      Set(patterns.keys),
      [
        "granted", "started_real", "changed", "changed_real", "overlay", "dock_geometry",
        "dock_hidden", "wave", "wave_without_overlay", "observing_list",
        "observing_create_and_destroy", "dock_relaunched", "list_destroyed",
      ],
      "a new log_ pattern needs the app path that logs its line in appLines()"
    )

    for (name, pattern) in patterns {
      for suffix in suffixes[name] ?? [""] {
        let matched = try lines.contains { try matches(pattern + suffix, $0) }
        XCTAssertTrue(matched, "log_\(name)='\(pattern)' + '\(suffix)' matches no line in \(lines)")
      }
    }
  }

  func testOnlyAHiddenDocksGeometryLineMatchesTheHiddenPattern() throws {
    let hiddenPattern = try XCTUnwrap(try scriptPatterns()["dock_hidden"])

    XCTAssertTrue(try matches(hiddenPattern, AppCoordinator.dockGeometryMessage(autoHiddenDock)))
    XCTAssertFalse(try matches(hiddenPattern, AppCoordinator.dockGeometryMessage(DockFixture.left)))
  }
}
