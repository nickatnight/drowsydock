import DockOverlayKit
import DrowsyDockCore
import SpriteKit

/// The SpriteKit scene that holds the cat.
@MainActor
final class MascotScene: SKScene, HostedScene {
  static let oneShotFramesPerSecond = 30
  static let loopFramesPerSecond = 15

  weak var host: SceneHostView?

  private let cat = CatRenderer()
  private var director = AnimationDirector()
  private var facing = DockPerch.Facing.left
  private var isActive = false
  private var isPlayingGestureOrLoop = false
  private var nextGesture: Task<Void, Never>?
  // Bumped whenever running work stops. SpriteKit can deliver a completion after its action was
  // removed, and a sleeping task can wake after it was cancelled, so each checks this first.
  private var generation = 0
  private let clock: any Clock<Duration>
  private var generator: any RandomNumberGenerator

  /// Creates the scene. `clock` times the pauses between gestures and `generator` draws them; tests
  /// pass a clock they advance and a seeded generator.
  init(
    clock: any Clock<Duration> = ContinuousClock(),
    generator: any RandomNumberGenerator = SystemRandomNumberGenerator()
  ) {
    self.clock = clock
    self.generator = generator
    super.init(size: CatRenderer.canvasSize)
    backgroundColor = .clear
    anchorPoint = .zero
    scaleMode = .fill
    cat.face(facing)
    addChild(cat.node)
  }

  required init?(coder: NSCoder) {
    nil
  }

  /// Shows `mood`, facing `facing` (or the same way as before when `nil`). While the cat is
  /// visible the change animates; while it is hidden or faded out, the cat switches at once.
  func show(_ mood: MascotMood, facing: DockPerch.Facing?) {
    if let facing, facing != self.facing {
      self.facing = facing
      cat.face(facing)
      redraw()
    }
    if isActive {
      if let step = director.request(mood) {
        perform(step)
      }
    } else if mood != director.target {
      perform(director.jump(to: mood))
    }
  }

  /// Runs animations while the cat is visible. While it is hidden or faded out, any animation
  /// jumps to its end, ambient behaviour stops and the view pauses.
  func setActive(_ isActive: Bool) {
    guard isActive != self.isActive else { return }
    self.isActive = isActive
    if isActive {
      redraw()
      startAmbient()
    } else {
      if director.isAnimating, let target = director.target {
        perform(director.jump(to: target))
      }
      stopEverything(before: nil)
      host?.isPaused = true
    }
  }

  var needsAnotherFrame: Bool {
    isPlayingGestureOrLoop || director.isAnimating
  }

  // MARK: - Transitions

  private func perform(_ step: AnimationDirector.Step) {
    stopEverything(before: step.animation)
    let pose = MascotPose(for: step.target.settledState)
    guard let animation = step.animation else {
      cat.apply(pose)
      redraw()
      startAmbient()
      return
    }
    run(atFramesPerSecond: Self.oneShotFramesPerSecond)
    let generation = self.generation
    cat.play(animation, to: pose) { [weak self] in
      guard let self, self.generation == generation else { return }
      animationFinished()
    }
  }

  private func animationFinished() {
    if let next = director.finishAnimation() {
      perform(next)
    } else {
      redraw()
      startAmbient()
    }
  }

  // MARK: - Ambient behaviour

  private func startAmbient() {
    nextGesture?.cancel()
    nextGesture = nil
    guard isActive, !director.isAnimating, case .drowsiness(let state) = director.shown else {
      return
    }
    switch AmbientSchedule.next(for: state, using: &generator) {
    case .oneShot(let gesture, let pause):
      nextGesture = Task { [weak self, generation, clock] in
        guard (try? await clock.sleep(for: pause)) != nil, !Task.isCancelled else { return }
        guard let self, self.generation == generation else { return }
        play(gesture)
      }
    case .loop(let loop):
      isPlayingGestureOrLoop = true
      cat.loop(loop)
      run(atFramesPerSecond: Self.loopFramesPerSecond)
    }
  }

  private func play(_ gesture: AmbientGesture) {
    guard isActive, !director.isAnimating, !isPlayingGestureOrLoop else { return }
    isPlayingGestureOrLoop = true
    run(atFramesPerSecond: Self.oneShotFramesPerSecond)
    let generation = self.generation
    cat.play(gesture) { [weak self] in
      guard let self, self.generation == generation else { return }
      isPlayingGestureOrLoop = false
      redraw()
      startAmbient()
    }
  }

  private func stopEverything(before next: MascotAnimation?) {
    generation += 1
    nextGesture?.cancel()
    nextGesture = nil
    isPlayingGestureOrLoop = false
    cat.stopAnimations(before: next)
  }

  private func redraw() {
    host?.isPaused = false
  }

  private func run(atFramesPerSecond rate: Int) {
    host?.framesPerSecond = rate
    host?.isPaused = false
  }
}
