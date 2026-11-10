import DockOverlayKit
import DrowsyDockCore
import XCTest

@testable import DrowsyDock

// QA section 8: the cat's pose in each state, drawn by the real `MascotScene` with the cat still,
// and the whole overlay (cat, veil and perch) over fixture Docks.
@MainActor
final class PoseSnapshotTests: XCTestCase {
  // The same code on the same GPU draws identical pixels, so the tolerance only absorbs driver
  // rounding. A changed pose moves hundreds of pixels.
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

  // The real overlay at rest on `dock`, with the pointer away from it.
  private func overlay(_ state: DrowsinessState, on dock: DockGeometry) -> Bitmap {
    let overlay = MascotOverlay()
    addTeardownBlock { overlay.show(nil) }
    KeepAlive.keep(overlay)
    overlay.show(.drowsiness(state))
    overlay.present(.shown(dock.perch(for: MascotOverlay.spriteSize), on: dock))
    return OverlayFilm(overlay, on: dock).render()
  }

  // MARK: - Poses on a bottom Dock

  // QA 8.1
  func testAwakeHasRoundOpenEyesUprightEarsAndAStraightHead() {
    Snapshot.assert(pose(.awake, facing: .left), named: "pose-awake-left", within: tolerance)
  }

  // QA 8.2
  func testDrowsyLidsCoverUnderHalfOfEachEyeTheHeadLeansAndTheEarsFoldSlightly() {
    Snapshot.assert(pose(.drowsy, facing: .left), named: "pose-drowsy-left", within: tolerance)
  }

  // QA 8.3
  func testYawningLidsSitLowerTheHeadLeansFurtherAndTheEarsFoldMore() {
    Snapshot.assert(pose(.yawning, facing: .left), named: "pose-yawning-left", within: tolerance)
  }

  // QA 8.4
  func testNoddingOffShowsSlitEyesDroopingEarsAndOneZ() {
    Snapshot.assert(
      pose(.noddingOff, facing: .left),
      named: "pose-noddingOff-left",
      within: tolerance
    )
  }

  // QA 8.5, the cat
  func testAsleepShowsClosedEyesFullyDroopedEarsTwoZsAndASnoreBubble() {
    Snapshot.assert(pose(.asleep, facing: .left), named: "pose-asleep-left", within: tolerance)
  }

  // MARK: - The overlay over a Dock

  // QA 8.5 (the veil's edge on the Dock's outline, rounded ends included) and 8.15 (the paws on
  // the outline). The veil and the cat come from the real MascotOverlay on the user's job 003 Dock.
  func testAsleepOnABottomDockTheVeilCoversTheDockAndThePawsRestOnItsTopEdge() {
    Snapshot.assert(
      overlay(.asleep, on: DockFixture.bottom),
      named: "overlay-asleep-bottom",
      within: tolerance
    )
  }

  // QA 8.1 and 8.15: no veil while awake, and the cat sits on the last icon's right edge.
  func testAwakeOnABottomDockThereIsNoVeil() {
    Snapshot.assert(
      overlay(.awake, on: DockFixture.bottom),
      named: "overlay-awake-bottom",
      within: tolerance
    )
  }

  // QA 8.9: on a left Dock the cat sits above the top icon facing right, and the "z"s still read
  // as Z. The veil follows the Dock.
  func testAsleepOnALeftDockTheCatFacesRightAndTheVeilFollowsTheDock() {
    Snapshot.assert(
      overlay(.asleep, on: DockFixture.left),
      named: "overlay-asleep-left-dock",
      within: tolerance
    )
  }

  // QA 8.9: on a right Dock the cat faces left.
  func testAsleepOnARightDockTheCatFacesLeftAndTheVeilFollowsTheDock() {
    Snapshot.assert(
      overlay(.asleep, on: DockFixture.right),
      named: "overlay-asleep-right-dock",
      within: tolerance
    )
  }
}
