import SpriteKit

/// A SpriteKit scene that covers the whole Dock, for effects drawn over it: the veil that dims
/// the Dock while the cat is asleep. Like `MascotScene`, it pauses its view whenever nothing
/// changes.
@MainActor
final class DockCanvasScene: SKScene {
  private static let framesPerChange = 2

  private let veil = SKShapeNode()
  private var dockFrame = CGRect.zero
  private var framesToDraw = 0

  override init() {
    super.init(size: CGSize(width: 1, height: 1))
    backgroundColor = .clear
    anchorPoint = .zero
    scaleMode = .resizeFill
    veil.fillColor = .black
    veil.strokeColor = .clear
    veil.alpha = 0
    addChild(veil)
  }

  required init?(coder: NSCoder) {
    nil
  }

  /// Places the effects over the Dock, whose frame is given in this scene's coordinates.
  func layOut(dockFrame: CGRect) {
    guard dockFrame != self.dockFrame else { return }
    self.dockFrame = dockFrame
    // The Dock's background has rounded ends; this radius roughly follows them.
    let radius = min(dockFrame.width, dockFrame.height) * 0.28
    veil.path = CGPath(
      roundedRect: dockFrame,
      cornerWidth: radius,
      cornerHeight: radius,
      transform: nil
    )
    redraw()
  }

  /// Sets how dark the veil over the Dock is, from 0 to 1.
  func setVeil(opacity: Double) {
    guard veil.alpha != CGFloat(opacity) else { return }
    veil.alpha = CGFloat(opacity)
    redraw()
  }

  // The window resizes with the Dock, and a paused view would keep showing its old frame.
  override func didChangeSize(_ oldSize: CGSize) {
    super.didChangeSize(oldSize)
    redraw()
  }

  override func update(_ currentTime: TimeInterval) {
    guard framesToDraw == 0 else {
      framesToDraw -= 1
      return
    }
    view?.isPaused = true
  }

  private func redraw() {
    framesToDraw = Self.framesPerChange
    view?.isPaused = false
  }
}
