import AppKit
import ApplicationServices
import os

/// Follows the Dock. It reads the Dock's geometry whenever something may have moved it, and tells
/// the caller what the overlay should show.
///
/// Reads happen on events: Accessibility notifications from the Dock's list, display changes,
/// Dock preference changes, Space changes and a Dock relaunch. The Dock posts nothing when it
/// magnifies, so a once-a-second frame check runs, but only while the pointer is near the Dock.
/// `DockTrackerState` makes every decision; this class only feeds it events and applies them.
@MainActor
public final class DockTracker {
  private static let frameCheckInterval: TimeInterval = 1

  // The Dock may post a change before it finishes laying out, and needs a moment to shrink back
  // after the pointer leaves.
  private static let followUpReadDelay = Duration.milliseconds(500)

  // A relaunched Dock needs time to build its icon list before Accessibility can read it, and
  // how long varies. The first retry comes soon enough to re-place the overlay within 1 s of a
  // fast relaunch. Doubling gives up after 7.75 s in all; after that, the next display, Space or
  // preference change reads the Dock again.
  private static let relaunchRetryDelays: [Duration] = [0.25, 0.5, 1, 2, 4].map { .seconds($0) }

  private static let dockBundleIdentifier = "com.apple.dock"
  private static let dockPreferencesChanged = Notification.Name("com.apple.dock.prefchanged")

  private static let listNotifications = [
    kAXMovedNotification,
    kAXResizedNotification,
    kAXCreatedNotification,
    kAXUIElementDestroyedNotification,
  ]

  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "DockOverlayKit",
    category: "dock"
  )

  private let onPresentationChange: @MainActor (OverlayPresentation) -> Void
  private var state: DockTrackerState
  private var appliedPresentation = OverlayPresentation.hidden
  private var isTracking = false
  private var notificationTokens: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
  private var pointerMonitor: Any?
  private var frameCheckTimer: Timer?
  private var followUpRead: Task<Void, Never>?
  private var relaunchRetry: Task<Void, Never>?
  private var listObserver: DockListObserver?

  /// Creates a tracker that is idle until `accessibilityChanged(isGranted:)` reports a grant.
  public init(
    spriteSize: CGSize,
    onPresentationChange: @escaping @MainActor (OverlayPresentation) -> Void
  ) {
    state = DockTrackerState(spriteSize: spriteSize)
    self.onPresentationChange = onPresentationChange
  }

  /// Starts tracking when the grant is present, and stops every observer and timer when it isn't.
  public func accessibilityChanged(isGranted: Bool) {
    state.accessibilityChanged(isGranted: isGranted)
    if isGranted {
      startTracking()
      readDock()
    } else {
      stopTracking()
    }
    apply()
  }

  // MARK: - Events

  private func startTracking() {
    guard !isTracking else { return }
    isTracking = true
    observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification)
    observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification)
    observe(DistributedNotificationCenter.default(), Self.dockPreferencesChanged)
    observeDockRelaunch()
    pointerMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.mouseMoved, .leftMouseDragged]
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.pointerMoved() }
    }
  }

  private func stopTracking() {
    guard isTracking else { return }
    isTracking = false
    for (center, token) in notificationTokens {
      center.removeObserver(token)
    }
    notificationTokens = []
    if let pointerMonitor {
      NSEvent.removeMonitor(pointerMonitor)
    }
    pointerMonitor = nil
    followUpRead?.cancel()
    followUpRead = nil
    relaunchRetry?.cancel()
    relaunchRetry = nil
    listObserver = nil
  }

  private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
    let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.dockMayHaveChanged() }
    }
    notificationTokens.append((center, token))
  }

  private func observeDockRelaunch() {
    let center = NSWorkspace.shared.notificationCenter
    let token = center.addObserver(
      forName: NSWorkspace.didLaunchApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      let application =
        notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      let bundleIdentifier = application?.bundleIdentifier
      MainActor.assumeIsolated {
        guard bundleIdentifier == Self.dockBundleIdentifier else { return }
        self?.dockRelaunched()
      }
    }
    notificationTokens.append((center, token))
  }

  private func dockMayHaveChanged() {
    readDock()
    scheduleFollowUpRead(after: Self.followUpReadDelay)
    apply()
  }

  private func dockRelaunched() {
    logger.notice("The Dock relaunched")
    listObserver = nil
    relaunchRetry?.cancel()
    relaunchRetry = Task { [weak self] in
      for delay in Self.relaunchRetryDelays {
        guard (try? await Task.sleep(for: delay)) != nil else { return }
        if (try? DockReader.iconList()) != nil { break }
      }
      guard let self else { return }
      relaunchRetry = nil
      readDock()
      apply()
    }
  }

  private func pointerMoved() {
    state.pointerMoved(to: NSEvent.mouseLocation)
    apply()
  }

  private func checkFrames() {
    state.frameChecked(try? DockReader.read())
    apply()
  }

  // MARK: - Reads

  private func readDock() {
    installListObserverIfNeeded()
    do {
      state.dockRead(try DockReader.read())
    } catch {
      logger.error("Dock geometry unavailable: \(String(describing: error), privacy: .public)")
      state.dockRead(nil)
    }
  }

  private func scheduleFollowUpRead(after delay: Duration) {
    followUpRead?.cancel()
    followUpRead = Task { [weak self] in
      guard (try? await Task.sleep(for: delay)) != nil, let self else { return }
      followUpRead = nil
      readDock()
      apply()
    }
  }

  private func installListObserverIfNeeded() {
    guard listObserver == nil else { return }
    do {
      let list = try DockReader.iconList()
      listObserver = try DockListObserver(
        processIdentifier: list.processIdentifier,
        list: list.element,
        notifications: Self.listNotifications
      ) { [weak self] in
        self?.dockMayHaveChanged()
      }
      logger.notice(
        "Observing the Dock list for: \(self.listObserver?.notifications ?? [], privacy: .public)"
      )
    } catch {
      logger.error(
        "Can't observe the Dock list: \(String(describing: error), privacy: .public)"
      )
    }
  }

  // MARK: - Applying the state

  private func apply() {
    let presentation = state.presentation
    if presentation != appliedPresentation {
      appliedPresentation = presentation
      logger.notice("Overlay: \(String(describing: presentation), privacy: .public)")
      onPresentationChange(presentation)
    }
    updateFrameCheckTimer()
    if state.awaitsSettledRead, followUpRead == nil {
      scheduleFollowUpRead(after: Self.followUpReadDelay)
    }
  }

  private func updateFrameCheckTimer() {
    guard state.runsFrameChecks else {
      if frameCheckTimer != nil {
        logger.debug("Frame checks stopped")
      }
      frameCheckTimer?.invalidate()
      frameCheckTimer = nil
      return
    }
    guard frameCheckTimer == nil else { return }
    logger.debug("Frame checks started")
    let timer = Timer(timeInterval: Self.frameCheckInterval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.checkFrames() }
    }
    timer.tolerance = Self.frameCheckInterval / 10
    RunLoop.main.add(timer, forMode: .common)
    frameCheckTimer = timer
  }
}

/// Registers for Accessibility notifications on the Dock's icon list.
///
/// `DockListObserver` is not main-actor isolated, so its `deinit` may read these non-Sendable
/// handles. A main-actor class could not, because its `deinit` is nonisolated in Swift 6.0.
private final class DockListObserver {
  private final class Callback: Sendable {
    let onNotification: @MainActor @Sendable () -> Void

    init(_ onNotification: @escaping @MainActor @Sendable () -> Void) {
      self.onNotification = onNotification
    }
  }

  /// The notifications the Dock accepted. It rejects the ones it never posts.
  let notifications: [String]

  private let observer: AXObserver
  private let callbackContext: Unmanaged<Callback>

  init(
    processIdentifier: pid_t,
    list: AXUIElement,
    notifications: [String],
    onNotification: @escaping @MainActor @Sendable () -> Void
  ) throws(DockReader.Failure) {
    var created: AXObserver?
    let error = AXObserverCreate(
      processIdentifier,
      { _, _, _, context in
        guard let context else { return }
        let callback = Unmanaged<Callback>.fromOpaque(context).takeUnretainedValue()
        // The observer's source is added to the main run loop below, so callbacks arrive on the
        // main thread.
        MainActor.assumeIsolated { callback.onNotification() }
      },
      &created
    )
    guard error == .success, let created else {
      throw .accessibility(attribute: "AXObserverCreate", code: error.rawValue)
    }
    let callbackContext = Unmanaged.passRetained(Callback(onNotification))
    self.notifications = notifications.filter { notification in
      AXObserverAddNotification(created, list, notification as CFString, callbackContext.toOpaque())
        == .success
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
    observer = created
    self.callbackContext = callbackContext
  }

  deinit {
    CFRunLoopSourceInvalidate(AXObserverGetRunLoopSource(observer))
    // The observer may be running the callback on the main thread right now, so free its context
    // on the main queue, after that callback returns. This holds because `init` adds the source
    // only to the main run loop.
    let callbackContext = callbackContext
    DispatchQueue.main.async { callbackContext.release() }
  }
}
