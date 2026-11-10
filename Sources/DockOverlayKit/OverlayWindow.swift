import AppKit
import os

/// A transparent window just above the Dock. It shows on every Space, including beside
/// full-screen apps, and lets every click through to whatever is below it.
@MainActor
public final class OverlayWindow {
  let window: NSWindow

  /// Creates the window, hidden, with the view it draws.
  public init(contentView: NSView) {
    window = NSWindow(
      contentRect: .zero,
      styleMask: .borderless,
      backing: .buffered,
      defer: true
    )
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.ignoresMouseEvents = true
    // "Hide Others" in another app would otherwise hide the overlay too.
    window.canHide = false
    window.isReleasedWhenClosed = false
    window.animationBehavior = .none
    window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
    window.collectionBehavior = [
      .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary,
    ]
    window.contentView = contentView
  }

  private static let fadeDuration: TimeInterval = 0.2

  /// What the window shows once a fade it is running ends.
  public enum Visibility: Sendable {
    /// Off screen.
    case hidden
    /// On screen but fully transparent, at its frame.
    case fadedOut
    /// On screen and opaque, at its frame.
    case shown
  }

  /// The window's frame in AppKit global coordinates.
  public var frame: CGRect { window.frame }

  /// What the window shows once a fade it is running ends.
  public private(set) var visibility = Visibility.hidden

  private(set) var hasReportedUnusableFrame = false

  // Runs a fade of `window` to `alpha` over `duration` seconds, then `completion`. Internal so the
  // kit's and the app's tests can record each fade and end it at once: AppKit runs window
  // animations only while a display is awake.
  var fader: @MainActor (NSWindow, CGFloat, TimeInterval, @escaping @MainActor () -> Void) -> Void =
    OverlayWindow.animatedFade

  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "DockOverlayKit",
    category: "overlay"
  )

  /// Shows the window at `frame`, in AppKit global coordinates, fading it in if it was hidden or
  /// faded out. A frame that isn't `isUsableWindowFrame` hides the window instead.
  ///
  /// - Returns: Whether the window took the frame.
  @discardableResult
  public func show(at frame: CGRect) -> Bool {
    guard accepts(frame) else { return false }
    place(at: frame)
    fade(to: 1)
    visibility = .shown
    return true
  }

  /// Keeps the window at `frame` but fades it out. A frame that isn't `isUsableWindowFrame` hides
  /// the window instead.
  ///
  /// - Returns: Whether the window took the frame.
  @discardableResult
  public func fadeOut(at frame: CGRect) -> Bool {
    guard accepts(frame) else { return false }
    place(at: frame)
    fade(to: 0)
    visibility = .fadedOut
    return true
  }

  /// Takes the window off screen, at once or after fading it out.
  public func hide(fading: Bool = false) {
    visibility = .hidden
    guard fading, window.isVisible, window.alphaValue > 0 else {
      window.orderOut(nil)
      return
    }
    fader(window, 0, Self.fadeDuration) { [weak self] in
      guard let self, self.visibility != .shown else { return }
      self.window.orderOut(nil)
    }
  }

  // AppKit aborts the app when given a null or non-finite frame, so such a frame means there is
  // nothing to show.
  private func accepts(_ frame: CGRect) -> Bool {
    guard !frame.isUsableWindowFrame else {
      hasReportedUnusableFrame = false
      return true
    }
    if !hasReportedUnusableFrame {
      hasReportedUnusableFrame = true
      logger.error("Overlay hidden: unusable frame \(String(describing: frame), privacy: .public)")
    }
    hide()
    return false
  }

  private func place(at frame: CGRect) {
    if window.frame != frame {
      window.setFrame(frame, display: true)
    }
    if !window.isVisible {
      window.alphaValue = 0
      window.orderFrontRegardless()
    }
  }

  private func fade(to alpha: CGFloat) {
    guard window.alphaValue != alpha else { return }
    fader(window, alpha, Self.fadeDuration) {}
  }

  static func animatedFade(
    _ window: NSWindow,
    to alpha: CGFloat,
    over duration: TimeInterval,
    then completion: @escaping @MainActor () -> Void
  ) {
    NSAnimationContext.runAnimationGroup { context in
      context.duration = duration
      window.animator().alphaValue = alpha
    } completionHandler: {
      // AppKit calls this on the main thread.
      MainActor.assumeIsolated(completion)
    }
  }
}
