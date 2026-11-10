import DrowsyDockCore
import XCTest

final class MascotPoseTests: XCTestCase {
  private let sleepierOrder = DrowsinessState.allCases

  // MARK: - The two ends

  func testAnAwakeCatHasOpenEyesAndNothingElse() {
    let pose = MascotPose(for: .awake)

    XCTAssertEqual(pose.eyelidOpenness, 1)
    XCTAssertEqual(pose.headTiltDegrees, 0)
    XCTAssertEqual(pose.zCount, 0)
    XCTAssertFalse(pose.showsSnoreBubble)
    XCTAssertEqual(pose.veilOpacity, 0)
  }

  func testAnAsleepCatHasClosedEyesASnoreBubbleZsAndAVeil() {
    let pose = MascotPose(for: .asleep)

    XCTAssertEqual(pose.eyelidOpenness, 0)
    XCTAssertGreaterThan(pose.zCount, 0)
    XCTAssertTrue(pose.showsSnoreBubble)
    XCTAssertGreaterThan(pose.veilOpacity, 0)
  }

  // MARK: - Getting sleepier

  func testEachSleepierStateHasHeavierEyelids() {
    for (state, sleepier) in zip(sleepierOrder, sleepierOrder.dropFirst()) {
      XCTAssertLessThan(
        MascotPose(for: sleepier).eyelidOpenness,
        MascotPose(for: state).eyelidOpenness,
        "\(sleepier) after \(state)"
      )
    }
  }

  func testEachSleepierStateTiltsTheHeadFurther() {
    for (state, sleepier) in zip(sleepierOrder, sleepierOrder.dropFirst()) {
      XCTAssertGreaterThan(
        MascotPose(for: sleepier).headTiltDegrees,
        MascotPose(for: state).headTiltDegrees,
        "\(sleepier) after \(state)"
      )
    }
  }

  func testEachSleepierStateDroopsTheEarsAtLeastAsMuch() {
    for (state, sleepier) in zip(sleepierOrder, sleepierOrder.dropFirst()) {
      XCTAssertGreaterThanOrEqual(
        MascotPose(for: sleepier).earDroop,
        MascotPose(for: state).earDroop,
        "\(sleepier) after \(state)"
      )
    }
  }

  func testOnlyNoddingOffAndAsleepShowZsAndAsleepShowsMore() {
    XCTAssertEqual(MascotPose(for: .awake).zCount, 0)
    XCTAssertEqual(MascotPose(for: .drowsy).zCount, 0)
    XCTAssertEqual(MascotPose(for: .yawning).zCount, 0)
    XCTAssertGreaterThan(MascotPose(for: .noddingOff).zCount, 0)
    XCTAssertGreaterThan(MascotPose(for: .asleep).zCount, MascotPose(for: .noddingOff).zCount)
  }

  func testOnlyAsleepShowsTheSnoreBubbleAndTheVeil() {
    for state in sleepierOrder where state != .asleep {
      XCTAssertFalse(MascotPose(for: state).showsSnoreBubble, "\(state)")
      XCTAssertEqual(MascotPose(for: state).veilOpacity, 0, "\(state)")
    }
  }

  func testTheVeilDimsTheDockWithoutHidingIt() {
    XCTAssertLessThanOrEqual(MascotPose(for: .asleep).veilOpacity, 0.5)
  }

  func testEveryStateHasItsOwnPose() {
    let poses = sleepierOrder.map { MascotPose(for: $0) }

    for (index, pose) in poses.enumerated() {
      XCTAssertFalse(poses[(index + 1)...].contains(pose), "\(sleepierOrder[index])")
    }
  }

  func testEveryPoseStaysInRange() {
    for state in sleepierOrder {
      let pose = MascotPose(for: state)
      XCTAssertTrue((0...1).contains(pose.eyelidOpenness), "\(state)")
      XCTAssertTrue((0...1).contains(pose.earDroop), "\(state)")
      XCTAssertTrue((0...1).contains(pose.veilOpacity), "\(state)")
    }
  }
}
