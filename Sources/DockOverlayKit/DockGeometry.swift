import CoreGraphics

/// The screen edge the Dock sits on.
public enum DockOrientation: Sendable {
  case bottom
  case left
  case right
}

/// Where a sprite sits on the Dock, and which way it faces.
public struct DockPerch: Equatable, Sendable {
  /// A horizontal direction.
  public enum Facing: Sendable {
    case left
    case right
  }

  /// The sprite's frame in AppKit global coordinates.
  public let frame: CGRect

  /// The direction that faces into the screen.
  public let facing: Facing

  /// Creates a perch.
  public init(frame: CGRect, facing: Facing) {
    self.frame = frame
    self.facing = facing
  }
}

/// The Dock's frames in AppKit global coordinates, and the display it is on.
public struct DockGeometry: Equatable, Sendable {
  // Absorbs rounding between Accessibility frames and display frames, so that a Dock flush with
  // the display edge counts as on screen, and a half-point difference doesn't count as growth.
  private static let edgeTolerance: CGFloat = 1

  // The largest magnified icon size that System Settings allows, in points.
  private static let largestMagnifiedIconSize: CGFloat = 128

  /// The frame of the Dock's icon list.
  public let frame: CGRect

  /// The frames of the Dock's items in Dock order, without separators.
  public let iconFrames: [CGRect]

  /// The frame of the display that holds the Dock.
  public let screenFrame: CGRect

  /// The screen edge the Dock sits on.
  public let orientation: DockOrientation

  /// Builds the geometry from the frames that the Accessibility API reports for the Dock's list
  /// and its items.
  public init(listFrame: AXRect, iconFrames: [AXRect], layout: DisplayLayout) {
    frame = layout.appKitRect(listFrame)
    self.iconFrames = iconFrames.map(layout.appKitRect)
    screenFrame = layout.display(holding: frame)
    orientation = Self.orientation(of: frame, on: screenFrame)
  }

  /// Whether the Dock is off screen, as an auto-hidden Dock is until the pointer reaches the edge.
  public var isHidden: Bool {
    let edge = Self.edgeTolerance
    return frame.isEmpty || !screenFrame.insetBy(dx: -edge, dy: -edge).contains(frame)
  }

  /// Returns where a sprite of the given size perches.
  ///
  /// On a bottom Dock it sits on the top edge at the trailing end, inside the last icon. On a side
  /// Dock it sits on the top end, centred above the first icon and facing into the screen. The
  /// frame is kept on the Dock's display.
  public func perch(for size: CGSize) -> DockPerch {
    let origin: CGPoint
    let facing: DockPerch.Facing
    switch orientation {
    case .bottom:
      let anchor = iconFrames.last ?? frame
      origin = CGPoint(x: anchor.maxX - size.width, y: frame.maxY)
      facing = .left
    case .left, .right:
      let anchor = iconFrames.first ?? frame
      origin = CGPoint(x: anchor.midX - size.width / 2, y: frame.maxY)
      facing = orientation == .left ? .right : .left
    }
    let clamped = CGPoint(
      x: min(max(origin.x, screenFrame.minX), screenFrame.maxX - size.width),
      y: min(max(origin.y, screenFrame.minY), screenFrame.maxY - size.height)
    )
    return DockPerch(frame: CGRect(origin: clamped, size: size), facing: facing)
  }

  /// The area around the resting Dock where the pointer may be over the Dock, even while it is
  /// magnified.
  public var hoverRegion: CGRect {
    frame.insetBy(dx: -Self.largestMagnifiedIconSize, dy: -Self.largestMagnifiedIconSize)
  }

  /// Returns whether `current` is the Dock at `resting`, magnified by the pointer.
  ///
  /// Magnification only grows the list or its icons. A Dock that shrank, or whose icons were
  /// added or removed, has a new resting geometry instead.
  public static func isMagnified(current: DockGeometry, resting: DockGeometry) -> Bool {
    if grew(from: resting.frame, to: current.frame) { return true }
    guard current.iconFrames.count == resting.iconFrames.count else { return false }
    return zip(resting.iconFrames, current.iconFrames).contains { grew(from: $0, to: $1) }
  }

  private static func grew(from resting: CGRect, to current: CGRect) -> Bool {
    current.width > resting.width + edgeTolerance || current.height > resting.height + edgeTolerance
  }

  // The Dock always holds at least Finder and the Trash, so a bottom Dock is wider than it is
  // tall, and a side Dock is taller than it is wide.
  private static func orientation(of frame: CGRect, on screen: CGRect) -> DockOrientation {
    if frame.width >= frame.height { return .bottom }
    return frame.midX < screen.midX ? .left : .right
  }
}
