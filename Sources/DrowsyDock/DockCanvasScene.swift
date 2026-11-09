import DockOverlayKit
import SpriteKit

/// A SpriteKit scene that covers the whole Dock, for effects drawn over it: the veil that dims
/// the Dock while the cat is asleep, and the crowd effect.
@MainActor
final class DockCanvasScene: SKScene {
  weak var host: SceneHostView?

  private let veil = SKShapeNode()
  private let crowd = CrowdEffectNode()
  private var background = CGRect.zero
  private var isPlayingCrowdEffect = false

  override init() {
    super.init(size: CGSize(width: 1, height: 1))
    backgroundColor = .clear
    anchorPoint = .zero
    scaleMode = .fill
    veil.fillColor = .black
    veil.strokeColor = .clear
    veil.alpha = 0
    addChild(veil)
    addChild(crowd.node)
  }

  required init?(coder: NSCoder) {
    nil
  }

  /// Fits the veil to the Dock's drawn background, whose frame is given in this scene's
  /// coordinates.
  func layOut(background: CGRect, cornerRadius: CGFloat) {
    guard background != self.background else { return }
    self.background = background
    veil.path = CGPath(
      roundedRect: background,
      cornerWidth: cornerRadius,
      cornerHeight: cornerRadius,
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

  /// Plays the crowd effect over `iconFrames`, given in this scene's coordinates and in wave
  /// order, then calls `completion`.
  func playCrowdEffect(
    over iconFrames: [CGRect],
    orientation: DockOrientation,
    completion: @escaping @MainActor () -> Void
  ) {
    isPlayingCrowdEffect = true
    host?.isPaused = false
    crowd.play(over: iconFrames, orientation: orientation) { [weak self] in
      self?.isPlayingCrowdEffect = false
      self?.redraw()
      completion()
    }
  }

  func stopCrowdEffect() {
    guard isPlayingCrowdEffect else { return }
    isPlayingCrowdEffect = false
    crowd.stop()
    redraw()
  }

  override func didChangeSize(_ oldSize: CGSize) {
    super.didChangeSize(oldSize)
    redraw()
  }

  override func update(_ currentTime: TimeInterval) {
    guard !isPlayingCrowdEffect else { return }
    host?.isPaused = true
  }

  private func redraw() {
    host?.isPaused = false
  }
}
