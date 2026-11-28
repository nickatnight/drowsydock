import AppKit
import DockOverlayKit

/// Records an overlay window's fades and sets the window's alpha at once, so tests run without
/// AppKit's animations, which run only while a display is awake. A test can also hold the
/// completions and run them later.
@MainActor
package final class FadeRecorder: OverlayWindow.Fader {
  package private(set) var fades: [(alpha: CGFloat, duration: TimeInterval)] = []
  package var completesAtOnce = true
  package private(set) var pending: [@MainActor () -> Void] = []

  /// Makes `window` fade through this recorder.
  package init(_ window: OverlayWindow) {
    window.fader = self
  }

  package var lastFade: (alpha: CGFloat, duration: TimeInterval)? { fades.last }

  package func fade(
    _ window: NSWindow,
    to alpha: CGFloat,
    over duration: TimeInterval,
    then completion: @escaping @MainActor () -> Void
  ) {
    fades.append((alpha, duration))
    window.alphaValue = alpha
    if completesAtOnce {
      completion()
    } else {
      pending.append(completion)
    }
  }
}
