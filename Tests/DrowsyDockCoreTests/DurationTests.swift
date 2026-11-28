import DrowsyDockCore
import XCTest

final class DurationTests: XCTestCase {
  func testWholeSecondsConvert() {
    XCTAssertEqual(Duration.seconds(3).inSeconds, 3)
  }

  func testFractionsOfASecondConvert() {
    XCTAssertEqual(Duration.milliseconds(2650).inSeconds, 2.65, accuracy: 1e-12)
  }

  func testZeroIsZero() {
    XCTAssertEqual(Duration.zero.inSeconds, 0)
  }
}
