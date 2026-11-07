import SpriteKit

extension SKAction {
  /// Returns an action that runs `block` on the main actor, for use in a sequence.
  static func onMainActor(_ block: @escaping @MainActor () -> Void) -> SKAction {
    // With `queue: .main`, SpriteKit runs the block on the main thread.
    .run({ MainActor.assumeIsolated(block) }, queue: .main)
  }

  /// Returns an action that waits `duration` seconds, then runs `completion` on the main actor.
  static func completion(
    after duration: TimeInterval,
    _ completion: @escaping @MainActor () -> Void
  ) -> SKAction {
    .sequence([.wait(forDuration: duration), .onMainActor(completion)])
  }
}
