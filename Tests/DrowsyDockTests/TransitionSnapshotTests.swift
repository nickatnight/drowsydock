import DockOverlayKit
import DrowsyDockCore
import XCTest

@testable import DrowsyDock

@MainActor
final class TransitionSnapshotTests: XCTestCase {
  private let tolerance = SnapshotTolerance(channel: 2, differingPixels: 4)

  private let restingPoseTolerance = SnapshotTolerance(channel: 40, differingPixels: 4)

  private let first = 1.0 / 30

  override func setUpWithError() throws {
    try Snapshot.skipUnlessReferenceArchitecture()
  }

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

  func testAwakeToDrowsyCrossfades() {
    let film = CatFilm(resting: .awake)
    film.scene.show(.drowsiness(.drowsy), facing: nil)

    Snapshot.assert(
      film.strip(at: [first, 0.15, 0.3, 0.45, 0.6, 0.7]),
      named: "transition-awake-to-drowsy",
      within: tolerance
    )
  }

  func testDrowsyToYawningYawns() {
    let film = CatFilm(resting: .drowsy)
    film.scene.show(.drowsiness(.yawning), facing: nil)

    Snapshot.assert(
      film.strip(at: [first, 0.4, 0.8, 1.2, 1.6, 2.0, 2.4, 2.8, 3.1, 3.4]),
      named: "transition-drowsy-to-yawning",
      within: tolerance
    )
  }

  func testYawningToNoddingOffNodsOff() {
    let film = CatFilm(resting: .yawning)
    film.scene.show(.drowsiness(.noddingOff), facing: nil)

    Snapshot.assert(
      film.strip(at: [first, 0.4, 0.8, 1.3, 1.45, 1.7, 1.95, 2.2]),
      named: "transition-yawning-to-noddingOff",
      within: tolerance
    )
  }

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

  private func zAndBubblePixels(in frame: Bitmap) -> Int {
    stride(from: 0, to: frame.pixels.count, by: 4).filter { start in
      Int(frame.pixels[start + 2]) - Int(frame.pixels[start]) > 25
    }.count
  }

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
