import CoreGraphics

/// A rectangle in Accessibility coordinates: origin at the top-left of the primary display, with y
/// growing downward.
///
/// It has its own type so that an Accessibility frame can't be used where AppKit coordinates are
/// expected. `DisplayLayout.appKitRect(_:)` converts it.
public struct AXRect: Equatable, Sendable {
  /// The rectangle, still in Accessibility coordinates.
  public let rect: CGRect

  /// Wraps a rectangle that the Accessibility API reported.
  public init(_ rect: CGRect) {
    self.rect = rect
  }
}

/// The frames of the connected displays in AppKit global coordinates: origin at the bottom-left of
/// the primary display, with y growing upward.
public struct DisplayLayout: Equatable, Sendable {
  /// The display with the menu bar, whose top-left corner is the Accessibility origin.
  public let primary: CGRect

  /// Every other display.
  public let others: [CGRect]

  /// Creates a layout from `NSScreen.screens`: its first element is the primary display.
  public init(primary: CGRect, others: [CGRect] = []) {
    self.primary = primary
    self.others = others
  }

  /// Returns the AppKit global frame of a rectangle that the Accessibility API reported.
  public func appKitRect(_ rect: AXRect) -> CGRect {
    CGRect(
      x: rect.rect.minX,
      y: primary.maxY - rect.rect.maxY,
      width: rect.rect.width,
      height: rect.rect.height
    )
  }

  /// Returns the display that holds the centre of `rect`, or the nearest display when the centre
  /// lies on none of them, as it does for an auto-hidden Dock.
  func display(holding rect: CGRect) -> CGRect {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    return others.reduce(primary) { nearest, display in
      distance(from: center, to: display) < distance(from: center, to: nearest) ? display : nearest
    }
  }

  private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
    let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
    let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
    return (dx * dx + dy * dy).squareRoot()
  }
}
