import DrowsyDockCore
import XCTest

@testable import DrowsyDock

@MainActor
final class AmbientSnapshotTests: XCTestCase {
  override func setUpWithError() throws {
    try Snapshot.skipUnlessComparable()
  }

  func testAnAwakeCatBlinksAfterAPauseAndIsStillOtherwise() throws {
    let film = CatFilm(resting: .awake)
    waitUntil("the blink is scheduled") { film.clock.sleeperCount == 1 }
    let still = film.frame()
    film.advance(by: 5)

    XCTAssertFalse(film.scene.needsAnotherFrame)
    XCTAssertEqual(film.frame(), still)
    let pause = film.playNextGesture(in: self)
    XCTAssertTrue((Duration.seconds(8)...Duration.seconds(20)).contains(try XCTUnwrap(pause)))
    Snapshot.assert(
      film.strip(at: [0.04, 0.08, 0.12, 0.16, 0.2, 0.26]),
      named: "ambient-awake-blink",
      within: .sameRenderer
    )
    film.advance(by: 0.2)
    waitUntil("the next blink is scheduled") { film.clock.sleeperCount == 1 }
    XCTAssertFalse(film.scene.needsAnotherFrame)
    XCTAssertEqual(film.frame(), still)
  }

  func testADrowsyCatBlinksSlowly() throws {
    let film = CatFilm(resting: .drowsy)
    let pause = film.playNextGesture(in: self)

    XCTAssertTrue((Duration.seconds(10)...Duration.seconds(20)).contains(try XCTUnwrap(pause)))
    Snapshot.assert(
      film.strip(at: [0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1.1]),
      named: "ambient-drowsy-slow-blink",
      within: .sameRenderer
    )
  }

  func testAYawningCatYawnsAndNods() throws {
    let film = CatFilm(resting: .yawning)
    let pause = film.playNextGesture(in: self)

    XCTAssertTrue((Duration.seconds(40)...Duration.seconds(50)).contains(try XCTUnwrap(pause)))
    Snapshot.assert(
      film.strip(at: [0.25, 0.5, 1.0, 1.5, 1.8, 2.1, 2.4, 2.7]),
      named: "ambient-yawning-yawn-and-nod",
      within: .sameRenderer
    )
  }

  func testANoddingOffCatFloatsZsAndBobsItsHead() {
    let film = CatFilm(resting: .noddingOff)

    XCTAssertTrue(film.scene.needsAnotherFrame)
    Snapshot.assert(
      film.strip(at: [0.4, 0.8, 1.2, 1.6, 2.0, 2.4, 2.8, 3.2]),
      named: "ambient-noddingOff-floating-zs",
      within: .sameRenderer
    )
  }

  func testAnAsleepCatSnores() {
    let film = CatFilm(resting: .asleep)

    XCTAssertTrue(film.scene.needsAnotherFrame)
    Snapshot.assert(
      film.strip(at: [0.4, 0.8, 1.2, 1.6, 2.0, 2.4, 2.8, 3.2]),
      named: "ambient-asleep-snore",
      within: .sameRenderer
    )
  }
}
