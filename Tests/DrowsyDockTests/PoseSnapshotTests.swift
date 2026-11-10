import DockOverlayKit
import DrowsyDockCore
import XCTest

@testable import DrowsyDock

// QA section 8: the cat's pose in each state, drawn by the real `MascotScene` with the cat still,
// and the whole overlay (cat, veil and perch) over fixture Docks.
@MainActor
final class PoseSnapshotTests: XCTestCase {
  private let tolerance = SnapshotTolerance(channel: 2, differingPixels: 4)

  private let backdrop: (red: UInt8, green: UInt8, blue: UInt8) = (214, 220, 230)

  override func setUpWithError() throws {
    try Snapshot.skipUnlessReferenceArchitecture()
  }

  private func pose(_ state: DrowsinessState, facing: DockPerch.Facing) -> Bitmap {
    let scene = MascotScene()
    scene.show(.drowsiness(state), facing: facing)
    return OffscreenRenderer(scene: scene).render(over: backdrop)
  }

  private func overlay(_ state: DrowsinessState, on dock: DockGeometry) -> Bitmap {
    let overlay = MascotOverlay()
    addTeardownBlock { overlay.show(nil) }
    KeepAlive.keep(overlay)
    overlay.show(.drowsiness(state))
    overlay.present(.shown(dock.perch(for: MascotOverlay.spriteSize), on: dock))
    return OverlayFilm(overlay, on: dock).render()
  }

  // MARK: - Poses on a bottom Dock

  func testAwakeHasRoundOpenEyesUprightEarsAndAStraightHead() {
    Snapshot.assert(pose(.awake, facing: .left), named: "pose-awake-left", within: tolerance)
  }

  func testDrowsyLidsCoverUnderHalfOfEachEyeTheHeadLeansAndTheEarsFoldSlightly() {
    Snapshot.assert(pose(.drowsy, facing: .left), named: "pose-drowsy-left", within: tolerance)
  }

  func testYawningLidsSitLowerTheHeadLeansFurtherAndTheEarsFoldMore() {
    Snapshot.assert(pose(.yawning, facing: .left), named: "pose-yawning-left", within: tolerance)
  }

  func testNoddingOffShowsSlitEyesDroopingEarsAndOneZ() {
    Snapshot.assert(
      pose(.noddingOff, facing: .left),
      named: "pose-noddingOff-left",
      within: tolerance
    )
  }

  func testAsleepShowsClosedEyesFullyDroopedEarsTwoZsAndASnoreBubble() {
    Snapshot.assert(pose(.asleep, facing: .left), named: "pose-asleep-left", within: tolerance)
  }

  // MARK: - The overlay over a Dock

  func testAsleepOnABottomDockTheVeilCoversTheDockAndThePawsRestOnItsTopEdge() {
    Snapshot.assert(
      overlay(.asleep, on: DockFixture.bottom),
      named: "overlay-asleep-bottom",
      within: tolerance
    )
  }

  func testAwakeOnABottomDockThereIsNoVeil() {
    Snapshot.assert(
      overlay(.awake, on: DockFixture.bottom),
      named: "overlay-awake-bottom",
      within: tolerance
    )
  }

  func testAsleepOnALeftDockTheCatFacesRightAndTheVeilFollowsTheDock() {
    Snapshot.assert(
      overlay(.asleep, on: DockFixture.left),
      named: "overlay-asleep-left-dock",
      within: tolerance
    )
  }

  func testAsleepOnARightDockTheCatFacesLeftAndTheVeilFollowsTheDock() {
    Snapshot.assert(
      overlay(.asleep, on: DockFixture.right),
      named: "overlay-asleep-right-dock",
      within: tolerance
    )
  }
}
