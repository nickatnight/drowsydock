import CoreGraphics
import LiveQAKit
import XCTest

final class DockAlignmentTests: XCTestCase {
  private let area = CaptureArea(frame: CGRect(x: 0, y: 0, width: 200, height: 60), scale: 2)
  private let background = CGRect(x: 20, y: 5, width: 160, height: 30)
  private let perch = CGRect(x: 140, y: 35, width: 30, height: 20)

  private enum Pixel {
    static let desktop = 20.0
    static let dock = 60.0
    static let rim = 120.0
    static let cat = 200.0
  }

  private func screenshot(veil: CGRect? = nil, catBottom: Double? = nil) -> LumaImage {
    let (width, height) = (400, 120)
    var values = [Double](repeating: Pixel.desktop, count: width * height)
    for row in 0..<height {
      for column in 0..<width {
        let point = CGPoint(
          x: area.x(atPixelColumn: Double(column) + 0.5), y: area.y(atPixelRow: Double(row) + 0.5))
        var value = Pixel.desktop
        if background.contains(point) {
          let onRim = point.y > background.maxY - 0.5 || point.x > background.maxX - 0.5
          value = onRim ? Pixel.rim : Pixel.dock
        }
        if let veil, veil.contains(point) {
          value *= 0.72
        }
        if let catBottom, point.x > perch.minX, point.x < perch.maxX, point.y > catBottom,
          point.y < perch.maxY
        {
          value = Pixel.cat
        }
        values[row * width + column] = value
      }
    }
    return LumaImage(width: width, height: height, values: values)
  }

  private func checks(veil: CGRect, catBottom: Double) -> [String: EdgeCheck] {
    let alignment = DockAlignment(area: area, edge: .bottom, background: background, perch: perch)
    let checks = alignment.checks(
      bare: screenshot(),
      awake: screenshot(catBottom: catBottom),
      asleep: screenshot(veil: veil, catBottom: catBottom)
    )
    return Dictionary(uniqueKeysWithValues: checks.map { ($0.name, $0) })
  }

  func testAVeilAndCatPlacedOnTheBackgroundPassEveryCheck() {
    let checks = checks(veil: background, catBottom: background.maxY)

    XCTAssertEqual(checks.count, 5)
    for check in checks.values {
      XCTAssertTrue(check.passes, check.report)
    }
  }

  func testAVeilThreePointsTooHighFailsItsTopEdgeByThreePoints() throws {
    let checks = checks(veil: background.offsetBy(dx: 0, dy: 3), catBottom: background.maxY)

    let top = try XCTUnwrap(checks["veil, top edge (8.5)"])
    XCTAssertFalse(top.passes)
    XCTAssertEqual(try XCTUnwrap(top.offset), 3, accuracy: 0.01)
    XCTAssertTrue(try XCTUnwrap(checks["Dock rim, top edge (8.5)"]).passes)
  }

  func testAVeilTwoPointsShortFailsItsRightEnd() throws {
    let veil = CGRect(
      x: background.minX, y: background.minY, width: background.width - 2, height: background.height
    )
    let checks = checks(veil: veil, catBottom: background.maxY)

    let end = try XCTUnwrap(checks["veil, right end (8.5)"])
    XCTAssertFalse(end.passes)
    XCTAssertEqual(try XCTUnwrap(end.offset), -2, accuracy: 0.01)
  }

  func testPawsFivePointsAboveTheRimFail() throws {
    let checks = checks(veil: background, catBottom: background.maxY + 5)

    let paws = try XCTUnwrap(checks["paws on the Dock's top edge (8.15)"])
    XCTAssertFalse(paws.passes)
    XCTAssertEqual(try XCTUnwrap(paws.offset), 5, accuracy: 0.01)
  }

  func testIdenticalScreenshotsFindNoVeilAndNoCat() {
    let alignment = DockAlignment(area: area, edge: .bottom, background: background, perch: perch)
    let bare = screenshot()

    let checks = alignment.checks(bare: bare, awake: bare, asleep: bare)

    let missing = checks.filter { $0.found == nil }.map(\.name)
    XCTAssertEqual(
      Set(missing),
      ["veil, top edge (8.5)", "veil, right end (8.5)", "paws on the Dock's top edge (8.15)"]
    )
  }
}
