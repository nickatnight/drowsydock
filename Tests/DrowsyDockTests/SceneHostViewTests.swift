import DockOverlayKit
import DrowsyDockCore
import QuartzCore
import XCTest

@testable import DrowsyDock

// QA 8.13, 9.8 and the frame-count side of 3.7, 7.6 and 10.11 (c): frames drawn by the real
// SceneHostViews in the real MascotOverlay, counted while a stand-in display link calls them at
// the rate each view asks for. A paused view gets no calls, as a paused CADisplayLink makes none.
@MainActor
final class SceneHostViewTests: XCTestCase {
  private let dock = DockFixture.bottom

  private var shown: OverlayPresentation {
    .shown(dock.perch(for: MascotOverlay.spriteSize), on: dock)
  }

  private var fadedOut: OverlayPresentation {
    .fadedOut(dock.perch(for: MascotOverlay.spriteSize), on: dock)
  }

  private var time: CFTimeInterval = 1000

  private func overlay(showing state: DrowsinessState) throws -> MascotOverlay {
    let overlay = MascotOverlay(catScene: MascotScene(clock: TestClock()))
    addTeardownBlock { overlay.show(nil) }
    KeepAlive.keep(overlay)
    overlay.show(.drowsiness(state))
    overlay.present(shown)
    for host in try hosts(of: overlay) {
      host.layoutSubtreeIfNeeded()
    }
    return overlay
  }

  private func hosts(of overlay: MascotOverlay) throws -> [SceneHostView] {
    [try XCTUnwrap(overlay.catScene.host), try XCTUnwrap(overlay.canvasScene.host)]
  }

  private func catHost(_ overlay: MascotOverlay) throws -> SceneHostView {
    try XCTUnwrap(overlay.catScene.host)
  }

  private func canvasHost(_ overlay: MascotOverlay) throws -> SceneHostView {
    try XCTUnwrap(overlay.canvasScene.host)
  }

  /// Runs a stand-in display link for `seconds` and returns the frames each host drew.
  @discardableResult
  private func runDisplayLinks(
    _ hosts: [SceneHostView],
    for seconds: CFTimeInterval
  ) -> [Int] {
    let before = hosts.map(\.framesDrawn)
    var nextFrame = hosts.map { _ in time }
    let end = time + seconds
    let tick = 1.0 / 240
    while time < end - 1e-9 {
      for (index, host) in hosts.enumerated() where !host.isPaused && time >= nextFrame[index] {
        host.drawFrame(atTime: time)
        nextFrame[index] = time + 1 / Double(host.framesPerSecond) - 1e-9
      }
      OffscreenRenderer.drainMainQueue()
      time += tick
    }
    return zip(hosts, before).map { $0.framesDrawn - $1 }
  }

  // QA 8.13: an idle pose draws one frame for the change, then nothing.
  func testAnIdlePoseDrawsOneFrameAndThenNothing() throws {
    for state in [DrowsinessState.awake, .drowsy, .yawning] {
      let overlay = try overlay(showing: state)
      let cat = try catHost(overlay)

      XCTAssertEqual(runDisplayLinks([cat], for: 1), [1], "\(state)")
      XCTAssertEqual(runDisplayLinks([cat], for: 5), [0], "\(state)")
      XCTAssertTrue(cat.isPaused, "\(state)")
      XCTAssertEqual(cat.displayLink?.isPaused, true, "\(state)")
    }
  }

  // QA 8.13 and 10.11 (c): after the snore, the loop's ease-out, the crossfade, the veil's fade
  // and the canvas pausing, nothing draws.
  func testLeavingTheSnoreForAwakeEndsWithEveryViewPaused() throws {
    let overlay = try overlay(showing: .asleep)
    let views = try hosts(of: overlay)
    runDisplayLinks(views, for: 2)

    overlay.show(.drowsiness(.awake))
    let duringCrossfade = runDisplayLinks(views, for: 1)
    let afterwards = runDisplayLinks(views, for: 5)

    XCTAssertGreaterThan(duringCrossfade[0], 10)
    XCTAssertEqual(afterwards, [0, 0])
    XCTAssertTrue(views.allSatisfy(\.isPaused))
  }

  // ADR 0011: a transition draws at 30 frames a second, then stops.
  func testATransitionDrawsThirtyFramesASecondUntilItEnds() throws {
    let overlay = try overlay(showing: .awake)
    let cat = try catHost(overlay)
    runDisplayLinks([cat], for: 1)

    overlay.show(.drowsiness(.drowsy))

    XCTAssertEqual(cat.framesPerSecond, 30)
    let frames = runDisplayLinks([cat], for: 2)[0]
    // 0.6 s at 30 fps is 18 frames, plus the first and the one after the completion arrives.
    XCTAssertTrue((18...22).contains(frames), "\(frames) frames for a 0.6 s crossfade")
    XCTAssertTrue(cat.isPaused)
  }

  // QA 8.5: the canvas draws the veil once and pauses while the veil is still.
  func testTheVeilDrawsOnceThenTheCanvasPauses() throws {
    let overlay = try overlay(showing: .asleep)
    let canvas = try canvasHost(overlay)

    XCTAssertEqual(runDisplayLinks([canvas], for: 3), [1])
    XCTAssertTrue(canvas.isPaused)
  }

  // QA 11.1: the canvas draws while the wave runs, then pauses.
  func testTheCanvasDrawsUntilTheWaveEndsThenPauses() throws {
    let overlay = try overlay(showing: .asleep)
    let canvas = try canvasHost(overlay)
    runDisplayLinks([canvas], for: 1)

    XCTAssertTrue(overlay.playCrowdEffect())
    let duringWave = runDisplayLinks([canvas], for: 4.5)[0]
    let afterwards = runDisplayLinks([canvas], for: 2)[0]

    XCTAssertGreaterThan(duringWave, 60)
    XCTAssertEqual(afterwards, 0)
    XCTAssertTrue(canvas.isPaused)
  }

  // QA 9.8: while the cat is faded out at 5%, the snore draws nothing; it resumes after.
  func testAFadedOutCatDrawsNothingAndResumesWhenShown() throws {
    let overlay = try overlay(showing: .asleep)
    let cat = try catHost(overlay)
    runDisplayLinks([cat], for: 1)

    overlay.present(fadedOut)
    XCTAssertEqual(runDisplayLinks([cat], for: 3), [0])
    overlay.present(shown)

    XCTAssertGreaterThan(runDisplayLinks([cat], for: 1)[0], 10)
  }
}
