import AppKit

@testable import DockOverlayKit

@MainActor
final class FadeRecorder: OverlayWindow.Fader {
  private(set) var fades: [(alpha: CGFloat, duration: TimeInterval)] = []
  var completesAtOnce = true
  private(set) var pending: [@MainActor () -> Void] = []

  init(_ window: OverlayWindow) {
    window.fader = self
  }

  func fade(
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

  var lastFade: (alpha: CGFloat, duration: TimeInterval)? { fades.last }
}
