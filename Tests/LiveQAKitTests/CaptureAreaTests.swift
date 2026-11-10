import CoreGraphics
import LiveQAKit
import XCTest

final class CaptureAreaTests: XCTestCase {
  private let area = CaptureArea(frame: CGRect(x: 325, y: 0, width: 862, height: 132), scale: 2)

  func testPixelRowsCountDownFromTheTop() {
    XCTAssertEqual(area.pixelRow(atY: 132), 0)
    XCTAssertEqual(area.pixelRow(atY: 84), 96)
    XCTAssertEqual(area.y(atPixelRow: 96), 84)
  }

  func testPixelColumnsCountFromTheLeft() {
    XCTAssertEqual(area.pixelColumn(atX: 325), 0)
    XCTAssertEqual(area.pixelColumn(atX: 1139), 1628)
    XCTAssertEqual(area.x(atPixelColumn: 1628), 1139)
  }

  func testTheScreencaptureRegionCountsYFromTheTop() {
    XCTAssertEqual(area.screencaptureRegion(primaryHeight: 982), "325,850,862,132")
  }

  // Room for the edge searches around the background, the perch above it, and nothing off the
  // display.
  func testTheAreaAroundADockHoldsTheSearchesAndThePerchOnTheDisplay() {
    let around = CaptureArea.around(
      background: CGRect(x: 373, y: 5, width: 766, height: 79),
      perch: CGRect(x: 1066.85, y: 84, width: 64, height: 80),
      on: CGRect(x: 0, y: 0, width: 1512, height: 982),
      scale: 2
    )

    XCTAssertEqual(around.frame, CGRect(x: 361, y: 0, width: 790, height: 164))
    XCTAssertEqual(around.scale, 2)
  }
}
