import DockOverlayKit
import DrowsyDockCore
import SpriteKit

/// The SpriteKit scene that holds the cat.
///
/// `AnimationDirector` picks the animation into each new mood, and `AmbientSchedule` what the
/// cat does while it rests. The view stays paused unless something moves: a pose change renders
/// a couple of frames, a one-shot or a transition unpauses it until its completion, and only a
/// looping state keeps it running, at the 30 fps that `MascotOverlay` sets.
@MainActor
final class MascotScene: SKScene {
  // One frame to apply the change, one more in case the first lands before the window is ready.
  private static let framesPerChange = 2

  private let cat = CatRenderer()
  private var director = AnimationDirector()
  private var framesToDraw = 0
  private var facing = DockPerch.Facing.left
  private var isActive = false
  private var isPlayingOneShot = false
  private var isLooping = false
  private var nextAmbientAction: Task<Void, Never>?
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
      view?.isPaused = true
    }
  }

  override func update(_ currentTime: TimeInterval) {
    guard framesToDraw == 0 else {
      framesToDraw -= 1
      return
    }
    guard !isPlayingOneShot, !isLooping, !director.isAnimating else { return }
    view?.isPaused = true
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
    view?.isPaused = false
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
    case .oneShot(let action, let pause):
      nextAmbientAction = Task { [weak self] in
        guard (try? await Task.sleep(for: pause)) != nil else { return }
        self?.playOneShot(action)
      }
    case .loop(let action):
      isLooping = true
      cat.loop(action)
      view?.isPaused = false
    }
  }

  private func playOneShot(_ action: AmbientAction) {
    isPlayingOneShot = true
    view?.isPaused = false
    cat.play(action) { [weak self] in
      guard let self else { return }
      isPlayingOneShot = false
      redraw()
      startAmbient()
    }
  }

  // Cancels the ambient schedule and every running animation, leaving the cat in its pose.
  private func stopEverything() {
    nextAmbientAction?.cancel()
    nextAmbientAction = nil
    isPlayingOneShot = false
    isLooping = false
    cat.stopAnimations()
  }

  private func redraw() {
    framesToDraw = Self.framesPerChange
    view?.isPaused = false
  }
}
