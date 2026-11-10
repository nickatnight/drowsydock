import AppKit

@testable import DockOverlayKit

// Records each fade an overlay window starts and ends it at once, so a test sees the alpha and the
// length of every fade without waiting for AppKit, which animates only while a display is awake.
@MainActor
final class FadeRecorder {
  private(set) var fades: [(alpha: CGFloat, duration: TimeInterval)] = []

  init(_ window: OverlayWindow) {
    window.fader = { [weak self] nsWindow, alpha, duration, completion in
      self?.fades.append((alpha, duration))
      nsWindow.alphaValue = alpha
      completion()
    }
  }

  var lastFade: (alpha: CGFloat, duration: TimeInterval)? { fades.last }
}
