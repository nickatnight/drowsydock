import DrowsyDockCore
import XCTest

final class MascotTimelineTests: XCTestCase {
  private let transitions: [MascotAnimation] = [.crossfade, .yawn, .nodOff, .wakeUp]

  func testEveryTransitionLeavesItsFlexiblePhaseALengthAboveZero() {
    for animation in transitions {
      XCTAssertGreaterThan(MascotTimeline.flexiblePhase(of: animation), 0, "\(animation)")
    }
  }

  // The parts a loop moves ease back while the transition that interrupted it plays, so they
  // must have settled before the shortest transition ends and the view may pause.
  func testTheLoopEaseOutEndsBeforeEveryTransitionDoes() {
    for animation in transitions {
      XCTAssertGreaterThan(MascotTimeline.loopEaseOut, 0, "\(animation)")
      XCTAssertLessThan(MascotTimeline.loopEaseOut, animation.duration.inSeconds, "\(animation)")
    }
  }

  func testACrossfadeIsAllFlexible() {
    XCTAssertEqual(
      MascotTimeline.flexiblePhase(of: .crossfade),
      MascotAnimation.crossfade.duration.inSeconds,
      accuracy: 1e-9
    )
  }

  func testTheYawnSettlesThenYawnsAndNodsWithinItsDuration() {
    let yawn = MascotTimeline.YawnAndNod.self
    let phases = [yawn.leanBack, yawn.holdYawn, yawn.straighten, yawn.nodDown, yawn.jerkUp]

    XCTAssertEqual(
      MascotTimeline.flexiblePhase(of: .yawn) + phases.reduce(0, +),
      MascotAnimation.yawn.duration.inSeconds,
      accuracy: 1e-9
    )
  }

  func testTheNodOffDroopsJerksAndSettlesWithinItsDuration() {
    let nodOff = MascotTimeline.NodOff.self

    XCTAssertEqual(
      nodOff.droop + nodOff.jerk + MascotTimeline.flexiblePhase(of: .nodOff),
      MascotAnimation.nodOff.duration.inSeconds,
      accuracy: 1e-9
    )
  }

  func testTheWakeUpSnapsOpenHoldsAndBlinksWithinItsDuration() {
    let blink = MascotTimeline.blink

    XCTAssertEqual(
      MascotTimeline.WakeUp.snapOpen + MascotTimeline.flexiblePhase(of: .wakeUp) + blink.close
        + blink.hold + blink.open,
      MascotAnimation.wakeUp.duration.inSeconds,
      accuracy: 1e-9
    )
  }

  func testASlowBlinkTakesLongerThanABlink() {
    XCTAssertGreaterThan(MascotTimeline.slowBlink.length, MascotTimeline.blink.length)
  }
}
