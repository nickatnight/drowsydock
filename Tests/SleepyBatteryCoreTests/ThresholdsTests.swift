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
    XCTAssertNotNil(
      Thresholds(drowsyBelow: 99, yawningBelow: 3, noddingOffBelow: 2, asleepBelow: 1))
  }

  func testRejectsEqualNeighbours() {
    XCTAssertNil(
      Thresholds(drowsyBelow: 50, yawningBelow: 50, noddingOffBelow: 20, asleepBelow: 10))
  }

  func testRejectsAscendingNeighbours() {
    XCTAssertNil(
      Thresholds(drowsyBelow: 50, yawningBelow: 30, noddingOffBelow: 10, asleepBelow: 20))
  }

  func testRejectsValuesAboveNinetyNine() {
    XCTAssertNil(
      Thresholds(drowsyBelow: 100, yawningBelow: 30, noddingOffBelow: 20, asleepBelow: 10))
  }

  func testRejectsValuesBelowOne() {
    XCTAssertNil(Thresholds(drowsyBelow: 50, yawningBelow: 30, noddingOffBelow: 20, asleepBelow: 0))
  }

  func testStatesOrderFromAwakeToAsleep() {
    XCTAssertEqual(
      DrowsinessState.allCases.sorted(),
      [.awake, .drowsy, .yawning, .noddingOff, .asleep]
    )
  }
}
