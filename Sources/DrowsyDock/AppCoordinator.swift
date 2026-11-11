import AppKit
import DockOverlayKit
import DrowsyDockCore
import Observation

@MainActor
protocol DockTracking: AnyObject {
  func accessibilityChanged(isGranted: Bool)
}

@MainActor
@Observable
final class AppCoordinator {
  private static let logger = MirroredLogger(
    subsystem: "com.drowsydock.DrowsyDock",
    category: "accessibility"
  )

  private static let dockLogger = MirroredLogger(
    subsystem: "com.drowsydock.DrowsyDock",
    category: "dock"
  )

  private static let mascotLogger = MirroredLogger(
    subsystem: "com.drowsydock.DrowsyDock",
    category: "mascot"
  )

  // macOS posts this, undocumented, whenever an app's Accessibility grant changes. It is a hint:
  // TCC may not report the new grant at once, so the grant is checked again a moment later.
  private static let accessibilityListChanged = Notification.Name("com.apple.accessibility.api")
  private static let grantRecheckDelay = Duration.seconds(1)

  let battery: BatteryMonitor
  private(set) var isAccessibilityGranted: Bool

  @ObservationIgnored let overlay: MascotOverlay
  @ObservationIgnored private var menuObserver: (any NSObjectProtocol)?
  @ObservationIgnored private var accessibilityObserver: (any NSObjectProtocol)?
  @ObservationIgnored private var grantRecheck: Task<Void, Never>?
  @ObservationIgnored private let readsAccessibilityGrant: @MainActor () -> Bool
  @ObservationIgnored private let dockTracker: any DockTracking
  @ObservationIgnored private var crowdEffect: CrowdEffectRule

  convenience init(
    arguments: [String] = CommandLine.arguments,
    qaLogFolder: URL = QALogFile.folder
  ) {
    // First, so the file gets BatteryMonitor's "Started:" and the grant line, which the live script
    // waits for.
    QALogFile.startIfRequested(by: arguments, in: qaLogFolder)
    self.init(
      battery: BatteryMonitor(),
      overlay: MascotOverlay(),
      readsAccessibilityGrant: { AccessibilityPermission.isGranted },
      makeDockTracker: { onPresentationChange in
        DockTracker(
          spriteSize: MascotOverlay.spriteSize,
          onPresentationChange: onPresentationChange
        )
      }
    )
  }

  init(
    battery: BatteryMonitor,
    overlay: MascotOverlay,
    readsAccessibilityGrant: @escaping @MainActor () -> Bool,
    makeDockTracker: (@escaping @MainActor (OverlayPresentation) -> Void) -> any DockTracking
  ) {
    self.battery = battery
    self.overlay = overlay
    self.readsAccessibilityGrant = readsAccessibilityGrant
    isAccessibilityGranted = readsAccessibilityGrant()
    crowdEffect = CrowdEffectRule(startingIn: battery.session.tracker.phase)
    dockTracker = makeDockTracker { [overlay] presentation in
      overlay.present(presentation)
    }
    overlay.show(battery.session.tracker.phase.mood)
    battery.onPhaseChange = { [weak self] phase in
      self?.batteryPhaseDidChange(phase)
    }
    Self.logger.notice("Accessibility granted: \(isAccessibilityGranted)")

    // NSMenu posts this for the MenuBarExtra's menu, too.
    menuObserver = NotificationCenter.default.addObserver(
      forName: NSMenu.didBeginTrackingNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.refreshAccessibility() }
    }
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
        Dock geometry: \(geometry) \
        hidden: \(geometry.isHidden) \
        perch: \(perch)
        """
      )
    } catch {
      Self.dockLogger.error("Dock geometry unavailable: \(error)")
    }
  }

  private func batteryPhaseDidChange(_ phase: DrowsinessTracker.Phase) {
    overlay.show(phase.mood)
    guard crowdEffect.phaseChanged(to: phase) else { return }
    if overlay.playCrowdEffect() {
      Self.mascotLogger.notice("The whole Dock nods off")
    } else {
      Self.mascotLogger.notice("The whole Dock would nod off, but the overlay isn't showing")
    }
  }

  // Any process can post this notification, so this handler must never prompt or open System
  // Settings: it only re-reads the grant, which `AccessibilityPermission.isGranted` does silently.
  private func accessibilityListDidChange() {
    refreshAccessibility()
    grantRecheck?.cancel()
    grantRecheck = Task { [weak self] in
      guard (try? await Task.sleep(for: Self.grantRecheckDelay)) != nil else { return }
      self?.refreshAccessibility()
    }
  }

  private func refreshAccessibility() {
    let isGranted = readsAccessibilityGrant()
    guard isGranted != isAccessibilityGranted else { return }
    isAccessibilityGranted = isGranted
    Self.logger.notice("Accessibility granted: \(isGranted)")
    dockTracker.accessibilityChanged(isGranted: isGranted)
  }
}
