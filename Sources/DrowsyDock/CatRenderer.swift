import DockOverlayKit
import DrowsyDockCore
import SpriteKit

/// Draws the cat in code, as SpriteKit shapes, and puts it into a `MascotPose`.
///
/// The cat is an original design: an apricot cat with a cream muzzle and paws, a darker ginger
/// patch on its forehead, rosy cheeks and a curled tail. It sits facing left. `node` is the root;
/// its origin is the point between the cat's front paws, on the surface it sits on.
@MainActor
final class CatRenderer {
  /// The canvas the cat and its "z"s fit in, in points.
  static let canvasSize = CGSize(width: 64, height: 80)

  /// Where `node` sits on the canvas when the cat faces left. Off-centre, so the "z"s have room
  /// behind the head.
  static let anchorFacingLeft = CGPoint(x: 29, y: 1)

  private enum Palette {
    static let fur = SKColor(srgbRed: 0.96, green: 0.73, blue: 0.48, alpha: 1)
    static let patch = SKColor(srgbRed: 0.87, green: 0.53, blue: 0.29, alpha: 1)
    static let cream = SKColor(srgbRed: 1.00, green: 0.95, blue: 0.87, alpha: 1)
    static let outline = SKColor(srgbRed: 0.29, green: 0.20, blue: 0.16, alpha: 1)
    static let pink = SKColor(srgbRed: 0.95, green: 0.58, blue: 0.62, alpha: 1)
    static let eye = SKColor(srgbRed: 0.18, green: 0.13, blue: 0.11, alpha: 1)
    static let zFill = SKColor(srgbRed: 0.84, green: 0.90, blue: 1.00, alpha: 1)
    static let zOutline = SKColor(srgbRed: 0.17, green: 0.23, blue: 0.40, alpha: 1)
    static let bubble = SKColor(srgbRed: 0.80, green: 0.91, blue: 1.00, alpha: 0.7)
    static let bubbleRim = SKColor(srgbRed: 0.45, green: 0.62, blue: 0.85, alpha: 0.9)
  }

  private enum Metrics {
    static let outlineWidth: CGFloat = 1.4
    static let neck = CGPoint(x: 0, y: 25)
    static let eyeSize = CGSize(width: 5.5, height: 7)
    static let eyeCentres = [CGPoint(x: -8, y: 12), CGPoint(x: 7, y: 12)]
    static let lidSize = CGSize(width: 8.5, height: 7.6)
    static let lidCurve: CGFloat = 1.6
    static let maxEarDroop: CGFloat = 0.55
    static let zSpots: [(position: CGPoint, size: CGFloat)] = [
      (CGPoint(x: 19, y: 53), 6.5),
      (CGPoint(x: 26, y: 64), 9),
    ]
  }

  /// The cat's root node.
  let node = SKNode()

  private let head = SKNode()
  private let ears: [SKNode]
  private let lids: [SKNode]
  private let lashes: [SKShapeNode]
  private let zs: [SKNode]
  private let snoreBubble: SKNode

  init() {
    let tail = Self.tail()
    let body = Self.shape(Self.bodyPath(), fill: Palette.fur)
    let belly = Self.shape(
      CGPath(ellipseIn: CGRect(x: -8, y: 3, width: 14, height: 16), transform: nil),
      fill: Palette.cream,
      stroke: nil
    )
    let paws = [CGPoint(x: -8, y: 2.5), CGPoint(x: 5, y: 2.5)].map { centre in
      Self.shape(
        CGPath(
          ellipseIn: CGRect(x: centre.x - 5, y: centre.y - 3, width: 10, height: 6),
          transform: nil
        ),
        fill: Palette.cream,
        lineWidth: 1.2
      )
    }

    ears = [CGPoint(x: -11, y: 21), CGPoint(x: 11, y: 21)].enumerated().map { index, base in
      let ear = Self.ear(mirrored: index == 1)
      ear.position = base
      return ear
    }

    let face = Self.shape(Self.facePath(), fill: Palette.fur)
    let eyes = Metrics.eyeCentres.map { Self.eye(at: $0) }
    var lids: [SKNode] = []
    var lashes: [SKShapeNode] = []
    for centre in Metrics.eyeCentres {
      let (lid, lash) = Self.lid()
      lid.position.x = centre.x
      lids.append(lid)
      lashes.append(lash)
    }
    self.lids = lids
    self.lashes = lashes
    let patch = Self.shape(
      CGPath(ellipseIn: CGRect(x: -5.5, y: -3, width: 11, height: 6), transform: nil),
      fill: Palette.patch,
      stroke: nil
    )
    patch.position = CGPoint(x: -8, y: 21.5)
    patch.zRotation = 0.3
    let muzzle = [CGPoint(x: -4.5, y: 5), CGPoint(x: 3, y: 5)].map { centre in
      Self.shape(
        CGPath(
          ellipseIn: CGRect(x: centre.x - 4.6, y: centre.y - 3.8, width: 9.2, height: 7.6),
          transform: nil
        ),
        fill: Palette.cream,
        stroke: nil
      )
    }
    let cheeks = [CGPoint(x: -13, y: 6.5), CGPoint(x: 12, y: 6.5)].map { centre in
      let cheek = Self.shape(
        CGPath(
          ellipseIn: CGRect(x: centre.x - 2.8, y: centre.y - 1.6, width: 5.6, height: 3.2),
          transform: nil
        ),
        fill: Palette.pink,
        stroke: nil
      )
      cheek.alpha = 0.55
      return cheek
    }
    let nose = Self.shape(Self.nosePath(), fill: Palette.pink, lineWidth: 0.8)
    let mouth = Self.shape(Self.mouthPath(), fill: nil, lineWidth: 1)
    let whiskers = Self.shape(Self.whiskersPath(), fill: nil, lineWidth: 0.6)
    whiskers.alpha = 0.7

    snoreBubble = Self.bubble()
    snoreBubble.position = CGPoint(x: -10.5, y: 3.5)

    zs = Metrics.zSpots.map { spot, size in
      let z = Self.z(size: size)
      z.position = spot
      return z
    }

    // Children draw in the order they are added, so later parts cover earlier ones.
    head.position = Metrics.neck
    var headParts: [SKNode] = ears
    headParts.append(face)
    headParts += eyes
    headParts += lids
    headParts.append(patch)
    headParts += muzzle
    headParts += cheeks
    headParts += [nose, mouth, whiskers, snoreBubble]
    for part in headParts {
      head.addChild(part)
    }
    var bodyParts: [SKNode] = [tail, body, belly]
    bodyParts += paws
    bodyParts.append(head)
    bodyParts += zs
    for part in bodyParts {
      node.addChild(part)
    }
    apply(MascotPose(for: .awake))
  }

  /// Puts the cat into `pose` at once.
  func apply(_ pose: MascotPose) {
    setEyelids(pose.eyelidOpenness)
    head.zRotation = CGFloat(pose.headTiltDegrees) * .pi / 180
    let droop = CGFloat(pose.earDroop) * Metrics.maxEarDroop
    ears[0].zRotation = droop
    ears[1].zRotation = -droop
    for (index, z) in zs.enumerated() {
      z.alpha = index < pose.zCount ? 1 : 0
    }
    snoreBubble.alpha = pose.showsSnoreBubble ? 1 : 0
  }

  /// Turns the cat to face `facing` by mirroring it. The "z"s are mirrored back, so they still
  /// read as the letter.
  func face(_ facing: DockPerch.Facing) {
    switch facing {
    case .left:
      node.xScale = 1
      node.position = Self.anchorFacingLeft
    case .right:
      node.xScale = -1
      node.position = CGPoint(
        x: Self.canvasSize.width - Self.anchorFacingLeft.x,
        y: Self.anchorFacingLeft.y
      )
    }
    for z in zs {
      z.xScale = node.xScale
    }
  }

  // MARK: - Eyelids

  private func setEyelids(_ openness: Double) {
    let open = CGFloat(min(max(openness, 0), 1))
    let eyeTop = Metrics.eyeCentres[0].y + Metrics.eyeSize.height / 2
    // At 1 the lid's lower edge rests on the top of the eye; at 0 it reaches the bottom.
    let lowerEdge = eyeTop - (1 - open) * Metrics.eyeSize.height
    for lid in lids {
      lid.position.y = lowerEdge
    }
    for lash in lashes {
      lash.alpha = open > 0.97 ? 0 : 1
    }
  }

  // MARK: - Shapes

  private static func shape(
    _ path: CGPath,
    fill: SKColor?,
    stroke: SKColor? = Palette.outline,
    lineWidth: CGFloat = Metrics.outlineWidth
  ) -> SKShapeNode {
    let node = SKShapeNode(path: path)
    node.fillColor = fill ?? .clear
    node.strokeColor = stroke ?? .clear
    node.lineWidth = stroke == nil ? 0 : lineWidth
    node.lineCap = .round
    node.lineJoin = .round
    node.isAntialiased = true
    return node
  }

  private static func bodyPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: -17, y: 1))
    path.addCurve(
      to: CGPoint(x: -11, y: 27),
      control1: CGPoint(x: -20, y: 12),
      control2: CGPoint(x: -16, y: 24)
    )
    path.addCurve(
      to: CGPoint(x: 11, y: 27),
      control1: CGPoint(x: -5, y: 31),
      control2: CGPoint(x: 5, y: 31)
    )
    path.addCurve(
      to: CGPoint(x: 17, y: 1),
      control1: CGPoint(x: 16, y: 24),
      control2: CGPoint(x: 20, y: 12)
    )
    path.addCurve(
      to: CGPoint(x: -17, y: 1),
      control1: CGPoint(x: 8, y: -1),
      control2: CGPoint(x: -8, y: -1)
    )
    path.closeSubpath()
    return path
  }

  private static func facePath() -> CGPath {
    // Wider than tall, with fuller cheeks below the eyes.
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: 27))
    path.addCurve(
      to: CGPoint(x: 20, y: 11),
      control1: CGPoint(x: 13, y: 27),
      control2: CGPoint(x: 20, y: 21)
    )
    path.addCurve(
      to: CGPoint(x: 0, y: -3),
      control1: CGPoint(x: 21, y: 2),
      control2: CGPoint(x: 12, y: -3)
    )
    path.addCurve(
      to: CGPoint(x: -20, y: 11),
      control1: CGPoint(x: -12, y: -3),
      control2: CGPoint(x: -21, y: 2)
    )
    path.addCurve(
      to: CGPoint(x: 0, y: 27),
      control1: CGPoint(x: -20, y: 21),
      control2: CGPoint(x: -13, y: 27)
    )
    path.closeSubpath()
    return path
  }

  private static func ear(mirrored: Bool) -> SKNode {
    let ear = SKNode()
    let side: CGFloat = mirrored ? -1 : 1
    let outer = CGMutablePath()
    outer.move(to: CGPoint(x: -7 * side, y: -3))
    outer.addQuadCurve(to: CGPoint(x: -5 * side, y: 12), control: CGPoint(x: -8 * side, y: 6))
    outer.addQuadCurve(to: CGPoint(x: 6 * side, y: 3), control: CGPoint(x: 1 * side, y: 10))
    outer.closeSubpath()
    let inner = CGMutablePath()
    inner.move(to: CGPoint(x: -4.5 * side, y: -0.5))
    inner.addQuadCurve(to: CGPoint(x: -4 * side, y: 8.5), control: CGPoint(x: -5.5 * side, y: 4))
    inner.addQuadCurve(to: CGPoint(x: 2.5 * side, y: 2.5), control: CGPoint(x: -0.5 * side, y: 7))
    inner.closeSubpath()
    ear.addChild(shape(outer, fill: Palette.fur))
    ear.addChild(shape(inner, fill: Palette.pink, stroke: nil))
    return ear
  }

  private static func eye(at centre: CGPoint) -> SKNode {
    let eye = SKNode()
    eye.position = centre
    let size = Metrics.eyeSize
    eye.addChild(
      shape(
        CGPath(
          ellipseIn: CGRect(
            x: -size.width / 2,
            y: -size.height / 2,
            width: size.width,
            height: size.height
          ),
          transform: nil
        ),
        fill: Palette.eye,
        stroke: nil
      )
    )
    eye.addChild(
      shape(
        CGPath(ellipseIn: CGRect(x: -0.4, y: 0.6, width: 2.2, height: 2.2), transform: nil),
        fill: .white,
        stroke: nil
      )
    )
    return eye
  }

  // A fur-coloured lid that slides down over the eye. Above the eye it lies on fur of the same
  // colour, so only its lower edge shows. The lash line marks that edge once the eye starts to
  // close.
  private static func lid() -> (SKNode, SKShapeNode) {
    let size = Metrics.lidSize
    let curve = Metrics.lidCurve
    let half = size.width / 2
    let fill = CGMutablePath()
    fill.move(to: CGPoint(x: -half, y: 0))
    fill.addQuadCurve(to: CGPoint(x: half, y: 0), control: CGPoint(x: 0, y: -curve * 2))
    fill.addLine(to: CGPoint(x: half, y: size.height))
    fill.addLine(to: CGPoint(x: -half, y: size.height))
    fill.closeSubpath()
    let edge = CGMutablePath()
    edge.move(to: CGPoint(x: -half + 0.6, y: 0))
    edge.addQuadCurve(to: CGPoint(x: half - 0.6, y: 0), control: CGPoint(x: 0, y: -curve * 2))
    let lid = SKNode()
    lid.addChild(shape(fill, fill: Palette.fur, stroke: nil))
    let lash = shape(edge, fill: nil, lineWidth: 1.2)
    lid.addChild(lash)
    return (lid, lash)
  }

  private static func nosePath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: -2.4, y: 9))
    path.addLine(to: CGPoint(x: 1.4, y: 9))
    path.addQuadCurve(to: CGPoint(x: -0.5, y: 6.8), control: CGPoint(x: 1, y: 7.4))
    path.addQuadCurve(to: CGPoint(x: -2.4, y: 9), control: CGPoint(x: -2, y: 7.4))
    path.closeSubpath()
    return path
  }

  private static func mouthPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: -0.5, y: 6.8))
    path.addLine(to: CGPoint(x: -0.5, y: 5.6))
    path.addQuadCurve(to: CGPoint(x: -3.6, y: 5.2), control: CGPoint(x: -1.8, y: 3.6))
    path.move(to: CGPoint(x: -0.5, y: 5.6))
    path.addQuadCurve(to: CGPoint(x: 2.6, y: 5.2), control: CGPoint(x: 0.8, y: 3.6))
    return path
  }

  private static func whiskersPath() -> CGPath {
    let path = CGMutablePath()
    for (from, to) in [
      (CGPoint(x: -9, y: 6.5), CGPoint(x: -20, y: 8)),
      (CGPoint(x: -9, y: 4.5), CGPoint(x: -19.5, y: 3)),
      (CGPoint(x: 8, y: 6.5), CGPoint(x: 19, y: 8)),
      (CGPoint(x: 8, y: 4.5), CGPoint(x: 18.5, y: 3)),
    ] {
      path.move(to: from)
      path.addLine(to: to)
    }
    return path
  }

  private static func tail() -> SKNode {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 13, y: 4))
    path.addCurve(
      to: CGPoint(x: 26, y: 17),
      control1: CGPoint(x: 24, y: 1),
      control2: CGPoint(x: 28, y: 9)
    )
    path.addQuadCurve(to: CGPoint(x: 21, y: 25), control: CGPoint(x: 25, y: 23))
    let tail = SKNode()
    let outline = shape(path, fill: nil, lineWidth: 6.4)
    let fill = shape(path, fill: nil, stroke: Palette.fur, lineWidth: 3.8)
    tail.addChild(outline)
    tail.addChild(fill)
    return tail
  }

  private static func bubble() -> SKNode {
    let bubble = SKNode()
    bubble.addChild(
      shape(
        CGPath(ellipseIn: CGRect(x: -4.2, y: -4.2, width: 8.4, height: 8.4), transform: nil),
        fill: Palette.bubble,
        stroke: Palette.bubbleRim,
        lineWidth: 0.9
      )
    )
    bubble.addChild(
      shape(
        CGPath(ellipseIn: CGRect(x: -2.4, y: 0.8, width: 1.8, height: 1.8), transform: nil),
        fill: .white,
        stroke: nil
      )
    )
    return bubble
  }

  private static func z(size: CGFloat) -> SKNode {
    let half = size / 2
    let path = CGMutablePath()
    path.move(to: CGPoint(x: -half, y: half))
    path.addLine(to: CGPoint(x: half, y: half))
    path.addLine(to: CGPoint(x: -half, y: -half))
    path.addLine(to: CGPoint(x: half, y: -half))
    let z = SKNode()
    z.addChild(shape(path, fill: nil, stroke: Palette.zOutline, lineWidth: size * 0.42))
    z.addChild(shape(path, fill: nil, stroke: Palette.zFill, lineWidth: size * 0.22))
    return z
  }
}
