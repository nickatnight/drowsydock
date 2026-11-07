import AppKit
import DockOverlayKit
import Observation
import os

@MainActor
@Observable
final class AppCoordinator {
  private static let logger = Logger(
    subsystem: "com.drowsydock.DrowsyDock",
    category: "accessibility"
  )

  private static let dockLogger = Logger(subsystem: "com.drowsydock.DrowsyDock", category: "dock")

  // Until the mascot exists (plan slice 8), the overlay is a square of this size.
  static let mascotSize = CGSize(width: 64, height: 64)

  let battery = BatteryMonitor()
  private(set) var isAccessibilityGranted: Bool

  @ObservationIgnored private var menuObserver: (any NSObjectProtocol)?
  @ObservationIgnored private var dockTracker = DockTrackerState(spriteSize: mascotSize)
  @ObservationIgnored private let overlay = OverlayWindow(contentView: debugOutline())

  init() {
    isAccessibilityGranted = AccessibilityPermission.isGranted
    Self.logger.notice("Accessibility granted: \(self.isAccessibilityGranted, privacy: .public)")
    dockTracker.accessibilityChanged(isGranted: isAccessibilityGranted)
    // Runs once the app's run loop is going, so the window is ordered front after launch.
    Task { [weak self] in self?.placeOverlay() }

    // The spec re-checks the grant each time the menu opens. NSMenu posts this for the
    // MenuBarExtra's menu, too.
    menuObserver = NotificationCenter.default.addObserver(
      forName: NSMenu.didBeginTrackingNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.refreshAccessibility() }
    }
  }

  func grantAccessibility() {
    AccessibilityPermission.requestAndOpenSettings()
  }

  func logDockGeometry() {
    do {
      let geometry = try DockReader.read()
      let perch = geometry.perch(for: Self.mascotSize)
      Self.dockLogger.notice(
        """
        Dock geometry: \(String(describing: geometry), privacy: .public) \
        hidden: \(geometry.isHidden, privacy: .public) \
        perch: \(String(describing: perch), privacy: .public)
        """
      )
    } catch {
      Self.dockLogger.error(
        "Dock geometry unavailable: \(String(describing: error), privacy: .public)"
      )
    }
  }

  private func refreshAccessibility() {
    let isGranted = AccessibilityPermission.isGranted
    guard isGranted != isAccessibilityGranted else { return }
    isAccessibilityGranted = isGranted
    Self.logger.notice("Accessibility granted: \(isGranted, privacy: .public)")
    dockTracker.accessibilityChanged(isGranted: isGranted)
    placeOverlay()
  }

  private func placeOverlay() {
    if isAccessibilityGranted {
      do {
        dockTracker.dockRead(try DockReader.read())
      } catch {
        Self.dockLogger.error(
          "Dock geometry unavailable: \(String(describing: error), privacy: .public)"
        )
        dockTracker.dockRead(nil)
      }
    }
    overlay.present(dockTracker.presentation)
    Self.dockLogger.notice(
      "Overlay: \(String(describing: self.dockTracker.presentation), privacy: .public)"
    )
  }

  // Marks the perch until the mascot replaces it (plan slice 8).
  private static func debugOutline() -> NSView {
    let view = NSView()
    view.wantsLayer = true
    view.layer?.borderColor = NSColor.systemPink.cgColor
    view.layer?.borderWidth = 2
    return view
  }
}
