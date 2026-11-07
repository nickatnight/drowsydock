import AppKit
import DockOverlayKit
import DrowsyDockCore
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

  private static let mascotLogger = Logger(
    subsystem: "com.drowsydock.DrowsyDock",
    category: "mascot"
  )

  // macOS posts this, undocumented, whenever an app's Accessibility grant changes. It is a hint:
  // TCC may not report the new grant at once, so the grant is checked again a moment later.
  private static let accessibilityListChanged = Notification.Name("com.apple.accessibility.api")
  private static let grantRecheckDelay = Duration.seconds(1)

  let battery = BatteryMonitor()
  private(set) var isAccessibilityGranted: Bool

  @ObservationIgnored private var menuObserver: (any NSObjectProtocol)?
  @ObservationIgnored private var accessibilityObserver: (any NSObjectProtocol)?
  @ObservationIgnored private var grantRecheck: Task<Void, Never>?
  @ObservationIgnored private let dockTracker: DockTracker
  @ObservationIgnored private let overlay = MascotOverlay()
  @ObservationIgnored private var crowdEffect: CrowdEffectRule

  init() {
    isAccessibilityGranted = AccessibilityPermission.isGranted
    crowdEffect = CrowdEffectRule(startingIn: battery.session.tracker.phase)
    dockTracker = DockTracker(spriteSize: MascotOverlay.spriteSize) { [overlay] presentation in
      overlay.present(presentation)
    }
    overlay.show(battery.session.tracker.phase.mood)
    battery.onPhaseChange = { [weak self] phase in
      self?.batteryPhaseDidChange(phase)
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
    // Opening the menu stays the fallback in case this notification is never posted.
    accessibilityObserver = DistributedNotificationCenter.default().addObserver(
      forName: Self.accessibilityListChanged,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.accessibilityListDidChange() }
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
      let perch = geometry.perch(for: MascotOverlay.spriteSize)
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

  private func batteryPhaseDidChange(_ phase: DrowsinessTracker.Phase) {
    overlay.show(phase.mood)
    // The crowd-effect setting and quiet hours arrive in plan slices 12 and 13.
    guard crowdEffect.phaseChanged(to: phase) else { return }
    if overlay.playCrowdEffect() {
      Self.mascotLogger.notice("The whole Dock nods off")
    } else {
      Self.mascotLogger.notice("The whole Dock would nod off, but the overlay isn't showing")
    }
  }

  private func accessibilityListDidChange() {
    refreshAccessibility()
    grantRecheck?.cancel()
    grantRecheck = Task { [weak self] in
      guard (try? await Task.sleep(for: Self.grantRecheckDelay)) != nil else { return }
      self?.refreshAccessibility()
    }
  }

  private func refreshAccessibility() {
    let isGranted = AccessibilityPermission.isGranted
    guard isGranted != isAccessibilityGranted else { return }
    isAccessibilityGranted = isGranted
    Self.logger.notice("Accessibility granted: \(isGranted, privacy: .public)")
    dockTracker.accessibilityChanged(isGranted: isGranted)
  }
}
