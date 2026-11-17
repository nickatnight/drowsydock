import DockOverlayKit
import DrowsyDockCore
import XCTest

@testable import DrowsyDock

@MainActor
final class CrowdWaveSnapshotTests: XCTestCase {
  override func setUpWithError() throws {
    try Snapshot.skipUnlessComparable()
  }

  private func wave(on dock: DockGeometry) -> OverlayFilm {
    let overlay = MascotOverlay(catScene: MascotScene(clock: TestClock()))
    addTeardownBlock { overlay.show(nil) }
    KeepAlive.keep(overlay)
    overlay.show(.drowsiness(.asleep))
    overlay.present(.shown(dock.perch(for: MascotOverlay.spriteSize), on: dock))
    let film = OverlayFilm(overlay, on: dock)
    XCTAssertTrue(overlay.playCrowdEffect())
    return film
  }

  func testTheWaveRunsLeftToRightAlongABottomDock() {
    let film = wave(on: DockFixture.bottom)

    Snapshot.assert(
      film.strip(at: [0.2, 0.7, 1.2, 1.7, 2.2, 2.7]),
      named: "crowd-wave-bottom",
      within: .sameRenderer
    )
    XCTAssertFalse(film.overlay.canvasScene.needsAnotherFrame)
  }

  func testTheWaveRunsDownALeftDockAndTheZsDriftIntoTheScreen() {
    let film = wave(on: DockFixture.left)

    Snapshot.assert(
      film.strip(at: [0.3, 0.9, 1.5]),
      named: "crowd-wave-left-dock",
      within: .sameRenderer
    )
  }

  func testOnARightDockTheZsDriftLeft() {
    let film = wave(on: DockFixture.right)

    Snapshot.assert(
      film.strip(at: [0.3, 0.9, 1.5]),
      named: "crowd-wave-right-dock",
      within: .sameRenderer
    )
  }
}
