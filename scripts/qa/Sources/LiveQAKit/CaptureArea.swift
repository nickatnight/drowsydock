import CoreGraphics

/// The part of the screen a screenshot covers, which maps its pixels to AppKit points and back.
public struct CaptureArea: Equatable, Sendable {
  /// The area in AppKit global coordinates: origin at the bottom-left of the primary display.
  public let frame: CGRect

  /// Pixels per point.
  public let scale: Double

  /// Creates the area a screenshot of `frame` covers, at `scale` pixels per point.
  public init(frame: CGRect, scale: Double) {
    self.frame = frame
    self.scale = scale
  }

  /// The area `DockAlignment` needs: the Dock's background with room for its edge searches on
  /// every side, and the cat's perch, kept on the Dock's display and on whole points.
  public static func around(
    background: CGRect,
    perch: CGRect,
    on screen: CGRect,
    scale: Double
  ) -> CaptureArea {
    let room = 2 * DockAlignment.searchDistance
    let frame = background.insetBy(dx: -room, dy: -room).union(perch).intersection(screen).integral
    return CaptureArea(frame: frame, scale: scale)
  }

  /// The pixel row, from the screenshot's top, that shows AppKit y `y`. Pixel row `r` spans
  /// `r ..< r + 1`, so an edge between two rows lies at a whole number.
  public func pixelRow(atY y: Double) -> Double {
    (frame.maxY - y) * scale
  }

  /// The AppKit y at pixel row `row` from the top.
  public func y(atPixelRow row: Double) -> Double {
    frame.maxY - row / scale
  }

  /// The pixel column, from the screenshot's left, that shows AppKit x `x`.
  public func pixelColumn(atX x: Double) -> Double {
    (x - frame.minX) * scale
  }

  /// The AppKit x at pixel column `column` from the left.
  public func x(atPixelColumn column: Double) -> Double {
    frame.minX + column / scale
  }

  /// The `-R x,y,w,h` argument for `screencapture`, which counts y down from the top of the
  /// primary display, whose height is `primaryHeight`.
  public func screencaptureRegion(primaryHeight: Double) -> String {
    let top = primaryHeight - frame.maxY
    return [frame.minX, top, frame.width, frame.height].map { String(Int($0.rounded())) }
      .joined(separator: ",")
  }
}
