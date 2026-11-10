import DockOverlayKit
import DrowsyDockCore
import XCTest

@testable import DrowsyDock

// QA section 8: the cat's pose in each state, drawn by the real `MascotScene` with the cat still.
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

  // QA 8.1
  func testAwakeHasRoundOpenEyesUprightEarsAndAStraightHead() {
    Snapshot.assert(pose(.awake, facing: .left), named: "pose-awake-left", within: tolerance)
  }
}
