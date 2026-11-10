import LiveQAKit
import XCTest

final class ProfileTests: XCTestCase {
  func testTheStrongestStepIsTheFirstSampleAfterTheLargestJump() {
    XCTAssertEqual(Profile.strongestStep(in: [10, 11, 12, 40, 41, 40]), 3)
  }

  func testADownwardStepCountsAsMuchAsAnUpwardOne() {
    XCTAssertEqual(Profile.strongestStep(in: [90, 88, 30, 29, 35]), 2)
  }

  func testAFlatProfileHasNoStepAndNoLine() {
    XCTAssertNil(Profile.strongestStep(in: [4, 4, 4, 4, 4, 4]))
    XCTAssertNil(Profile.thinLine(in: [4, 4, 4, 4, 4, 4]))
  }

  func testAProfileTooShortHasNoStep() {
    XCTAssertNil(Profile.strongestStep(in: [5]))
  }

  func testAThinBrightLineIsFound() {
    XCTAssertEqual(Profile.thinLine(in: [6, 6, 7, 88, 30, 28, 25, 23]), 3)
  }

  func testAThinDarkLineIsFound() {
    XCTAssertEqual(Profile.thinLine(in: [29, 29, 29, 29, 9, 31, 31, 31]), 4)
  }

  // A step is no line: the samples two either side differ, so the middle stands out half as much
  // as a line of the same height.
  func testALineOutranksAStepOfTheSameHeight() {
    XCTAssertEqual(
      Profile.thinLine(in: [0, 0, 0, 0, 0, 50, 50, 50, 50, 50, 50, 100, 50, 50, 50]), 11)
  }

  func testAProfileTooShortHasNoLine() {
    XCTAssertNil(Profile.thinLine(in: [1, 2, 9, 2]))
  }

  func testTheLastIndexAboveAThresholdCountsDarkeningToo() {
    XCTAssertEqual(Profile.lastIndex(in: [0, 30, -25, 3, 1], above: 20), 2)
    XCTAssertNil(Profile.lastIndex(in: [0, 3, -5], above: 20))
  }
}
