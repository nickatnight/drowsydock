import AppKit

/// The menu-bar icon: a battery outline with cat ears, a low charge bar and two closed eyes.
///
/// It is the app icon's mark reduced to one colour. The image is a template, so the menu bar
/// tints it for light and dark menu bars and for the highlighted state.
enum MenuBarGlyph {
  /// The image's size in points. Wider than tall, like the system's battery icon.
  static let size = NSSize(width: 20, height: 16)

  /// The label that VoiceOver reads for the menu-bar item.
  static let accessibilityDescription = "DrowsyDock"

  /// Returns the template image that the menu bar shows.
  static func image() -> NSImage {
    let image = NSImage(size: size, flipped: true) { _ in
      draw()
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = accessibilityDescription
    return image
  }

  // MARK: - Drawing

  // The shapes are laid out on the app icon's 1,024-point canvas (`Resources/AppIcon.svg`), with
  // y growing downwards; `canvasCenter` is the middle of the mark and `scale` maps it to points.
  private static let canvasCenter = NSPoint(x: 530, y: 521)

  private static let scale: CGFloat = 16 / 540

  private static func draw() {
    let transform = NSAffineTransform()
    transform.translateX(by: size.width / 2, yBy: size.height / 2)
    transform.scale(by: scale)
    transform.translateX(by: -canvasCenter.x, yBy: -canvasCenter.y)
    transform.concat()
    NSColor.black.set()

    let outline = batteryOutline()
    outline.lineWidth = 52
    outline.lineJoinStyle = .round
    outline.stroke()

    // The terminal nub, then the charge bar: a little charge left.
    NSBezierPath(
      roundedRect: NSRect(x: 778, y: 506, width: 48, height: 120), xRadius: 18, yRadius: 18
    ).fill()
    NSBezierPath(
      roundedRect: NSRect(x: 296, y: 450, width: 96, height: 232), xRadius: 14, yRadius: 14
    ).fill()

    let eyes = NSBezierPath()
    for left in [450, 582] as [CGFloat] {
      eyes.move(to: NSPoint(x: left, y: 556))
      eyes.curve(to: NSPoint(x: left + 88, y: 556), controlPoint: NSPoint(x: left + 44, y: 600))
    }
    eyes.lineWidth = 40
    eyes.lineCapStyle = .round
    eyes.stroke()
  }

  /// The battery's body, with the two ears rising from its top edge.
  private static func batteryOutline() -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 236, y: 420))
    path.line(to: NSPoint(x: 236, y: 712))
    path.curve(to: NSPoint(x: 266, y: 742), controlPoint: NSPoint(x: 236, y: 742))
    path.line(to: NSPoint(x: 718, y: 742))
    path.curve(to: NSPoint(x: 748, y: 712), controlPoint: NSPoint(x: 748, y: 742))
    path.line(to: NSPoint(x: 748, y: 420))
    path.curve(to: NSPoint(x: 718, y: 390), controlPoint: NSPoint(x: 748, y: 390))
    for point in [(676, 390), (640, 300), (590, 390), (394, 390), (344, 300), (308, 390)] {
      path.line(to: NSPoint(x: point.0, y: point.1))
    }
    path.line(to: NSPoint(x: 266, y: 390))
    path.curve(to: NSPoint(x: 236, y: 420), controlPoint: NSPoint(x: 236, y: 390))
    path.close()
    return path
  }
}
