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

  private func screenshot(
    veil: CGRect? = nil,
    catBottom: Double? = nil,
    drawnBackground: CGRect? = nil
  ) -> LumaImage {
    let drawn = drawnBackground ?? background
    let (width, height) = (400, 120)
    var values = [Double](repeating: Pixel.desktop, count: width * height)
    for row in 0..<height {
      for column in 0..<width {
        let point = CGPoint(
          x: area.x(atPixelColumn: Double(column) + 0.5), y: area.y(atPixelRow: Double(row) + 0.5))
        var value = Pixel.desktop
        if drawn.contains(point) {
          let onRim =
            point.y > drawn.maxY - 0.5 || point.y < drawn.minY + 0.5
            || point.x > drawn.maxX - 0.5 || point.x < drawn.minX + 0.5
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

  private func checks(
    veil: CGRect,
    catBottom: Double,
    drawnBackground: CGRect? = nil
  ) -> [String: EdgeCheck] {
    let alignment = DockAlignment(area: area, edge: .bottom, background: background, perch: perch)
    let checks = alignment.checks(
      bare: screenshot(drawnBackground: drawnBackground),
      awake: screenshot(catBottom: catBottom, drawnBackground: drawnBackground),
      asleep: screenshot(veil: veil, catBottom: catBottom, drawnBackground: drawnBackground)
    )
    return Dictionary(uniqueKeysWithValues: checks.map { ($0.name, $0) })
  }

  func testAVeilAndCatPlacedOnTheBackgroundPassEveryCheck() {
    let checks = checks(veil: background, catBottom: background.maxY)

    XCTAssertEqual(checks.count, 13)
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

    let paws = try XCTUnwrap(checks["paws on the Dock's top edge (8.15 6.1)"])
    XCTAssertFalse(paws.passes)
    XCTAssertEqual(try XCTUnwrap(paws.offset), 5, accuracy: 0.01)
  }

  func testIdenticalScreenshotsFindNoVeilAndNoCat() {
    let alignment = DockAlignment(area: area, edge: .bottom, background: background, perch: perch)
    let bare = screenshot()

    let checks = alignment.checks(bare: bare, awake: bare, asleep: bare)

    let missing = Set(checks.filter { $0.found == nil }.map(\.name))
    let rims = Set(checks.filter { $0.name.hasPrefix("Dock rim") }.map(\.name))
    XCTAssertEqual(missing, Set(checks.map(\.name)).subtracting(rims))
  }

  func testAVeilOnTheDrawnOutlinePassesAgainstTheRimEvenWhereTheFramesAreOff() throws {
    let drawn = background.offsetBy(dx: 0, dy: 2)
    let checks = checks(veil: drawn, catBottom: drawn.maxY, drawnBackground: drawn)

    XCTAssertFalse(try XCTUnwrap(checks["Dock rim, top edge (8.5)"]).passes)
    XCTAssertTrue(try XCTUnwrap(checks["veil against the rim, top edge (8.5)"]).passes)
  }

  func testAVeilTwoPointsShortOfTheLeftEndFailsAgainstTheFramesAndTheRim() throws {
    let veil = CGRect(
      x: background.minX + 2, y: background.minY, width: background.width - 2,
      height: background.height)
    let checks = checks(veil: veil, catBottom: background.maxY)

    XCTAssertFalse(try XCTUnwrap(checks["veil, left end (8.5)"]).passes)
    XCTAssertFalse(try XCTUnwrap(checks["veil against the rim, left end (8.5)"]).passes)
    XCTAssertTrue(try XCTUnwrap(checks["veil, right end (8.5)"]).passes)
  }

  func testAVeilThatStopsShortOfTheBottomEdgeFails() throws {
    let veil = CGRect(
      x: background.minX, y: background.minY + 2, width: background.width,
      height: background.height - 2)
    let checks = checks(veil: veil, catBottom: background.maxY)

    XCTAssertFalse(try XCTUnwrap(checks["veil, bottom edge (8.5)"]).passes)
  }

  func testWithNoRimTheVeilAgainstTheRimFindsNothing() throws {
    let flat = LumaImage(width: 400, height: 120, values: [Double](repeating: 60, count: 48_000))
    var veiled = flat.values
    for row in 0..<120 {
      for column in 0..<400 {
        let point = CGPoint(
          x: area.x(atPixelColumn: Double(column) + 0.5), y: area.y(atPixelRow: Double(row) + 0.5))
        if background.contains(point) {
          veiled[row * 400 + column] *= 0.72
        }
      }
    }
    let asleep = LumaImage(width: 400, height: 120, values: veiled)
    let alignment = DockAlignment(area: area, edge: .bottom, background: background, perch: perch)

    let checks = Dictionary(
      uniqueKeysWithValues: alignment.checks(bare: flat, awake: flat, asleep: asleep).map {
        ($0.name, $0)
      })

    XCTAssertNil(try XCTUnwrap(checks["Dock rim, top edge (8.5)"]).found)
    XCTAssertNotNil(try XCTUnwrap(checks["veil, top edge (8.5)"]).found)
    let againstRim = try XCTUnwrap(checks["veil against the rim, top edge (8.5)"])
    XCTAssertNil(againstRim.found)
    XCTAssertFalse(againstRim.passes)
  }
}
