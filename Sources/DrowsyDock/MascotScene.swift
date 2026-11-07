import DockOverlayKit
import DrowsyDockCore
import SpriteKit

/// The SpriteKit scene that holds the cat. It draws only while something changes: after a change
/// it renders a couple of frames and pauses its view, so a still cat costs no CPU.
@MainActor
final class MascotScene: SKScene {
  // One frame to apply the change, one more in case the first lands before the window is ready.
  private static let framesPerChange = 2

  private let cat = CatRenderer()
  private var framesToDraw = 0

  override init() {
    super.init(size: CatRenderer.canvasSize)
    backgroundColor = .clear
    anchorPoint = .zero
    scaleMode = .fill
    cat.face(.left)
    addChild(cat.node)
  }

  required init?(coder: NSCoder) {
    nil
  }

  /// Puts the cat into `pose`, facing `facing`.
  func show(_ pose: MascotPose, facing: DockPerch.Facing) {
    cat.face(facing)
    cat.apply(pose)
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
