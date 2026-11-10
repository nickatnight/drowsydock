import CoreGraphics

extension CGRect {
  // AppKit asserts that a window frame lies inside (INT_MIN, INT_MIN) to (INT_MAX, INT_MAX).
  private static let windowCoordinateLimit = CGFloat(Int32.max)

  /// Whether a window can take this as its frame: not null, an area above zero, and every edge a
  /// finite value inside the window server's integer coordinate range. `NSWindow.setFrame`
  /// aborts the app on any other frame, so one that fails this means there is nothing to show.
  public var isUsableWindowFrame: Bool {
    guard !isNull, size.width > 0, size.height > 0 else { return false }
    let limit = Self.windowCoordinateLimit
    return [minX, minY, maxX, maxY].allSatisfy { $0.isFinite && abs($0) <= limit }
  }
}
