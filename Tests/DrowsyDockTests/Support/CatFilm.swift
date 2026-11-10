import DockOverlayKit
import DrowsyDockCore
import XCTest

@testable import DrowsyDock

@MainActor
final class CatFilm {
  static let backdrop: (red: UInt8, green: UInt8, blue: UInt8) = (214, 220, 230)

  let clock = TestClock()
  let scene: MascotScene
  private let renderer: OffscreenRenderer

  init(resting state: DrowsinessState, facing: DockPerch.Facing = .left, seed: UInt64 = 2026) {
    scene = MascotScene(clock: clock, generator: SplitMix64(seed: seed))
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

  @discardableResult
  func playNextGesture(in test: XCTestCase) -> Duration? {
    test.waitUntil("the scene schedules a gesture") { clock.sleeperCount == 1 }
    guard let pause = clock.timeToNextDeadline else { return nil }
    clock.advance(by: pause)
    test.waitUntil("the gesture starts") { scene.needsAnotherFrame }
    return pause
  }
}
