import DockOverlayKit
import DrowsyDockCore
import SpriteKit

/// The SpriteKit scene that holds the cat.
@MainActor
final class MascotScene: SKScene {
  // Loops run slower to stay within the CPU budget for looping states (ADR 0011).
  private static let oneShotFramesPerSecond = 30
  private static let loopFramesPerSecond = 15

  weak var host: SceneHostView?

  private let cat = CatRenderer()
  private var director = AnimationDirector()
  private var facing = DockPerch.Facing.left
  private var isActive = false
  private var isPlayingOneShot = false
  private var isLooping = false
  private var nextGesture: Task<Void, Never>?
  private var generator = SystemRandomNumberGenerator()

  override init() {
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
      stopEverything()
      host?.isPaused = true
    }
  }

  // SceneHostView renders the frame in which this pauses it, so one frame shows each change.
  // An on-screen test showed the same pixels as three frames: a first pose fading in, a facing
  // change, a jump while the window was ordered out, and the veil.
  override func update(_ currentTime: TimeInterval) {
    guard !isPlayingOneShot, !isLooping, !director.isAnimating else { return }
    host?.isPaused = true
  }

  // MARK: - Transitions

  private func perform(_ step: AnimationDirector.Step) {
    stopEverything()
    let pose = MascotPose(for: step.target.settledState)
    guard let animation = step.animation else {
      cat.apply(pose)
      redraw()
      startAmbient()
      return
    }
    run(atFramesPerSecond: Self.oneShotFramesPerSecond)
    cat.play(animation, to: pose) { [weak self] in
      self?.animationFinished()
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
    guard isActive, !director.isAnimating, case .drowsiness(let state) = director.shown else {
      return
    }
    switch AmbientSchedule.next(for: state, using: &generator) {
    case .oneShot(let gesture, let pause):
      nextGesture = Task { [weak self] in
        guard (try? await Task.sleep(for: pause)) != nil else { return }
        self?.play(gesture)
      }
    case .loop(let loop):
      isLooping = true
      cat.loop(loop)
      run(atFramesPerSecond: Self.loopFramesPerSecond)
    }
  }

  private func play(_ gesture: AmbientGesture) {
    isPlayingOneShot = true
    run(atFramesPerSecond: Self.oneShotFramesPerSecond)
    cat.play(gesture) { [weak self] in
      guard let self else { return }
      isPlayingOneShot = false
      redraw()
      startAmbient()
    }
  }

  private func stopEverything() {
    nextGesture?.cancel()
    nextGesture = nil
    isPlayingOneShot = false
    isLooping = false
    cat.stopAnimations()
  }

  private func redraw() {
    host?.isPaused = false
  }

  private func run(atFramesPerSecond rate: Int) {
    host?.framesPerSecond = rate
    host?.isPaused = false
  }
}
