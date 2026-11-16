import Foundation
import LiveQAKit
import XCTest

final class LumaImageTests: XCTestCase {
  private let image = LumaImage(width: 3, height: 2, values: [10, 20, 30, 40, 50, 60])

  func testAProfileDownAveragesEachRowOverTheColumns() {
    XCTAssertEqual(image.profileDown(columns: 1...2, rows: 0...1), [25, 55])
  }

  func testAProfileAcrossAveragesEachColumnOverTheRows() {
    XCTAssertEqual(image.profileAcross(rows: 0...1, columns: 0...2), [25, 35, 45])
  }

  func testTheRatioIsTheShareOfTheOtherImagesBrightness() {
    let bare = LumaImage(width: 3, height: 1, values: [100, 50, 4])
    let veiled = LumaImage(width: 3, height: 1, values: [72, 36, 2])

    XCTAssertEqual(veiled.ratio(to: bare, floor: 8).values, [0.72, 0.72, 1])
  }

  func testCountsThePixelsThatDifferByMoreThanTheThreshold() {
    let other = LumaImage(width: 3, height: 2, values: [10, 45, 30, 40, 50, 100])

    XCTAssertEqual(image.countOfPixels(differingFrom: other, by: 24), 2)
    XCTAssertEqual(image.countOfPixels(differingFrom: image, by: 0), 0)
  }

  func testSubtractingGivesEachPixelsChange() {
    let other = LumaImage(width: 3, height: 2, values: [10, 10, 10, 10, 10, 10])

    XCTAssertEqual(image.subtracting(other).values, [0, 10, 20, 30, 40, 50])
  }

  func testAScreenshotIsReadAsTheMeanOfItsChannels() throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/rim-right-end.png")

    let screenshot = try LumaImage(contentsOf: fixture)

    XCTAssertEqual(screenshot.width, 80)
    XCTAssertEqual(screenshot.height, 60)
    XCTAssertEqual(screenshot[29, 28], 9, accuracy: 1)
  }

  func testAMissingScreenshotThrows() {
    XCTAssertThrowsError(
      try LumaImage(contentsOf: URL(fileURLWithPath: "/nonexistent/qa-helper-test.png"))
    )
  }
}
