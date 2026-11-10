import DockOverlayKit
import DrowsyDockCore
import XCTest

@testable import DrowsyDock

/// Films the real `MascotScene`, visible, with a test clock for the pauses between gestures and a
/// seeded generator for their lengths.
@MainActor
final class CatFilm {
  static let backdrop: (red: UInt8, green: UInt8, blue: UInt8) = (214, 220, 230)

  let clock = TestClock()
  let scene: MascotScene
  private let renderer: OffscreenRenderer

  /// Starts with the cat resting in `state`, visible, so its ambient behaviour starts.
  init(resting state: DrowsinessState, facing: DockPerch.Facing = .left, seed: UInt64 = 2026) {
    scene = MascotScene(clock: clock, generator: SeededGenerator(seed: seed))
    scene.show(.drowsiness(state), facing: facing)
    scene.setActive(true)
    renderer = OffscreenRenderer(scene: scene)
    OffscreenRenderer.drainMainQueue()
  }

  func advance(by seconds: TimeInterval) {
    renderer.advance(by: seconds)
  }

  func frame() -> Bitmap {
    renderer.render(over: Self.backdrop)
  }

  /// Frames at `times`, in seconds from now and increasing, side by side.
  func strip(at times: [TimeInterval]) -> Bitmap {
    var elapsed: TimeInterval = 0
    var frames: [Bitmap] = []
    for time in times {
      advance(by: time - elapsed)
      elapsed = time
      frames.append(frame())
    }
    return Bitmap.row(frames, gap: 4, background: (255, 255, 255))
  }

  /// Waits for the scene to schedule its next gesture, moves the clock to it, and waits for the
  /// gesture to start. Returns how long the pause was.
  @discardableResult
  func playNextGesture(in test: XCTestCase) -> Duration? {
    test.waitUntil("the scene schedules a gesture") { clock.sleeperCount == 1 }
    guard let pause = clock.timeToNextDeadline else { return nil }
    clock.advance(by: pause)
    test.waitUntil("the gesture starts") { scene.needsAnotherFrame }
    return pause
  }
}
