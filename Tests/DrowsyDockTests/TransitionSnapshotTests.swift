import DockOverlayKit
import DrowsyDockCore
import XCTest

@testable import DrowsyDock

// QA section 10 and 9.9: each transition filmed at fixed scene times after the change, and how the
// overlay ends a transition the pointer interrupts. A strip's first frame is the first frame drawn
// after the change, 1/30 s in.
@MainActor
final class TransitionSnapshotTests: XCTestCase {
  private let tolerance = SnapshotTolerance(channel: 2, differingPixels: 4)

  // For a frame compared with a still pose's reference after an animation. SpriteKit caches each
  // rasterized group when it draws it, and a cache drawn while the ears still turned (the first
  // 0.12 s of a wake-up) sits a fraction of a pixel off: edge pixels differ by up to 32, and
  // nothing else does. A wrong pose moves edges by whole pixels, which differ by over 100.
  private let restingPoseTolerance = SnapshotTolerance(channel: 40, differingPixels: 4)

  private let first = 1.0 / 30

  override func setUpWithError() throws {
    try Snapshot.skipUnlessReferenceArchitecture()
  }

  // Compares with a still pose's reference without ever recording over it.
  private func assertFrame(
    _ frame: Bitmap,
    matches pose: String,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let url = Snapshot.referenceDirectory.appendingPathComponent("\(pose).png")
    guard let reference = try? Bitmap(contentsOf: url) else {
      XCTFail("No reference at \(url.path)", file: file, line: line)
      return
    }
    let comparison = SnapshotComparison(
      expected: reference,
      actual: frame,
      channelTolerance: restingPoseTolerance.channel
    )
    XCTAssertTrue(
      comparison.matches(within: restingPoseTolerance),
      "\(message) \(comparison.differingPixels) pixels differ from \(pose)",
      file: file,
      line: line
    )
  }

  // MARK: - One transition at a time

  // QA 10.1: a quick crossfade; the lids sink, the head leans and the ears fold together.
  func testAwakeToDrowsyCrossfades() {
    let film = CatFilm(resting: .awake)
    film.scene.show(.drowsiness(.drowsy), facing: nil)

    Snapshot.assert(
      film.strip(at: [first, 0.15, 0.3, 0.45, 0.6, 0.7]),
      named: "transition-awake-to-drowsy",
      within: tolerance
    )
  }

  // QA 10.2: the cat settles into the yawning pose, then yawns and nods. About 3.4 s.
  func testDrowsyToYawningYawns() {
    let film = CatFilm(resting: .drowsy)
    film.scene.show(.drowsiness(.yawning), facing: nil)

    Snapshot.assert(
      film.strip(at: [first, 0.4, 0.8, 1.2, 1.6, 2.0, 2.4, 2.8, 3.1, 3.4]),
      named: "transition-drowsy-to-yawning",
      within: tolerance
    )
  }

  // QA 10.3: the head droops as the eyes fall shut, jerks back up, and settles; the "z" fades in.
  func testYawningToNoddingOffNodsOff() {
    let film = CatFilm(resting: .yawning)
    film.scene.show(.drowsiness(.noddingOff), facing: nil)

    Snapshot.assert(
      film.strip(at: [first, 0.4, 0.8, 1.3, 1.45, 1.7, 1.95, 2.2]),
      named: "transition-yawning-to-noddingOff",
      within: tolerance
    )
  }

  // QA 10.4: a crossfade into the asleep pose; the bubble and two "z"s fade in.
  func testNoddingOffToAsleepCrossfades() {
    let film = CatFilm(resting: .noddingOff)
    film.advance(by: 2)
    film.scene.show(.drowsiness(.asleep), facing: nil)

    Snapshot.assert(
      film.strip(at: [first, 0.1, 0.2, 0.3, 0.45, 0.6]),
      named: "transition-noddingOff-to-asleep",
      within: tolerance
    )
  }

  // QA 10.5 and 8.7: the eyes snap open, the bubble pops, the cat stretches, three sparkles
  // twinkle, and it ends with a blink in the awake pose.
  func testAsleepToWakingWakesUpAndEndsAwake() {
    let film = CatFilm(resting: .asleep)
    film.advance(by: 2)
    film.scene.show(.waking, facing: nil)

    Snapshot.assert(
      film.strip(at: [first, 0.1, 0.3, 0.5, 0.65, 0.8, 1.0, 1.3, 1.7, 2.6, 2.8]),
      named: "transition-asleep-to-waking",
      within: tolerance
    )
    film.advance(by: 0.5)
    XCTAssertFalse(film.scene.needsAnotherFrame)
    assertFrame(film.frame(), matches: "pose-awake-left")
  }

  // QA 10.6: the yawn plays to its end, then one crossfade straight to asleep, with no nod-off.
  func testChangesDuringAYawnWaitAndCollapseToTheLastOne() {
    let film = CatFilm(resting: .drowsy)
    film.scene.show(.drowsiness(.yawning), facing: nil)
    film.advance(by: 0.3)
    film.scene.show(.drowsiness(.noddingOff), facing: nil)
    film.advance(by: 0.3)
    film.scene.show(.drowsiness(.asleep), facing: nil)

    Snapshot.assert(
      film.strip(at: [0.4, 1.4, 2.6, 2.85, 3.0, 3.15, 3.3, 3.45]),
      named: "transition-yawn-then-asleep",
      within: tolerance
    )
  }

  // QA 10.10: Charging during the yawn stops it and plays the wake-up at once.
  func testChargingDuringTheYawnPlaysTheWakeUpAtOnce() {
    let film = CatFilm(resting: .drowsy)
    film.scene.show(.drowsiness(.yawning), facing: nil)
    film.advance(by: 0.4)
    film.scene.show(.waking, facing: nil)

    Snapshot.assert(
      film.strip(at: [first, 0.1, 0.3, 0.6, 1.0, 1.5, 2.8]),
      named: "transition-yawn-interrupted-by-waking",
      within: tolerance
    )
  }

  // QA 10.10: Charging during the nod-off stops it and plays the wake-up at once.
  func testChargingDuringTheNodOffPlaysTheWakeUpAtOnce() {
    let film = CatFilm(resting: .yawning)
    film.scene.show(.drowsiness(.noddingOff), facing: nil)
    film.advance(by: 0.4)
    film.scene.show(.waking, facing: nil)

    Snapshot.assert(
      film.strip(at: [first, 0.1, 0.3, 0.6, 1.0, 1.5, 2.8]),
      named: "transition-nodOff-interrupted-by-waking",
      within: tolerance
    )
  }

  // MARK: - Charging during a transition (job 003 H3)

  // Counts the blue pixels: the "z"s and the snore bubble are the only blue parts of the cat, and
  // the backdrop is bluer than red by only 16.
  private func zAndBubblePixels(in frame: Bitmap) -> Int {
    stride(from: 0, to: frame.pixels.count, by: 4).filter { start in
      Int(frame.pixels[start + 2]) - Int(frame.pixels[start]) > 25
    }.count
  }

  // QA 10.10: Charging stops the transition where it is. A "z" or the bubble that the interrupted
  // transition hadn't faded in yet must not pop in before the wake-up fades it.
  func testChargingMidTransitionShowsNoZOrBubbleThatWasntThere() {
    let cases: [(from: DrowsinessState, to: DrowsinessState)] = [
      (.yawning, .noddingOff), (.noddingOff, .asleep),
    ]
    for (from, to) in cases {
      let film = CatFilm(resting: from)
      film.advance(by: 2)
      film.scene.show(.drowsiness(to), facing: nil)
      film.advance(by: 0.1)
      let before = zAndBubblePixels(in: film.frame())

      film.scene.show(.waking, facing: nil)
      film.advance(by: first)

      XCTAssertLessThanOrEqual(zAndBubblePixels(in: film.frame()), before, "\(from) to \(to)")
    }
  }

  // MARK: - Leaving a loop

  // QA 10.11: nothing jumps in the first frame. The "z"s in the air fade where they are, and the
  // bubble and body ease back while the crossfade carries the face to awake.
  func testLeavingTheSnoreForAwakeEasesTheLoopOut() {
    let film = CatFilm(resting: .asleep)
    film.advance(by: 2)
    film.scene.show(.drowsiness(.awake), facing: nil)

    Snapshot.assert(
      film.strip(at: [first, 0.1, 0.2, 0.3, 0.45, 0.6]),
      named: "transition-snore-to-awake",
      within: tolerance
    )
  }

  // QA 10.11: the same from the floating "z"s and the bobbing head.
  func testLeavingTheFloatingZsForAwakeEasesTheLoopOut() {
    let film = CatFilm(resting: .noddingOff)
    film.advance(by: 2)
    film.scene.show(.drowsiness(.awake), facing: nil)

    Snapshot.assert(
      film.strip(at: [first, 0.1, 0.2, 0.3, 0.45, 0.6]),
      named: "transition-floating-zs-to-awake",
      within: tolerance
    )
  }

  // QA 10.11 (a) and 8.6: the head droops from wherever the breath left it, and the body and
  // bubble ease back.
  func testLeavingTheSnoreForNoddingOffDroopsFromWhereTheHeadIs() {
    let film = CatFilm(resting: .asleep)
    film.advance(by: 2)
    film.scene.show(.drowsiness(.noddingOff), facing: nil)

    Snapshot.assert(
      film.strip(at: [first, 0.1, 0.25, 0.6, 1.3, 1.6, 2.2]),
      named: "transition-snore-to-noddingOff",
      within: tolerance
    )
  }

  // QA 10.11 (b): the bubble pops from its current size and the body is back at rest before the
  // stretch.
  func testLeavingTheSnoreForWakingPopsTheBubbleFromItsSize() {
    let film = CatFilm(resting: .asleep)
    film.advance(by: 2)
    film.scene.show(.waking, facing: nil)

    Snapshot.assert(
      film.strip(at: [first, 0.1, 0.2, 0.3, 0.45, 0.6]),
      named: "transition-snore-to-waking",
      within: tolerance
    )
  }

  // QA 10.11 (b), from the floating "z"s.
  func testLeavingTheFloatingZsForWakingDoesNotJump() {
    let film = CatFilm(resting: .noddingOff)
    film.advance(by: 2)
    film.scene.show(.waking, facing: nil)

    Snapshot.assert(
      film.strip(at: [first, 0.1, 0.2, 0.3, 0.45, 0.6]),
      named: "transition-floating-zs-to-waking",
      within: tolerance
    )
  }

  // QA 9.9: a change in the middle of a yawn stops it at once, and a crossfade carries the cat to
  // the awake pose.
  func testAChangeInTheMiddleOfAnAmbientYawnStopsItAndCrossfades() {
    let film = CatFilm(resting: .yawning)
    film.playNextGesture(in: self)
    film.advance(by: 1)
    film.scene.show(.drowsiness(.awake), facing: nil)

    Snapshot.assert(
      film.strip(at: [first, 0.15, 0.3, 0.45, 0.6]),
      named: "transition-ambient-yawn-to-awake",
      within: tolerance
    )
  }

  // MARK: - The pointer and the hidden Dock

  private func overlay(clock: TestClock) -> MascotOverlay {
    let overlay = MascotOverlay(
      catScene: MascotScene(clock: clock, generator: SeededGenerator(seed: 2026))
    )
    addTeardownBlock { overlay.show(nil) }
    KeepAlive.keep(overlay)
    return overlay
  }

  private let dock = DockFixture.bottom

  private var shown: OverlayPresentation {
    .shown(dock.perch(for: MascotOverlay.spriteSize), on: dock)
  }

  private var fadedOut: OverlayPresentation {
    .fadedOut(dock.perch(for: MascotOverlay.spriteSize), on: dock)
  }

  // QA 10.7: hovering in the middle of the crossfade fades the cat out; it comes back in the
  // asleep pose without replaying the crossfade.
  func testHoveringDuringTheCrossfadeBringsTheCatBackAsleep() {
    let clock = TestClock()
    let overlay = overlay(clock: clock)
    overlay.show(.drowsiness(.awake))
    overlay.present(shown)
    let cat = OffscreenRenderer(scene: overlay.catScene)
    overlay.show(.drowsiness(.asleep))
    cat.advance(by: 0.3)

    overlay.present(fadedOut)
    cat.advance(by: 0.5)
    XCTAssertEqual(overlay.catWindow.visibility, .fadedOut)
    overlay.present(shown)
    cat.advance(by: 1.0 / 60)

    XCTAssertEqual(overlay.catWindow.visibility, .shown)
    assertFrame(cat.render(over: CatFilm.backdrop), matches: "pose-asleep-left")
  }

  // QA 10.8: with the Dock hidden, a change switches at once, so the cat appears in the new pose
  // without replaying its animation.
  func testAChangeWhileTheDockIsHiddenShowsTheNewPoseAtOnce() {
    let clock = TestClock()
    let overlay = overlay(clock: clock)
    overlay.show(.drowsiness(.drowsy))
    overlay.present(.hidden)
    let cat = OffscreenRenderer(scene: overlay.catScene)
    overlay.show(.drowsiness(.yawning))
    cat.advance(by: 1)

    overlay.present(shown)
    cat.advance(by: 1.0 / 60)

    XCTAssertFalse(overlay.catScene.needsAnotherFrame)
    assertFrame(cat.render(over: CatFilm.backdrop), matches: "pose-yawning-left")
  }

  // QA 10.9: hovering as each transition starts brings the cat back in the new state's pose, at
  // its normal width, with no leftover "z"s or bubble. Then the next ambient behaviour starts: a
  // loop at once, or a gesture scheduled while the cat stays still. Waking has none of its own;
  // it starts once waking ends and the cat is awake, as BatteryMonitor reports after 3 s.
  func testHoveringAsEachTransitionStartsBringsTheCatBackInTheNewPose() {
    let cases: [(from: MascotMood, to: MascotMood, pose: String, loops: Bool)] = [
      (.drowsiness(.drowsy), .drowsiness(.yawning), "pose-yawning-left", false),
      (.drowsiness(.yawning), .drowsiness(.noddingOff), "pose-noddingOff-left", true),
      (.drowsiness(.noddingOff), .drowsiness(.asleep), "pose-asleep-left", true),
      (.drowsiness(.asleep), .waking, "pose-awake-left", false),
    ]
    for (from, to, pose, loops) in cases {
      let clock = TestClock()
      let overlay = overlay(clock: clock)
      overlay.show(from)
      overlay.present(shown)
      let cat = OffscreenRenderer(scene: overlay.catScene)
      cat.advance(by: 1)
      overlay.show(to)
      cat.advance(by: 0.1)

      overlay.present(fadedOut)
      cat.advance(by: 1)
      overlay.present(shown)
      cat.advance(by: 1.0 / 60)

      assertFrame(cat.render(over: CatFilm.backdrop), matches: pose, "\(from) to \(to):")
      if to == .waking {
        overlay.show(.drowsiness(.awake))
      }
      if loops {
        XCTAssertTrue(overlay.catScene.needsAnotherFrame, "\(from) to \(to)")
      } else {
        waitUntil("the next gesture is scheduled after \(from) to \(to)") {
          clock.sleeperCount == 1
        }
        XCTAssertFalse(overlay.catScene.needsAnotherFrame, "\(from) to \(to)")
      }
    }
  }
}
