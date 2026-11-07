import DockOverlayKit
import DrowsyDockCore
import SpriteKit

/// The SpriteKit scene that holds the cat.
///
/// It keeps its view paused unless something moves. A pose change renders a couple of frames.
/// Idle states wait for `AmbientSchedule`'s pause with a task, unpause for the one action and
/// pause again. Looping states keep the view running, which `MascotOverlay` caps at 30 fps.
@MainActor
final class MascotScene: SKScene {
  // One frame to apply the change, one more in case the first lands before the window is ready.
  private static let framesPerChange = 2

  private let cat = CatRenderer()
  private var framesToDraw = 0
  private var facing = DockPerch.Facing.left
  private var restingState: DrowsinessState?
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

  /// Rests the cat in `state`, facing `facing`, and starts that state's ambient behaviour. Does
  /// nothing if it already rests there.
  func rest(in state: DrowsinessState, facing: DockPerch.Facing) {
    if facing != self.facing {
      self.facing = facing
      cat.face(facing)
      redraw()
    }
    guard state != restingState else { return }
    restingState = state
    stopAmbient()
    cat.apply(MascotPose(for: state))
    redraw()
    startAmbient()
  }

  /// Runs ambient behaviour while the cat is visible, and stops it, pausing the view, while it is
  /// hidden or faded out.
  func setActive(_ isActive: Bool) {
    guard isActive != self.isActive else { return }
    self.isActive = isActive
    if isActive {
      redraw()
      startAmbient()
    } else {
      stopAmbient()
      view?.isPaused = true
    }
  }

  override func update(_ currentTime: TimeInterval) {
    guard framesToDraw == 0 else {
      framesToDraw -= 1
      return
    }
    guard !isPlayingOneShot, !isLooping else { return }
    view?.isPaused = true
  }

  // MARK: - Ambient behaviour

  private func startAmbient() {
    guard isActive, let restingState else { return }
    switch AmbientSchedule.next(for: restingState, using: &generator) {
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

  private func stopAmbient() {
    nextAmbientAction?.cancel()
    nextAmbientAction = nil
    isPlayingOneShot = false
    isLooping = false
    cat.stopAmbient()
  }

  private func redraw() {
    framesToDraw = Self.framesPerChange
    view?.isPaused = false
  }
}
