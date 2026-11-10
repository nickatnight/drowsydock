import CoreGraphics
import DockOverlayKit

/// Dock geometries as macOS 27 reports them, on a 1512 × 982-point display.
///
/// The display sits 50,000 points from the real ones, so an overlay window placed on one of these
/// Docks during a test is on no screen. The bottom Dock is the user's from job 003 (ADR 0013): the
/// list at Accessibility (373, 893, 766, 79) with its twelve 63 × 79-point items 5 points lower.
/// The side Docks follow the same rule, 5 points from their edge.
enum DockFixture {
  static let offset: CGFloat = 50_000

  static let display = CGRect(x: offset, y: offset, width: 1512, height: 982)

  static var bottom: DockGeometry {
    let items = (0..<12).map { index in
      ax(378 + 63 * CGFloat(index), 898, 63, 79)
    }
    return DockGeometry(
      listFrame: ax(373, 893, 766, 79),
      iconFrames: items,
      layout: DisplayLayout(primary: display)
    )
  }

  static var left: DockGeometry {
    let items = (0..<8).map { index in
      ax(0, 240 + 63 * CGFloat(index), 79, 63)
    }
    return DockGeometry(
      listFrame: ax(5, 235, 79, 514),
      iconFrames: items,
      layout: DisplayLayout(primary: display)
    )
  }

  static var right: DockGeometry {
    let items = (0..<8).map { index in
      ax(1433, 240 + 63 * CGFloat(index), 79, 63)
    }
    return DockGeometry(
      listFrame: ax(1428, 235, 79, 514),
      iconFrames: items,
      layout: DisplayLayout(primary: display)
    )
  }

  private static func ax(
    _ x: CGFloat,
    _ y: CGFloat,
    _ width: CGFloat,
    _ height: CGFloat
  ) -> AXRect {
    AXRect(CGRect(x: offset + x, y: y, width: width, height: height))
  }
}
