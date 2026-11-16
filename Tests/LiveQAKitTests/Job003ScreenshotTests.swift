import CoreGraphics
import DockOverlayKit
import LiveQAKit
import XCTest

final class Job003ScreenshotTests: XCTestCase {
  private static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures")

  private let dock = DockGeometry(
    listFrame: AXRect(CGRect(x: 373, y: 893, width: 766, height: 79)),
    iconFrames: (0..<12).map {
      AXRect(CGRect(x: 378 + 63 * CGFloat($0), y: 898, width: 63, height: 79))
    },
    layout: DisplayLayout(primary: CGRect(x: 0, y: 0, width: 1512, height: 982))
  )

  private static let screenshotTopLeft = CGPoint(x: 312.4, y: 159)

  private static let scale = 2.0

  /// Returns the fixture `name`, cut from the full screenshot at `screenshotPixels` (top-left
  /// origin, in the full screenshot's pixels), and the screen area it shows.
  private func crop(
    _ name: String,
    screenshotPixels pixels: CGRect
  ) throws -> (LumaImage, CaptureArea) {
    let image = try LumaImage(contentsOf: Self.fixtures.appendingPathComponent("\(name).png"))
    let origin = Self.screenshotTopLeft
    let frame = CGRect(
      x: origin.x + pixels.minX / Self.scale,
      y: origin.y - pixels.maxY / Self.scale,
      width: pixels.width / Self.scale,
      height: pixels.height / Self.scale
    )
    return (image, CaptureArea(frame: frame, scale: Self.scale))
  }

  private let insideColumns = 10...70
  private let aboveTheRim = 5...27
  private let aroundTheTopRim = 15...45
  private let aroundTheRightEnd = 10...60
  private let midDockRows = 20...40

  func testTheStepFinderPutsTheOldVeilOnTheListFrameFivePointsAboveTheBackground() throws {
    let (image, area) = try crop(
      "veil-top-over-window",
      screenshotPixels: CGRect(x: 720, y: 120, width: 80, height: 50)
    )

    let row = try XCTUnwrap(
      Profile.strongestStep(in: image.profileDown(columns: insideColumns, rows: aboveTheRim))
    )
    let found = area.y(atPixelRow: Double(aboveTheRim.lowerBound + row))

    XCTAssertTrue(EdgeCheck(name: "old veil", expected: dock.frame.maxY, found: found).passes)
    let check = EdgeCheck(name: "veil", expected: dock.backgroundFrame.maxY, found: found)
    XCTAssertFalse(check.passes)
    XCTAssertEqual(try XCTUnwrap(check.offset), 5, accuracy: 0.5)
  }

  func testTheLineFinderPutsTheDocksRimOnTheBackgroundsTopEdge() throws {
    let (image, area) = try crop(
      "rim-top-over-dark",
      screenshotPixels: CGRect(x: 1430, y: 120, width: 80, height: 55)
    )

    let row = try XCTUnwrap(
      Profile.thinLine(in: image.profileDown(columns: insideColumns, rows: aroundTheTopRim))
    )
    let found = area.y(atPixelRow: Double(aroundTheTopRim.lowerBound + row) + 0.5)

    XCTAssertTrue(EdgeCheck(name: "rim", expected: dock.backgroundFrame.maxY, found: found).passes)
    XCTAssertFalse(EdgeCheck(name: "rim", expected: dock.frame.maxY, found: found).passes)
  }

  func testTheLineFinderPutsTheRimsRightEndOnTheBackgroundsRightEdge() throws {
    let (image, area) = try crop(
      "rim-right-end",
      screenshotPixels: CGRect(x: 1625, y: 200, width: 80, height: 60)
    )

    let column = try XCTUnwrap(
      Profile.thinLine(in: image.profileAcross(rows: midDockRows, columns: aroundTheRightEnd))
    )
    let found = area.x(atPixelColumn: Double(aroundTheRightEnd.lowerBound + column) + 0.5)

    XCTAssertTrue(EdgeCheck(name: "rim", expected: dock.backgroundFrame.maxX, found: found).passes)
  }
}
