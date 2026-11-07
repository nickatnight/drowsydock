import DrowsyDockCore
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

  func testRejectsEqualOrReversedValuesInEveryAdjacentPair() {
    let invalid: [(name: String, values: [Int])] = [
      ("drowsy == yawning", [50, 50, 20, 10]),
      ("drowsy < yawning", [30, 50, 20, 10]),
      ("yawning == noddingOff", [50, 30, 30, 10]),
      ("yawning < noddingOff", [50, 20, 30, 10]),
      ("noddingOff == asleep", [50, 30, 20, 20]),
      ("noddingOff < asleep", [50, 30, 10, 20]),
    ]

    for (name, values) in invalid {
      XCTAssertNil(
        Thresholds(
          drowsyBelow: values[0],
          yawningBelow: values[1],
          noddingOffBelow: values[2],
          asleepBelow: values[3]
        ),
        name
      )
    }
  }

  func testRejectsValuesOutsideOneToNinetyNine() {
    let invalid: [(name: String, values: [Int])] = [
      ("drowsy 100", [100, 30, 20, 10]),
      ("asleep 0", [50, 30, 20, 0]),
      ("asleep -5", [50, 30, 20, -5]),
    ]

    for (name, values) in invalid {
      XCTAssertNil(
        Thresholds(
          drowsyBelow: values[0],
          yawningBelow: values[1],
          noddingOffBelow: values[2],
          asleepBelow: values[3]
        ),
        name
      )
    }
  }

  func testStatesOrderFromAwakeToAsleep() {
    XCTAssertEqual(
      DrowsinessState.allCases.sorted(),
      [.awake, .drowsy, .yawning, .noddingOff, .asleep]
    )
  }
}
