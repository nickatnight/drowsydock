import DockOverlayKit
import DrowsyDockCore
import QuartzCore
import XCTest

@testable import DrowsyDock

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

  func testTheLoopsDrawTwelveFramesASecond() throws {
    for state in [DrowsinessState.noddingOff, .asleep] {
      let overlay = try overlay(showing: state)
      let cat = try catHost(overlay)

      XCTAssertEqual(runDisplayLinks([cat], for: 2), [24], "\(state)")
      XCTAssertFalse(cat.isPaused, "\(state)")
      XCTAssertEqual(cat.framesPerSecond, 12, "\(state)")
      XCTAssertEqual(cat.displayLink?.preferredFrameRateRange.preferred, 12, "\(state)")
    }
  }

  // The display link only delivers rates that divide the display's refresh rate: on a 120 Hz
  // display a request for 13 fps drew 15 (ADR 0017).
  func testEveryFrameRateDividesSixtyAndOneHundredTwentyHertz() {
    for rate in [MascotScene.loopFramesPerSecond, MascotScene.oneShotFramesPerSecond] {
      XCTAssertEqual(60 % rate, 0, "\(rate) fps")
      XCTAssertEqual(120 % rate, 0, "\(rate) fps")
    }
  }

  func testATransitionDrawsThirtyFramesASecondUntilItEnds() throws {
    let overlay = try overlay(showing: .awake)
    let cat = try catHost(overlay)
    runDisplayLinks([cat], for: 1)

    overlay.show(.drowsiness(.drowsy))

    XCTAssertEqual(cat.framesPerSecond, 30)
    let frames = runDisplayLinks([cat], for: 2)[0]
    // One frame per tick of the crossfade, plus the first and the ones until its completion lands.
    let crossfadeFrames = Int(
      MascotAnimation.crossfade.duration.inSeconds * Double(MascotScene.oneShotFramesPerSecond)
    )
    XCTAssertTrue(
      (crossfadeFrames...crossfadeFrames + 4).contains(frames),
      "\(frames) frames for a crossfade of \(crossfadeFrames)"
    )
    XCTAssertTrue(cat.isPaused)
  }

  func testTheVeilDrawsOnceThenTheCanvasPauses() throws {
    let overlay = try overlay(showing: .asleep)
    let canvas = try canvasHost(overlay)

    XCTAssertEqual(runDisplayLinks([canvas], for: 3), [1])
    XCTAssertTrue(canvas.isPaused)
  }

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
