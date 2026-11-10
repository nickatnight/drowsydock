import CoreGraphics
import DockOverlayKit
import LiveQAKit
import XCTest

// The edge finders and the comparison against the Accessibility frames, run on crops of the user's
// job 003 screenshot (2x, macOS 27.0.1, bottom Dock): the veil was drawn on the Dock's list frame,
// 5 points above the Dock's drawn background (ADR 0013). The crops hold no Dock icons.
//
// The screenshot's pixel (px, py) shows AppKit point (312.4 + px / 2, 159 - py / 2), from the
// Finder icon's centre and the old veil's top edge (job 003 build.md, `veilfit`).
final class Job003ScreenshotTests: XCTestCase {
  private static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures")

  // The frames the user's app read: the list, and its items 5 points lower, on a 1512 x 982 display.
  private let dock = DockGeometry(
    listFrame: AXRect(CGRect(x: 373, y: 893, width: 766, height: 79)),
    iconFrames: (0..<12).map {
      AXRect(CGRect(x: 378 + 63 * CGFloat($0), y: 898, width: 63, height: 79))
    },
    layout: DisplayLayout(primary: CGRect(x: 0, y: 0, width: 1512, height: 982))
  )

  private func crop(_ name: String, x: Double, y: Double, width: Double, height: Double) throws -> (
    LumaImage, CaptureArea
  ) {
    let image = try LumaImage(contentsOf: Self.fixtures.appendingPathComponent("\(name).png"))
    let frame = CGRect(
      x: 312.4 + x / 2,
      y: 159 - (y + height) / 2,
      width: width / 2,
      height: height / 2
    )
    return (image, CaptureArea(frame: frame, scale: 2))
  }

  // The window holds the veil's edge over the Mail window behind the Dock, and stops above the
  // Dock's rim, which is a stronger feature.
  func testTheStepFinderPutsTheOldVeilOnTheListFrameFivePointsAboveTheBackground() throws {
    let (image, area) = try crop("veil-top-over-window", x: 720, y: 120, width: 80, height: 50)

    let row = try XCTUnwrap(
      Profile.strongestStep(in: image.profileDown(columns: 10...70, rows: 5...27))
    )
    let found = area.y(atPixelRow: Double(5 + row))

    XCTAssertTrue(EdgeCheck(name: "old veil", expected: dock.frame.maxY, found: found).passes)
    let check = EdgeCheck(name: "veil", expected: dock.backgroundFrame.maxY, found: found)
    XCTAssertFalse(check.passes)
    XCTAssertEqual(try XCTUnwrap(check.offset), 5, accuracy: 0.5)
  }

  func testTheLineFinderPutsTheDocksRimOnTheBackgroundsTopEdge() throws {
    let (image, area) = try crop("rim-top-over-dark", x: 1430, y: 120, width: 80, height: 55)

    let row = try XCTUnwrap(
      Profile.thinLine(in: image.profileDown(columns: 10...70, rows: 15...45))
    )
    let found = area.y(atPixelRow: Double(15 + row) + 0.5)

    XCTAssertTrue(EdgeCheck(name: "rim", expected: dock.backgroundFrame.maxY, found: found).passes)
    XCTAssertFalse(EdgeCheck(name: "rim", expected: dock.frame.maxY, found: found).passes)
  }

  func testTheLineFinderPutsTheRimsRightEndOnTheBackgroundsRightEdge() throws {
    let (image, area) = try crop("rim-right-end", x: 1625, y: 200, width: 80, height: 60)

    let column = try XCTUnwrap(
      Profile.thinLine(in: image.profileAcross(rows: 20...40, columns: 10...60))
    )
    let found = area.x(atPixelColumn: Double(10 + column) + 0.5)

    XCTAssertTrue(EdgeCheck(name: "rim", expected: dock.backgroundFrame.maxX, found: found).passes)
  }
}
