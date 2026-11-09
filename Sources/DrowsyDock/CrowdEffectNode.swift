import DockOverlayKit
import DrowsyDockCore
import SpriteKit

/// Draws "the whole Dock nods off": a wave along the Dock in which each icon dims briefly and
/// puffs a "z", timed by `CrowdWave`.
@MainActor
final class CrowdEffectNode {
  private static let dimOpacity: CGFloat = 0.35
  private static let zSize: CGFloat = 9

  private static let artworkCornerRadius: CGFloat = 0.22

  private static let dimPhases = (fadeIn: 0.3, hold: 0.3, fadeOut: 0.4)

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
    node.run(.completion(after: wave.totalDuration.inSeconds, completion))
  }

  func stop() {
    node.removeAllActions()
    node.removeAllChildren()
  }

  private func dim(_ icon: CGRect, after delay: TimeInterval) {
    let artwork = DockGeometry.artworkFrame(ofItem: icon)
    let radius = artwork.width * Self.artworkCornerRadius
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
        .fadeAlpha(to: Self.dimOpacity, duration: dim * Self.dimPhases.fadeIn),
        .wait(forDuration: dim * Self.dimPhases.hold),
        .fadeOut(withDuration: dim * Self.dimPhases.fadeOut),
        .removeFromParent(),
      ])
    )
  }

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
