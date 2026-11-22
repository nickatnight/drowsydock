import AppKit
import XCTest

@testable import DrowsyDock

@MainActor
final class MenuBarGlyphTests: XCTestCase {
  func testTheGlyphIsATemplateSoTheMenuBarTintsIt() {
    XCTAssertTrue(MenuBarGlyph.image().isTemplate)
  }

  func testTheGlyphIsTwentyBySixteenPoints() {
    XCTAssertEqual(MenuBarGlyph.image().size, NSSize(width: 20, height: 16))
  }

  func testVoiceOverReadsTheAppName() {
    XCTAssertEqual(MenuBarGlyph.image().accessibilityDescription, "DrowsyDock")
  }

  func testTheGlyphIsABatteryWithCatEarsALowChargeAndClosedEyes() throws {
    try Snapshot.skipUnlessComparable()
    Snapshot.assert(render(scale: 2), named: "menu-bar-glyph", within: .sameRenderer)
  }

  /// Draws the glyph in black over the snapshot backdrop at `scale` pixels per point.
  private func render(scale: Int) -> Bitmap {
    let width = Int(MenuBarGlyph.size.width) * scale
    let height = Int(MenuBarGlyph.size.height) * scale
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: width,
      pixelsHigh: height,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    MenuBarGlyph.image().draw(in: NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    var bitmap = Bitmap(width: width, height: height, filledWith: Snapshot.backdrop)
    bitmap.draw(rep.cgImage!, atBottomLeft: .zero)
    return bitmap
  }
}
