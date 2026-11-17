import DockOverlayKit
import DrowsyDockCore
import XCTest

@testable import DrowsyDock

@MainActor
final class PoseSnapshotTests: XCTestCase {
  override func setUpWithError() throws {
    try Snapshot.skipUnlessComparable()
  }

  private func pose(_ state: DrowsinessState, facing: DockPerch.Facing) -> Bitmap {
    let scene = MascotScene(clock: TestClock(), generator: SplitMix64(seed: 2026))
    scene.show(.drowsiness(state), facing: facing)
    return OffscreenRenderer(scene: scene).render(over: Snapshot.backdrop)
  }

  private func overlay(_ state: DrowsinessState, on dock: DockGeometry) -> Bitmap {
    let overlay = MascotOverlay(
      catScene: MascotScene(clock: TestClock(), generator: SplitMix64(seed: 2026))
    )
    addTeardownBlock { overlay.show(nil) }
    KeepAlive.keep(overlay)
    overlay.show(.drowsiness(state))
    overlay.present(.shown(dock.perch(for: MascotOverlay.spriteSize), on: dock))
    return OverlayFilm(overlay, on: dock).render()
  }

  // MARK: - Poses on a bottom Dock

  func testAwakeHasRoundOpenEyesUprightEarsAndAStraightHead() {
    Snapshot.assert(pose(.awake, facing: .left), named: "pose-awake-left", within: .sameRenderer)
  }

  func testDrowsyLidsCoverUnderHalfOfEachEyeTheHeadLeansAndTheEarsFoldSlightly() {
    Snapshot.assert(pose(.drowsy, facing: .left), named: "pose-drowsy-left", within: .sameRenderer)
  }

  func testYawningLidsSitLowerTheHeadLeansFurtherAndTheEarsFoldMore() {
    Snapshot.assert(
      pose(.yawning, facing: .left), named: "pose-yawning-left", within: .sameRenderer)
  }

  func testNoddingOffShowsSlitEyesDroopingEarsAndOneZ() {
    Snapshot.assert(
      pose(.noddingOff, facing: .left),
      named: "pose-noddingOff-left",
      within: .sameRenderer
    )
  }

  func testAsleepShowsClosedEyesFullyDroopedEarsTwoZsAndASnoreBubble() {
    Snapshot.assert(pose(.asleep, facing: .left), named: "pose-asleep-left", within: .sameRenderer)
  }

  // MARK: - The overlay over a Dock

  func testAsleepOnABottomDockTheVeilCoversTheDockAndThePawsRestOnItsTopEdge() {
    Snapshot.assert(
      overlay(.asleep, on: DockFixture.bottom),
      named: "overlay-asleep-bottom",
      within: .sameRenderer
    )
  }

  func testAwakeOnABottomDockThereIsNoVeil() {
    Snapshot.assert(
      overlay(.awake, on: DockFixture.bottom),
      named: "overlay-awake-bottom",
      within: .sameRenderer
    )
  }

  func testAsleepOnALeftDockTheCatFacesRightAndTheVeilFollowsTheDock() {
    Snapshot.assert(
      overlay(.asleep, on: DockFixture.left),
      named: "overlay-asleep-left-dock",
      within: .sameRenderer
    )
  }

  func testAsleepOnARightDockTheCatFacesLeftAndTheVeilFollowsTheDock() {
    Snapshot.assert(
      overlay(.asleep, on: DockFixture.right),
      named: "overlay-asleep-right-dock",
      within: .sameRenderer
    )
  }
}
