import DrowsyDockCore
import XCTest

final class MascotTimelineTests: XCTestCase {
  private let transitions: [MascotAnimation] = [.crossfade, .yawn, .nodOff, .wakeUp]

  func testEveryTransitionLeavesItsFlexiblePhaseALengthAboveZero() {
    for animation in transitions {
      XCTAssertGreaterThan(MascotTimeline.flexiblePhase(of: animation), 0, "\(animation)")
    }
  }

  func testTheLoopEaseOutEndsBeforeEveryTransitionDoes() {
    XCTAssertGreaterThan(MascotTimeline.loopEaseOut, 0)
    for animation in transitions {
      XCTAssertLessThan(
        MascotTimeline.loopEaseOut, animation.duration / .seconds(1), "\(animation)")
    }
  }

  // The yawn moves the head's height only after its settle, so the head must have eased back.
  func testTheLoopEaseOutEndsBeforeTheYawnsSettleDoes() {
    XCTAssertLessThanOrEqual(MascotTimeline.loopEaseOut, MascotTimeline.flexiblePhase(of: .yawn))
  }

  func testTheLoopEaseOutEndsBeforeTheWakeUpStretches() {
    XCTAssertLessThanOrEqual(MascotTimeline.loopEaseOut, MascotTimeline.WakeUp.stretchDelay)
  }

  func testTheWakeUpsBeatsEndBeforeItsFinalBlinkStarts() {
    let wakeUp = MascotTimeline.WakeUp.self
    let finalBlinkStart = wakeUp.snapOpen + MascotTimeline.flexiblePhase(of: .wakeUp)
    let sparkle = wakeUp.Sparkle.self
    let lastSparkleEnd =
      wakeUp.firstSparkle + Double(wakeUp.sparkleCount - 1) * wakeUp.sparkleInterval
      + sparkle.appear + sparkle.hold + sparkle.fade
    let beatEnds = [
      wakeUp.earsUp, wakeUp.pop, wakeUp.headStraighten,
      wakeUp.stretchDelay + 2 * wakeUp.stretch, lastSparkleEnd,
    ]

    for end in beatEnds {
      XCTAssertLessThanOrEqual(end, finalBlinkStart)
    }
    XCTAssertLessThanOrEqual(wakeUp.headStraighten, wakeUp.stretchDelay)
  }

  func testACrossfadeIsAllFlexible() {
    XCTAssertEqual(
      MascotTimeline.flexiblePhase(of: .crossfade),
      MascotAnimation.crossfade.duration / .seconds(1),
      accuracy: 1e-9
    )
  }

  func testTheYawnSettlesThenYawnsAndNodsWithinItsDuration() {
    let yawn = MascotTimeline.YawnAndNod.self
    let phases = [yawn.leanBack, yawn.holdYawn, yawn.straighten, yawn.nodDown, yawn.jerkUp]

    XCTAssertEqual(
      MascotTimeline.flexiblePhase(of: .yawn) + phases.reduce(0, +),
      MascotAnimation.yawn.duration / .seconds(1),
      accuracy: 1e-9
    )
  }

  func testTheNodOffDroopsJerksAndSettlesWithinItsDuration() {
    let nodOff = MascotTimeline.NodOff.self

    XCTAssertEqual(
      nodOff.droop + nodOff.jerk + MascotTimeline.flexiblePhase(of: .nodOff),
      MascotAnimation.nodOff.duration / .seconds(1),
      accuracy: 1e-9
    )
  }

  func testTheWakeUpSnapsOpenHoldsAndBlinksWithinItsDuration() {
    let blink = MascotTimeline.blink

    XCTAssertEqual(
      MascotTimeline.WakeUp.snapOpen + MascotTimeline.flexiblePhase(of: .wakeUp) + blink.close
        + blink.hold + blink.open,
      MascotAnimation.wakeUp.duration / .seconds(1),
      accuracy: 1e-9
    )
  }

  func testASlowBlinkTakesLongerThanABlink() {
    XCTAssertGreaterThan(MascotTimeline.slowBlink.length, MascotTimeline.blink.length)
  }
}
