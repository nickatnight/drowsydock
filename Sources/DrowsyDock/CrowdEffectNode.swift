import DockOverlayKit
import DrowsyDockCore
import SpriteKit

/// Draws "the whole Dock nods off": a wave along the Dock in which each icon dims briefly and
/// puffs a "z", timed by `CrowdWave`.
@MainActor
final class CrowdEffectNode {
  private static let dimOpacity: CGFloat = 0.35
  private static let zSize: CGFloat = 9

  /// The node to add to the Dock canvas.
  let node = SKNode()

  /// Plays the wave over `iconFrames`, given in the canvas's coordinates and in wave order, then
  /// calls `completion` on the main actor.
  func play(
    over iconFrames: [CGRect],
    orientation: DockOrientation,
    completion: @escaping @MainActor () -> Void
  ) {
    stop()
    let wave = CrowdWave(iconCount: iconFrames.count)
    for (index, icon) in iconFrames.enumerated() {
      let start = wave.startTime(ofIconAt: index).inSeconds
      dim(icon, after: start)
      puff(from: icon, orientation: orientation, after: start)
    }
    node.run(
      .sequence([
        .wait(forDuration: wave.totalDuration.inSeconds),
        .run({ MainActor.assumeIsolated(completion) }, queue: .main),
      ])
    )
  }

  /// Stops the wave at once and clears it.
  func stop() {
    node.removeAllActions()
    node.removeAllChildren()
  }

  // A dark rounded square over the icon's artwork, in and out within the dim duration.
  private func dim(_ icon: CGRect, after delay: TimeInterval) {
    let artwork = icon.insetBy(dx: icon.width * 0.12, dy: icon.height * 0.12)
    let radius = artwork.width * 0.22
    let shade = SKShapeNode(
      path: CGPath(roundedRect: artwork, cornerWidth: radius, cornerHeight: radius, transform: nil)
    )
    shade.fillColor = .black
    shade.strokeColor = .clear
    shade.lineWidth = 0
    shade.alpha = 0
    node.addChild(shade)
    let dim = CrowdWave.dimDuration.inSeconds
    shade.run(
      .sequence([
        .wait(forDuration: delay),
        .fadeAlpha(to: Self.dimOpacity, duration: dim * 0.3),
        .wait(forDuration: dim * 0.3),
        .fadeOut(withDuration: dim * 0.4),
        .removeFromParent(),
      ])
    )
  }

  // A "z" that rises from the icon into the screen and fades.
  private func puff(from icon: CGRect, orientation: DockOrientation, after delay: TimeInterval) {
    let z = CatRenderer.z(size: Self.zSize)
    let drift: CGVector
    switch orientation {
    case .bottom:
      z.position = CGPoint(x: icon.midX, y: icon.maxY - Self.zSize)
      drift = CGVector(dx: 4, dy: 24)
    case .left:
      z.position = CGPoint(x: icon.maxX - Self.zSize, y: icon.midY)
      drift = CGVector(dx: 24, dy: 6)
    case .right:
      z.position = CGPoint(x: icon.minX + Self.zSize, y: icon.midY)
      drift = CGVector(dx: -24, dy: 6)
    }
    z.alpha = 0
    z.setScale(0.5)
    node.addChild(z)
    let life = CrowdWave.iconEffectDuration.inSeconds
    z.run(
      .sequence([
        .wait(forDuration: delay),
        .group([
          .move(by: drift, duration: life),
          .scale(to: 1.1, duration: life),
          .sequence([
            .fadeIn(withDuration: life * 0.15),
            .wait(forDuration: life * 0.45),
            .fadeOut(withDuration: life * 0.4),
          ]),
        ]),
        .removeFromParent(),
      ])
    )
  }
}
