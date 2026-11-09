import DrowsyDockCore
import XCTest

final class AnimationDirectorTests: XCTestCase {
  private let awake = MascotMood.drowsiness(.awake)
  private let drowsy = MascotMood.drowsiness(.drowsy)
  private let yawning = MascotMood.drowsiness(.yawning)
  private let noddingOff = MascotMood.drowsiness(.noddingOff)
  private let asleep = MascotMood.drowsiness(.asleep)
  private let waking = MascotMood.waking

  private var everyMood: [MascotMood] { [awake, drowsy, yawning, noddingOff, asleep, waking] }

  private func transition(_ from: MascotMood?, _ to: MascotMood) -> AnimationDirector.Transition {
    AnimationDirector.transition(from: from, to: to)
  }

  // MARK: - The (from, to) table

  func testEveryChangeIntoYawningPlaysTheYawn() {
    for from in [awake, drowsy, noddingOff, asleep, waking] {
      XCTAssertEqual(transition(from, yawning), .play(.yawn), "from \(from)")
    }
  }

  func testEveryChangeIntoNoddingOffPlaysTheNodOff() {
    for from in [awake, drowsy, yawning, asleep, waking] {
      XCTAssertEqual(transition(from, noddingOff), .play(.nodOff), "from \(from)")
    }
  }

  func testEveryChangeIntoWakingPlaysTheWakeUp() {
    for from in [awake, drowsy, yawning, noddingOff, asleep] {
      XCTAssertEqual(transition(from, waking), .play(.wakeUp), "from \(from)")
    }
  }

  func testTheEndOfTheWakeUpNeedsNoAnimationBecauseItEndsAwake() {
    XCTAssertEqual(transition(waking, awake), .cut)
  }

  func testEveryOtherChangeCrossfades() {
    let crossfades: [(MascotMood, MascotMood)] = [
      (drowsy, awake), (yawning, awake), (noddingOff, awake), (asleep, awake),
      (awake, drowsy), (yawning, drowsy), (noddingOff, drowsy), (asleep, drowsy), (waking, drowsy),
      (awake, asleep), (drowsy, asleep), (yawning, asleep), (noddingOff, asleep), (waking, asleep),
    ]
    for (from, to) in crossfades {
      XCTAssertEqual(transition(from, to), .play(.crossfade), "\(from) to \(to)")
    }
  }

  func testStayingInTheSameMoodDoesNothing() {
    for mood in everyMood {
      XCTAssertEqual(transition(mood, mood), .none, "\(mood)")
    }
  }

  func testTheFirstMoodShowsAtOnce() {
    for mood in everyMood {
      XCTAssertEqual(transition(nil, mood), .cut, "\(mood)")
    }
  }

  func testQuietHoursShowEveryChangeAtOnce() {
    for from in everyMood {
      for to in everyMood where to != from {
        XCTAssertEqual(
          AnimationDirector.transition(from: from, to: to, quietHours: true),
          .cut,
          "\(from) to \(to)"
        )
      }
    }
  }

  func testInQuietHoursRequestingTheShownMoodStillDoesNothing() {
    for mood in everyMood {
      XCTAssertEqual(
        AnimationDirector.transition(from: mood, to: mood, quietHours: true),
        .none,
        "\(mood)"
      )
    }
  }

  // MARK: - Playing and queueing

  func testTheFirstRequestShowsTheMoodAtOnce() {
    var director = AnimationDirector()

    XCTAssertEqual(director.request(drowsy), .init(animation: nil, target: drowsy))
    XCTAssertFalse(director.isAnimating)
    XCTAssertEqual(director.shown, drowsy)
  }

  func testAfterAFirstCutTheNextChangeAnimates() {
    var director = AnimationDirector()
    _ = director.request(drowsy)

    XCTAssertEqual(director.request(yawning), .init(animation: .yawn, target: yawning))
  }

  func testARequestWhileIdlePlaysItsAnimation() {
    var director = AnimationDirector(showing: drowsy)

    XCTAssertEqual(director.request(yawning), .init(animation: .yawn, target: yawning))
    XCTAssertTrue(director.isAnimating)
  }

  func testARequestForTheShownMoodDoesNothing() {
    var director = AnimationDirector(showing: drowsy)

    XCTAssertNil(director.request(drowsy))
    XCTAssertFalse(director.isAnimating)
  }

  func testARequestDuringAnAnimationWaitsForItToFinish() {
    var director = AnimationDirector(showing: drowsy)
    _ = director.request(yawning)

    XCTAssertNil(director.request(noddingOff))
    XCTAssertEqual(director.finishAnimation(), .init(animation: .nodOff, target: noddingOff))
  }

  func testBackToBackRequestsCollapseToTheLastOne() {
    var director = AnimationDirector(showing: awake)
    _ = director.request(drowsy)

    _ = director.request(yawning)
    _ = director.request(noddingOff)
    _ = director.request(asleep)

    XCTAssertEqual(director.finishAnimation(), .init(animation: .crossfade, target: asleep))
    XCTAssertNil(director.finishAnimation())
    XCTAssertEqual(director.shown, asleep)
  }

  func testAQueuedRequestBackToTheAnimatedMoodPlaysNothingMore() {
    var director = AnimationDirector(showing: awake)
    _ = director.request(drowsy)
    _ = director.request(yawning)

    _ = director.request(drowsy)

    XCTAssertNil(director.finishAnimation())
    XCTAssertFalse(director.isAnimating)
    XCTAssertEqual(director.shown, drowsy)
  }

  func testAMoodThatWaitedAndPlayedIsNotPlayedAgain() {
    var director = AnimationDirector(showing: drowsy)
    _ = director.request(yawning)
    _ = director.request(noddingOff)
    _ = director.finishAnimation()
    _ = director.finishAnimation()

    _ = director.request(asleep)

    XCTAssertNil(director.finishAnimation())
    XCTAssertEqual(director.shown, asleep)
  }

  func testFinishingWithNothingQueuedLeavesTheDirectorIdle() {
    var director = AnimationDirector(showing: drowsy)
    _ = director.request(yawning)

    XCTAssertNil(director.finishAnimation())

    XCTAssertFalse(director.isAnimating)
    XCTAssertEqual(director.request(asleep), .init(animation: .crossfade, target: asleep))
  }

  func testTheTargetIsTheNewestRequest() {
    var director = AnimationDirector(showing: awake)
    _ = director.request(drowsy)
    _ = director.request(asleep)

    XCTAssertEqual(director.target, asleep)
  }

  func testWithNothingWaitingTheTargetIsTheShownMood() {
    var director = AnimationDirector(showing: awake)
    _ = director.request(drowsy)

    XCTAssertEqual(director.target, drowsy)
  }

  func testAJumpShowsTheMoodAtOnceAndDropsTheQueue() {
    var director = AnimationDirector(showing: awake)
    _ = director.request(drowsy)
    _ = director.request(yawning)

    XCTAssertEqual(director.jump(to: asleep), .init(animation: nil, target: asleep))

    XCTAssertFalse(director.isAnimating)
    XCTAssertNil(director.finishAnimation())
    XCTAssertEqual(director.shown, asleep)
  }

  func testQuietHoursShowAQueuedRequestAtOnceToo() {
    var director = AnimationDirector(showing: awake)
    _ = director.request(drowsy)
    _ = director.request(asleep)

    XCTAssertEqual(
      director.finishAnimation(quietHours: true),
      .init(animation: nil, target: asleep)
    )
  }

  func testThePluggedInSequencePlaysTheWakeUpThenSettlesAwake() {
    var director = AnimationDirector(showing: asleep)

    XCTAssertEqual(director.request(waking), .init(animation: .wakeUp, target: waking))
    XCTAssertNil(director.request(awake))
    XCTAssertEqual(director.finishAnimation(), .init(animation: nil, target: awake))
  }

  // MARK: - Plugging in during another transition

  private func steps(
    from start: MascotMood,
    requests: [MascotMood]
  ) -> (steps: [AnimationDirector.Step], director: AnimationDirector) {
    var director = AnimationDirector(showing: start)
    var steps: [AnimationDirector.Step] = []
    for mood in requests {
      if let step = director.request(mood) {
        steps.append(step)
      }
    }
    while director.isAnimating, let next = director.finishAnimation() {
      steps.append(next)
    }
    if director.isAnimating {
      _ = director.finishAnimation()
    }
    return (steps, director)
  }

  func testChargingDuringAYawnStillPlaysTheWakeUpAndEndsAwake() {
    // Charging right after the yawn starts: waking and its end both arrive before the yawn would end.
    XCTAssertGreaterThan(MascotAnimation.yawn.duration, DrowsinessTracker.wakingDuration)
    let run = steps(from: drowsy, requests: [yawning, waking, awake])

    XCTAssertTrue(run.steps.contains { $0.animation == .wakeUp }, "\(run.steps)")
    XCTAssertEqual(run.director.shown, awake)
    XCTAssertFalse(run.director.isAnimating)
  }

  func testChargingDuringEveryOtherTransitionStillPlaysTheWakeUp() {
    for (from, to) in [(yawning, noddingOff), (noddingOff, asleep), (asleep, yawning)] {
      let run = steps(from: from, requests: [to, waking, awake])

      XCTAssertTrue(run.steps.contains { $0.animation == .wakeUp }, "\(from) to \(to)")
      XCTAssertEqual(run.director.shown, awake, "\(from) to \(to)")
    }
  }

  func testChargingDuringATransitionStartsTheWakeUpAtOnce() {
    var director = AnimationDirector(showing: drowsy)
    _ = director.request(yawning)

    XCTAssertEqual(director.request(waking), .init(animation: .wakeUp, target: waking))
    XCTAssertTrue(director.isAnimating)
  }

  func testChargingAgainDuringTheWakeUpDoesNotRestartIt() {
    var director = AnimationDirector(showing: asleep)
    _ = director.request(waking)

    XCTAssertNil(director.request(waking))
  }

  func testChargingAgainDuringTheWakeUpLetsItFinishBeforeAwake() {
    var director = AnimationDirector(showing: asleep)
    _ = director.request(waking)
    _ = director.request(waking)

    XCTAssertNil(director.request(awake))
    XCTAssertTrue(director.isAnimating)
    XCTAssertEqual(director.finishAnimation(), .init(animation: nil, target: awake))
  }

  func testTheWakeUpDropsAChangeThatWasWaiting() {
    var director = AnimationDirector(showing: drowsy)
    _ = director.request(yawning)
    _ = director.request(noddingOff)

    _ = director.request(waking)

    XCTAssertNil(director.finishAnimation())
    XCTAssertEqual(director.shown, waking)
  }

  func testChargingDuringATransitionInQuietHoursCutsToTheWakeUpsEnd() {
    var director = AnimationDirector(showing: drowsy)
    _ = director.request(yawning)

    XCTAssertEqual(
      director.request(waking, quietHours: true),
      .init(animation: nil, target: waking)
    )
    XCTAssertFalse(director.isAnimating)
  }

  // MARK: - Durations

  func testTheWakeUpTakesAtMostThreeSeconds() {
    XCTAssertLessThanOrEqual(MascotAnimation.wakeUp.duration, .seconds(3))
  }

  func testTheWakeUpFitsInTheWakingPhase() {
    XCTAssertLessThanOrEqual(MascotAnimation.wakeUp.duration, DrowsinessTracker.wakingDuration)
  }

  func testACrossfadeIsQuickerThanEveryOneShot() {
    for animation in [MascotAnimation.yawn, .nodOff, .wakeUp] {
      XCTAssertGreaterThan(animation.duration, MascotAnimation.crossfade.duration, "\(animation)")
    }
    XCTAssertGreaterThan(MascotAnimation.crossfade.duration, .zero)
  }
}
