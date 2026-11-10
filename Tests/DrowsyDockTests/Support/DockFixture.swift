import CoreGraphics
import DockOverlayKit

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
