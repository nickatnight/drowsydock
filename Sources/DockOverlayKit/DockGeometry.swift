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
  private static let roundingTolerance: CGFloat = 1

  // The largest magnified icon size that System Settings allows, in points.
  private static let largestMagnifiedIconSize: CGFloat = 128

  /// The frame of the Dock's icon list.
  public let frame: CGRect

  /// The frames of the Dock's items in Dock order, without separators. An item whose frame has a
  /// non-finite component or edge is left out.
  public let iconFrames: [CGRect]

  /// The frame of the background the Dock draws behind its items.
  ///
  /// From macOS 26 the list frame sits 5 points further from the screen edge than the drawn
  /// background, while the items, as thick as the list, line up with it. So this is the list frame
  /// slid toward the screen edge until it holds the items, but never by more than the Dock's
  /// thickness. Where the list already holds them, as before macOS 26, it is the list frame.
  public let backgroundFrame: CGRect

  /// The frame of the display that holds the Dock.
  public let screenFrame: CGRect

  /// The visible frame of the display that holds the Dock: its frame without the menu bar and the
  /// Dock.
  public let visibleScreenFrame: CGRect

  /// The screen edge the Dock sits on.
  public let orientation: DockOrientation

  /// Builds the geometry from the frames that the Accessibility API reports for the Dock's list
  /// and its items.
  public init(listFrame: AXRect, iconFrames: [AXRect], layout: DisplayLayout) {
    frame = layout.appKitRect(listFrame)
    self.iconFrames = iconFrames.map(layout.appKitRect).filter(Self.hasFiniteEdges)
    let display = layout.display(holding: frame)
    screenFrame = display.frame
    visibleScreenFrame = display.visibleFrame
    orientation = Self.orientation(of: frame, on: screenFrame)
    backgroundFrame = Self.background(of: frame, holding: self.iconFrames, along: orientation)
  }

  /// The radius of the background's rounded corners: 0.28 of the Dock's thickness, which matched
  /// the corners of a 79-point-thick Dock on macOS 27 (ADR 0013).
  public var backgroundCornerRadius: CGFloat {
    min(backgroundFrame.width, backgroundFrame.height) * Self.cornerRadiusPerThickness
  }

  private static let cornerRadiusPerThickness: CGFloat = 0.28

  private static let artworkPerItemSide: CGFloat = 0.76

  /// Returns the frame of the icon artwork that the Dock draws inside an item: a square centred in
  /// the item. From macOS 26 an item is taller than its artwork is wide, so the square follows the
  /// item's shorter side.
  public static func artworkFrame(ofItem item: CGRect) -> CGRect {
    let side = min(item.width, item.height) * artworkPerItemSide
    return CGRect(x: item.midX - side / 2, y: item.midY - side / 2, width: side, height: side)
  }

  // An app icon is a rounded square whose corners span this fraction of its side.
  private static let artworkCornerRadiusPerSide: CGFloat = 0.22

  /// Returns the corner radius of icon artwork with the given frame.
  public static func artworkCornerRadius(of artwork: CGRect) -> CGFloat {
    artwork.width * artworkCornerRadiusPerSide
  }

  private static func background(
    of list: CGRect,
    holding icons: [CGRect],
    along orientation: DockOrientation
  ) -> CGRect {
    guard let first = icons.first else { return list }
    let items = icons.dropFirst().reduce(first) { $0.union($1) }
    let overhang: CGFloat
    switch orientation {
    case .bottom: overhang = list.minY - items.minY
    case .left: overhang = list.minX - items.minX
    case .right: overhang = items.maxX - list.maxX
    }
    guard overhang.isFinite, overhang > 0 else { return list }
    let slide = min(overhang, min(list.width, list.height))
    switch orientation {
    case .bottom: return list.offsetBy(dx: 0, dy: -slide)
    case .left: return list.offsetBy(dx: -slide, dy: 0)
    case .right: return list.offsetBy(dx: slide, dy: 0)
    }
  }

  private static func hasFiniteEdges(_ rect: CGRect) -> Bool {
    [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy(\.isFinite)
  }

  /// Whether the Dock is off screen, as an auto-hidden Dock is until the pointer reaches the edge.
  public var isHidden: Bool {
    let tolerance = Self.roundingTolerance
    return frame.isEmpty || !screenFrame.insetBy(dx: -tolerance, dy: -tolerance).contains(frame)
  }

  /// Returns where a sprite of the given size perches.
  ///
  /// On a bottom Dock it sits on the top edge of the drawn background at the trailing end, inside
  /// the last icon. On a side Dock it sits on the top end, centred above the first icon and facing
  /// into the screen. The frame is kept on the Dock's display and below its menu bar. It may sit
  /// outside the rest of the visible frame, because the Dock itself lies outside it.
  public func perch(for size: CGSize) -> DockPerch {
    let origin: CGPoint
    let facing: DockPerch.Facing
    let anchor = perchIcon
    switch orientation {
    case .bottom:
      origin = CGPoint(x: anchor.maxX - size.width, y: backgroundFrame.maxY)
      facing = .left
    case .left, .right:
      origin = CGPoint(x: anchor.midX - size.width / 2, y: backgroundFrame.maxY)
      facing = orientation == .left ? .right : .left
    }
    let clamped = CGPoint(
      x: min(max(origin.x, screenFrame.minX), screenFrame.maxX - size.width),
      y: min(max(origin.y, screenFrame.minY), visibleScreenFrame.maxY - size.height)
    )
    return DockPerch(frame: CGRect(origin: clamped, size: size), facing: facing)
  }

  /// The icon frames in the order the eye runs along the Dock: left to right on a bottom Dock, top
  /// to bottom on a side Dock.
  public var iconFramesAlongDock: [CGRect] {
    switch orientation {
    case .bottom: iconFrames.sorted { $0.minX < $1.minX }
    case .left, .right: iconFrames.sorted { $0.maxY > $1.maxY }
    }
  }

  /// The perch for a sprite of the given size together with the icon it sits on. While the pointer
  /// is here, the Dock shows that icon's label, which the sprite would cover.
  public func perchRegion(for size: CGSize) -> CGRect {
    perch(for: size).frame.union(perchIcon)
  }

  private var perchIcon: CGRect {
    switch orientation {
    case .bottom: iconFrames.last ?? frame
    case .left, .right: iconFrames.first ?? frame
    }
  }

  /// The area around the resting Dock where the pointer may be over the Dock, even while it is
  /// magnified.
  public var hoverRegion: CGRect {
    frame.insetBy(dx: -Self.largestMagnifiedIconSize, dy: -Self.largestMagnifiedIconSize)
  }

  /// Returns whether `current` is the Dock at `resting`, magnified by the pointer.
  ///
  /// Magnification only grows the list or its icons, and never changes the orientation or the
  /// display. A Dock that shrank, moved to another edge or display, or whose icons were added or
  /// removed, has a new resting geometry instead. A Dock made larger by dragging its separator
  /// can't be told apart from a magnified one, so it counts as magnified until the pointer leaves.
  public static func isMagnified(current: DockGeometry, resting: DockGeometry) -> Bool {
    guard current.orientation == resting.orientation, current.screenFrame == resting.screenFrame
    else { return false }
    if grew(from: resting.frame, to: current.frame) { return true }
    guard current.iconFrames.count == resting.iconFrames.count else { return false }
    return zip(resting.iconFrames, current.iconFrames).contains { grew(from: $0, to: $1) }
  }

  private static func grew(from resting: CGRect, to current: CGRect) -> Bool {
    current.width > resting.width + roundingTolerance
      || current.height > resting.height + roundingTolerance
  }

  // The Dock always holds at least Finder and the Trash, so a bottom Dock is wider than it is
  // tall, and a side Dock is taller than it is wide.
  private static func orientation(of frame: CGRect, on screen: CGRect) -> DockOrientation {
    if frame.width >= frame.height { return .bottom }
    return frame.midX < screen.midX ? .left : .right
  }
}
