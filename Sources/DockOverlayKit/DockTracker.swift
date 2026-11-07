import AppKit
import ApplicationServices
import os

/// Follows the Dock. It reads the Dock's geometry whenever something may have moved it, and tells
/// the caller what the overlay should show.
///
/// Reads happen on events: Accessibility notifications from the Dock's list, display changes,
/// Dock preference changes, Space changes, and the Dock reappearing in
/// `NSWorkspace.runningApplications` after a relaunch. The Dock posts nothing when it magnifies,
/// so a once-a-second frame check runs, but only while the pointer is near the Dock.
/// `DockTrackerState` makes every tracking decision; this class only feeds it events and applies
/// them.
///
/// It has no teardown on deinit, so it must live as long as the app. Calling
/// `accessibilityChanged(isGranted: false)` stops every observer, monitor and timer.
@MainActor
public final class DockTracker {
  private static let frameCheckInterval: TimeInterval = 1

  // The Dock may post a change before it finishes laying out, and needs a moment to shrink back
  // after the pointer leaves.
  private static let followUpReadDelay = Duration.milliseconds(500)

  // A relaunched Dock needs time to build a new icon list before Accessibility can read it, and
  // how long varies. The first retry comes soon enough to re-place the overlay within 1 s of a
  // fast relaunch. Doubling gives up after 7.75 s in all; after that, the next display, Space or
  // preference change reads the Dock again.
  private static let listRetryDelays: [Duration] = [0.25, 0.5, 1, 2, 4].map { .seconds($0) }

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
  private var awaitedSettledRead = false
  private var isTracking = false
  private var notificationTokens: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
  private var pointerMonitor: Any?
  private var runningApplications: NSKeyValueObservation?
  private var frameCheckTimer: Timer?
  private var followUpRead: Task<Void, Never>?
  private var listRecovery: Task<Void, Never>?
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
    let workspace = NSWorkspace.shared.notificationCenter
    for (center, name) in [
      (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
      (workspace, NSWorkspace.activeSpaceDidChangeNotification),
      (DistributedNotificationCenter.default(), Self.dockPreferencesChanged),
    ] {
      observe(center, name) { [weak self] _ in
        MainActor.assumeIsolated { self?.dockMayHaveChanged() }
      }
    }
    // NSWorkspace posts no launch notification for an LSUIElement app such as the Dock, but its
    // runningApplications property changes for every app, and only on the main run loop. Only an
    // insertion's new value holds just the launched apps; any other kind could hold the whole
    // list, which always includes the running Dock.
    runningApplications = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) {
      [weak self] _, change in
      guard change.kind == .insertion else { return }
      let dockLaunched = change.newValue?.contains { DockReader.isDock($0) } ?? false
      guard dockLaunched else { return }
      MainActor.assumeIsolated { self?.recoverDockList(because: "The Dock relaunched") }
    }
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
    runningApplications?.invalidate()
    runningApplications = nil
    if let pointerMonitor {
      NSEvent.removeMonitor(pointerMonitor)
    }
    pointerMonitor = nil
    followUpRead?.cancel()
    followUpRead = nil
    listRecovery?.cancel()
    listRecovery = nil
    frameCheckTimer?.invalidate()
    frameCheckTimer = nil
    listObserver = nil
  }

  private func observe(
    _ center: NotificationCenter,
    _ name: Notification.Name,
    handler: @escaping @Sendable (Notification) -> Void
  ) {
    let token = center.addObserver(forName: name, object: nil, queue: .main, using: handler)
    notificationTokens.append((center, token))
  }

  private func dockMayHaveChanged() {
    if state.readsAtOnceOnDockChange {
      readDock()
    }
    scheduleFollowUpRead(after: Self.followUpReadDelay)
    apply()
  }

  // The Dock's list element is gone, so the observer on it is dead. Drop it and retry until the
  // Dock has a new list.
  private func recoverDockList(because reason: String) {
    logger.notice("\(reason, privacy: .public)")
    listObserver = nil
    listRecovery?.cancel()
    listRecovery = Task { [weak self] in
      for delay in Self.listRetryDelays {
        guard (try? await Task.sleep(for: delay)) != nil else { return }
        if (try? DockReader.iconList()) != nil { break }
      }
      guard let self else { return }
      listRecovery = nil
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

  // One icon-list fetch serves both the observer check and the read, so a frozen Dock stalls the
  // main thread for one Accessibility timeout, not two.
  private func readDock() {
    do throws(DockReader.Failure) {
      let list = try DockReader.iconList()
      installListObserverIfNeeded(on: list)
      state.dockRead(try DockReader.read(list: list.element))
    } catch {
      logger.error("Dock geometry unavailable: \(String(describing: error), privacy: .public)")
      state.dockRead(nil)
    }
    // The pointer may already be on the Dock, for example at launch or after a Space change.
    state.pointerMoved(to: NSEvent.mouseLocation)
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

  // Re-installs the observer when the Dock's pid or its list element changed, in case a relaunch
  // or a rebuilt list went unnoticed.
  private func installListObserverIfNeeded(
    on list: (processIdentifier: pid_t, element: AXUIElement)
  ) {
    if let listObserver, listObserver.observes(list.element, of: list.processIdentifier) {
      return
    }
    do {
      listObserver = try DockListObserver(
        processIdentifier: list.processIdentifier,
        list: list.element,
        notifications: Self.listNotifications
      ) { [weak self] isListDestroyed in
        if isListDestroyed {
          self?.recoverDockList(because: "The Dock list was destroyed")
        } else {
          self?.dockMayHaveChanged()
        }
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
      logger.debug("Overlay: \(String(describing: presentation), privacy: .public)")
      onPresentationChange(presentation)
    }
    updateFrameCheckTimer()
    // Timed from the moment the pointer left, even if an earlier follow-up read is pending, so the
    // read doesn't catch the Dock still shrinking back.
    if state.awaitsSettledRead, !awaitedSettledRead {
      scheduleFollowUpRead(after: Self.followUpReadDelay)
    }
    awaitedSettledRead = state.awaitsSettledRead
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
  // Never mutated, and its AX references are used only on the main thread: by the callback, by
  // DockListObserver.observes and DockListObserver.deinit, which run synchronously on the main
  // thread because the main-actor DockTracker is the only owner, and by the deferred release in
  // that deinit, which runs on the main queue.
  private final class Callback: @unchecked Sendable {
    let observer: AXObserver
    let list: AXUIElement
    let onNotification: @MainActor @Sendable (_ isListDestroyed: Bool) -> Void

    init(
      observer: AXObserver,
      list: AXUIElement,
      onNotification: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
      self.observer = observer
      self.list = list
      self.onNotification = onNotification
    }
  }

  /// The notifications the Dock accepted. It rejects the ones it never posts.
  let notifications: [String]

  /// The Dock process this observer listens to.
  let processIdentifier: pid_t

  private let callbackContext: Unmanaged<Callback>

  /// Whether this observer is registered on `list` in the Dock process `processIdentifier`.
  func observes(_ list: AXUIElement, of processIdentifier: pid_t) -> Bool {
    processIdentifier == self.processIdentifier
      && CFEqual(list, callbackContext.takeUnretainedValue().list)
  }

  init(
    processIdentifier: pid_t,
    list: AXUIElement,
    notifications: [String],
    onNotification: @escaping @MainActor @Sendable (_ isListDestroyed: Bool) -> Void
  ) throws(DockReader.Failure) {
    var created: AXObserver?
    let error = AXObserverCreate(
      processIdentifier,
      { _, element, notification, context in
        guard let context else { return }
        let callback = Unmanaged<Callback>.fromOpaque(context).takeUnretainedValue()
        // The registration on the list may also report its items being destroyed, such as the
        // icon of an app that quit. Only the list's own destruction kills the observer.
        let isListDestroyed =
          notification as String == kAXUIElementDestroyedNotification
          && CFEqual(element, callback.list)
        // The observer's source is added to the main run loop below, so callbacks arrive on the
        // main thread.
        MainActor.assumeIsolated { callback.onNotification(isListDestroyed) }
      },
      &created
    )
    guard error == .success, let created else {
      throw .accessibility(attribute: "AXObserverCreate", code: error.rawValue)
    }
    let callbackContext = Unmanaged.passRetained(
      Callback(observer: created, list: list, onNotification: onNotification)
    )
    self.notifications = notifications.filter { notification in
      AXObserverAddNotification(created, list, notification as CFString, callbackContext.toOpaque())
        == .success
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
    self.processIdentifier = processIdentifier
    self.callbackContext = callbackContext
  }

  deinit {
    let callback = callbackContext.takeUnretainedValue()
    for notification in notifications {
      AXObserverRemoveNotification(callback.observer, callback.list, notification as CFString)
    }
    CFRunLoopSourceInvalidate(AXObserverGetRunLoopSource(callback.observer))
    // The observer may be running the callback on the main thread right now, for example when the
    // callback itself dropped this object. The context owns the observer, so releasing the
    // context on the main queue frees both after that callback returns. This holds because `init`
    // adds the source only to the main run loop.
    let callbackContext = callbackContext
    DispatchQueue.main.async { callbackContext.release() }
  }
}
