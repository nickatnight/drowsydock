import DockOverlayKit
import SpriteKit

/// A SpriteKit scene that covers the whole Dock, for effects drawn over it: the veil that dims
/// the Dock while the cat is asleep, and the crowd effect.
@MainActor
final class DockCanvasScene: SKScene {
  // The Dock's background has rounded ends; this fraction of its thickness roughly follows them.
  private static let cornerRadiusRatio: CGFloat = 0.28

  weak var host: SceneHostView?

  private let veil = SKShapeNode()
  private let crowd = CrowdEffectNode()
  private var dockFrame = CGRect.zero
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

  /// Places the effects over the Dock, whose frame is given in this scene's coordinates.
  func layOut(dockFrame: CGRect) {
    guard dockFrame != self.dockFrame else { return }
    self.dockFrame = dockFrame
    let radius = min(dockFrame.width, dockFrame.height) * Self.cornerRadiusRatio
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

  // SceneHostView renders the frame in which this pauses it, so one frame shows each change.
  // An on-screen test showed the same pixels as three frames: a first pose fading in, a facing
  // change, a jump while the window was ordered out, and the veil.
  override func update(_ currentTime: TimeInterval) {
    guard !isPlayingCrowdEffect else { return }
    host?.isPaused = true
  }

  private func redraw() {
    host?.isPaused = false
  }
}
