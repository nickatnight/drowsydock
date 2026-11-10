import AppKit

@testable import DockOverlayKit

// Records each fade an overlay window starts. By default it ends the fade at once, so a test sees
// the alpha and the length of every fade without waiting for AppKit, which animates only while a
// display is awake. With `completesAtOnce` false it sets the alpha but holds the completion.
// Tests/DockOverlayKitTests/OverlayWindowTests.swift has the kit tests' copy; change both together.
@MainActor
final class FadeRecorder {
  private(set) var fades: [(alpha: CGFloat, duration: TimeInterval)] = []
  var completesAtOnce = true
  private(set) var pending: [@MainActor () -> Void] = []

  init(_ window: OverlayWindow) {
    window.fader = { [weak self] nsWindow, alpha, duration, completion in
      guard let self else { return }
      fades.append((alpha, duration))
      nsWindow.alphaValue = alpha
      if completesAtOnce {
        completion()
      } else {
        pending.append(completion)
      }
    }
  }

  var lastFade: (alpha: CGFloat, duration: TimeInterval)? { fades.last }
}
