import CoreGraphics
import DockOverlayKit
import SpriteKit

@testable import DrowsyDock

@MainActor
final class OverlayFilm {
  static let backdrop: (red: UInt8, green: UInt8, blue: UInt8) = (214, 220, 230)

  let overlay: MascotOverlay
  private let area: CGRect
  private let icons = SKScene()
  private let cat: OffscreenRenderer
  private let canvas: OffscreenRenderer
  private let iconLayer: OffscreenRenderer

  init(_ overlay: MascotOverlay, on dock: DockGeometry) {
    self.overlay = overlay
    let canvasFrame = MascotOverlay.canvasFrame(around: dock)
    area = canvasFrame.union(dock.perch(for: MascotOverlay.spriteSize).frame)
    icons.size = area.size
    icons.backgroundColor = .clear
    icons.anchorPoint = .zero
    for item in dock.iconFrames {
      let artwork = DockGeometry.artworkFrame(ofItem: item)
        .offsetBy(dx: -area.minX, dy: -area.minY)
      let radius = DockGeometry.artworkCornerRadius(of: artwork)
      let icon = SKShapeNode(
        path: CGPath(
          roundedRect: artwork, cornerWidth: radius, cornerHeight: radius, transform: nil)
      )
      icon.fillColor = SKColor(srgbRed: 0.98, green: 0.98, blue: 1, alpha: 1)
      icon.strokeColor = SKColor(srgbRed: 0.55, green: 0.58, blue: 0.65, alpha: 1)
      icons.addChild(icon)
    }
    iconLayer = OffscreenRenderer(scene: icons)
    cat = OffscreenRenderer(scene: overlay.catScene)
    canvas = OffscreenRenderer(scene: overlay.canvasScene, size: canvasFrame.size)
  }

  func advance(by seconds: TimeInterval) {
    OffscreenRenderer.advance([cat, canvas], by: seconds)
  }

  func strip(at times: [TimeInterval]) -> Bitmap {
    var elapsed: TimeInterval = 0
    var frames: [Bitmap] = []
    for time in times {
      advance(by: time - elapsed)
      elapsed = time
      frames.append(render())
    }
    let isWide = area.width > area.height
    return isWide
      ? Bitmap.column(frames, gap: 4, background: (255, 255, 255))
      : Bitmap.row(frames, gap: 4, background: (255, 255, 255))
  }

  func render() -> Bitmap {
    var image = iconLayer.render(over: Self.backdrop)
    let scale = CGFloat(OffscreenRenderer.scale)
    for (window, renderer) in [(overlay.canvasWindow, canvas), (overlay.catWindow, cat)]
    where window.visibility == .shown {
      image.draw(
        renderer.render(over: nil).cgImage,
        atBottomLeft: CGPoint(
          x: (window.frame.minX - area.minX) * scale,
          y: (window.frame.minY - area.minY) * scale
        )
      )
    }
    return image
  }
}
