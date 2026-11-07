import SleepyBatteryCore
import XCTest

final class ThresholdsTests: XCTestCase {
  func testDefaultThresholdsMapEveryBoundaryToTheSpecState() {
    let cases: [(percentage: Int, expected: DrowsinessState)] = [
      (100, .awake),
      (50, .awake),
      (49, .drowsy),
      (30, .drowsy),
      (29, .yawning),
      (20, .yawning),
      (19, .noddingOff),
      (10, .noddingOff),
      (9, .asleep),
      (0, .asleep),
    ]

    for (percentage, expected) in cases {
      XCTAssertEqual(
        DrowsinessState(percentage: percentage, thresholds: .default),
        expected,
        "\(percentage)%"
      )
    }
  }

  func testAcceptsStrictlyDescendingValuesInsideOneToNinetyNine() {
    XCTAssertNotNil(Thresholds(drowsy: 99, yawning: 3, noddingOff: 2, asleep: 1))
  }

  func testRejectsEqualNeighbours() {
    XCTAssertNil(Thresholds(drowsy: 50, yawning: 50, noddingOff: 20, asleep: 10))
  }

  func testRejectsAscendingNeighbours() {
    XCTAssertNil(Thresholds(drowsy: 50, yawning: 30, noddingOff: 10, asleep: 20))
  }

  func testRejectsValuesAboveNinetyNine() {
    XCTAssertNil(Thresholds(drowsy: 100, yawning: 30, noddingOff: 20, asleep: 10))
  }

  func testRejectsValuesBelowOne() {
    XCTAssertNil(Thresholds(drowsy: 50, yawning: 30, noddingOff: 20, asleep: 0))
  }

  func testStatesOrderFromAwakeToAsleep() {
    XCTAssertEqual(
      DrowsinessState.allCases.sorted(),
      [.awake, .drowsy, .yawning, .noddingOff, .asleep]
    )
  }
}
