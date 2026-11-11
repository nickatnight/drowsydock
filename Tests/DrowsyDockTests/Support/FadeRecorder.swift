import AppKit

@testable import DockOverlayKit

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
