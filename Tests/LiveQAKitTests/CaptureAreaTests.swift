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

  // screencapture -R counts y down from the top of the primary display.
  func testTheScreencaptureRegionCountsYFromTheTop() {
    XCTAssertEqual(area.screencaptureRegion(primaryHeight: 982), "325,850,862,132")
  }
}
