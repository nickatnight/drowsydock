import AppKit

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
    window.isReleasedWhenClosed = false
    window.animationBehavior = .none
    // One level above the Dock, so the sprite draws over the Dock's top edge.
    window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
    window.collectionBehavior = [
      .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary,
    ]
    window.contentView = contentView
  }

  /// Shows the window at the perch, or hides it.
  public func present(_ presentation: OverlayPresentation) {
    switch presentation {
    case .hidden:
      window.orderOut(nil)
    case .shown(let perch):
      window.setFrame(perch.frame, display: true)
      window.orderFrontRegardless()
    }
  }
}
