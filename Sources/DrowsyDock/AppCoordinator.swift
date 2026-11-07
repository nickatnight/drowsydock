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

  let battery = BatteryMonitor()
  private(set) var isAccessibilityGranted: Bool

  @ObservationIgnored private var menuObserver: (any NSObjectProtocol)?

  init() {
    isAccessibilityGranted = AccessibilityPermission.isGranted
    Self.logger.notice("Accessibility granted: \(self.isAccessibilityGranted, privacy: .public)")

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

  private func refreshAccessibility() {
    let isGranted = AccessibilityPermission.isGranted
    guard isGranted != isAccessibilityGranted else { return }
    isAccessibilityGranted = isGranted
    Self.logger.notice("Accessibility granted: \(isGranted, privacy: .public)")
  }
}
