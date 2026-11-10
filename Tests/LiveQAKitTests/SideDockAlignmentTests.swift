import CoreGraphics
import LiveQAKit
import XCTest

final class SideDockAlignmentTests: XCTestCase {
  private let area = CaptureArea(frame: CGRect(x: 0, y: 0, width: 60, height: 200), scale: 2)
  private let background = CGRect(x: 5, y: 20, width: 30, height: 160)
  private let perch = CGRect(x: 5, y: 180, width: 30, height: 20)

  private func screenshot(veil: CGRect? = nil, catBottom: Double? = nil) -> LumaImage {
    let (width, height) = (120, 400)
    var values = [Double](repeating: 20, count: width * height)
    for row in 0..<height {
      for column in 0..<width {
        let point = CGPoint(
          x: area.x(atPixelColumn: Double(column) + 0.5),
          y: area.y(atPixelRow: Double(row) + 0.5)
        )
        var value = 20.0
        if background.contains(point) {
          value = point.x > background.maxX - 0.5 ? 120 : 60
        }
        if let veil, veil.contains(point) {
          value *= 0.72
        }
        if let catBottom, perch.contains(point), point.y > catBottom {
          value = 200
        }
        values[row * width + column] = value
      }
    }
    return LumaImage(width: width, height: height, values: values)
  }

  private func checks(veil: CGRect) -> [EdgeCheck] {
    DockAlignment(area: area, edge: .left, background: background, perch: perch).checks(
      bare: screenshot(),
      awake: screenshot(catBottom: background.maxY),
      asleep: screenshot(veil: veil, catBottom: background.maxY)
    )
  }

  func testAVeilAndCatPlacedOnALeftDockPassEveryCheck() {
    let checks = checks(veil: background)

    XCTAssertEqual(checks.count, 3)
    for check in checks {
      XCTAssertTrue(check.passes, check.report)
    }
  }

  func testAVeilTwoPointsShortOfTheInnerEdgeFails() throws {
    let narrow = CGRect(x: 5, y: 20, width: 28, height: 160)

    let inner = try XCTUnwrap(checks(veil: narrow).first { $0.name == "veil, inner edge (8.9)" })

    XCTAssertFalse(inner.passes)
    XCTAssertEqual(try XCTUnwrap(inner.offset), -2, accuracy: 0.01)
  }
}
