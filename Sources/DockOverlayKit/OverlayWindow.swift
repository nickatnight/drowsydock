import AppKit
import os

/// A transparent window just above the Dock. It shows on every Space, including beside
/// full-screen apps, and lets every click through to whatever is below it.
@MainActor
public final class OverlayWindow {
  private let window: NSWindow

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

  private var hasReportedUnusableFrame = false

  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "DockOverlayKit",
    category: "overlay"
  )

  /// Shows the window at `frame`, in AppKit global coordinates, fading it in if it was hidden or
  /// faded out. A frame that isn't `isUsableWindowFrame` hides the window instead.
  public func show(at frame: CGRect) {
    guard accepts(frame) else { return }
    place(at: frame)
    fade(to: 1)
    visibility = .shown
  }

  /// Keeps the window at `frame` but fades it out. A frame that isn't `isUsableWindowFrame` hides
  /// the window instead.
  public func fadeOut(at frame: CGRect) {
    guard accepts(frame) else { return }
    place(at: frame)
    fade(to: 0)
    visibility = .fadedOut
  }

  /// Takes the window off screen, at once or after fading it out.
  public func hide(fading: Bool = false) {
    visibility = .hidden
    guard fading, window.isVisible, window.alphaValue > 0 else {
      window.orderOut(nil)
      return
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Self.fadeDuration
      window.animator().alphaValue = 0
    } completionHandler: { [weak self] in
      // AppKit calls this on the main thread.
      MainActor.assumeIsolated {
        guard let self, self.visibility != .shown else { return }
        self.window.orderOut(nil)
      }
    }
  }

  // AppKit aborts the app when given a null or non-finite frame, so such a frame means there is
  // nothing to show. Logged once per run of unusable frames: a usable frame re-arms the log.
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
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Self.fadeDuration
      window.animator().alphaValue = alpha
    }
  }
}
