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

  static let mascotSize = CGSize(width: 64, height: 64)

  let battery = BatteryMonitor()
  private(set) var isAccessibilityGranted: Bool

  @ObservationIgnored private var menuObserver: (any NSObjectProtocol)?
  @ObservationIgnored private let dockTracker: DockTracker

  init() {
    isAccessibilityGranted = AccessibilityPermission.isGranted
    let overlay = OverlayWindow(contentView: Self.debugOutline())
    dockTracker = DockTracker(spriteSize: Self.mascotSize) { presentation in
      overlay.present(presentation)
    }
    Self.logger.notice("Accessibility granted: \(self.isAccessibilityGranted, privacy: .public)")

    // NSMenu posts this for the MenuBarExtra's menu, too.
    menuObserver = NotificationCenter.default.addObserver(
      forName: NSMenu.didBeginTrackingNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.refreshAccessibility() }
    }
  }

  func startDockTracking() {
    dockTracker.accessibilityChanged(isGranted: isAccessibilityGranted)
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
  }

  private static func debugOutline() -> NSView {
    let view = NSView()
    view.wantsLayer = true
    view.layer?.borderColor = NSColor.systemPink.cgColor
    view.layer?.borderWidth = 2
    return view
  }
}
