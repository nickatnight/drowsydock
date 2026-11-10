import DockOverlayKit
import DrowsyDockCore
import XCTest

@testable import DrowsyDock

// QA 11.1 and 11.5: the whole Dock nods off, drawn by the real MascotOverlay over fixture Docks.
// Each icon's artwork darkens for 0.3 s and puffs a "z"; the wave runs along the Dock.
@MainActor
final class CrowdWaveSnapshotTests: XCTestCase {
  private let tolerance = SnapshotTolerance(channel: 2, differingPixels: 4)

  override func setUpWithError() throws {
    try Snapshot.skipUnlessReferenceArchitecture()
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

  // QA 11.1: left to right along a bottom Dock; the dark shape covers each icon's rounded square
  // and nothing more, and the whole wave ends within 4 s (2.65 s for twelve icons).
  func testTheWaveRunsLeftToRightAlongABottomDock() {
    let film = wave(on: DockFixture.bottom)

    Snapshot.assert(
      film.strip(at: [0.2, 0.7, 1.2, 1.7, 2.2, 2.7]),
      named: "crowd-wave-bottom",
      within: tolerance
    )
    XCTAssertFalse(film.overlay.canvasScene.needsAnotherFrame)
  }

  // QA 11.5: from the top icon down a left Dock, with the "z"s drifting right, into the screen.
  func testTheWaveRunsDownALeftDockAndTheZsDriftIntoTheScreen() {
    let film = wave(on: DockFixture.left)

    Snapshot.assert(
      film.strip(at: [0.3, 0.9, 1.5]),
      named: "crowd-wave-left-dock",
      within: tolerance
    )
  }

  // QA 11.5: on a right Dock the "z"s drift left.
  func testOnARightDockTheZsDriftLeft() {
    let film = wave(on: DockFixture.right)

    Snapshot.assert(
      film.strip(at: [0.3, 0.9, 1.5]),
      named: "crowd-wave-right-dock",
      within: tolerance
    )
  }
}
