/// Decides which animation carries the cat into each new mood, one at a time.
///
/// A mood that arrives while an animation plays waits for it to finish. Only the newest one
/// waits: back-to-back changes collapse to the last. The wake-up is the exception: it interrupts.
public struct AnimationDirector: Equatable, Sendable {
  /// How the cat gets from one mood to another.
  public enum Transition: Equatable, Sendable {
    /// The cat already shows the mood.
    case none
    /// Switch to the mood's pose at once.
    case cut
    /// Play the animation, ending in the mood's pose.
    case play(MascotAnimation)
  }

  /// What the caller does next: play `animation`, or switch at once when it is `nil`, and end in
  /// `target`.
  public struct Step: Equatable, Sendable {
    /// The animation to play, or `nil` to switch at once.
    public let animation: MascotAnimation?

    /// The mood the cat ends in.
    public let target: MascotMood

    /// Creates a step.
    public init(animation: MascotAnimation?, target: MascotMood) {
      self.animation = animation
      self.target = target
    }
  }

  /// The mood on screen, or the one the current animation ends in.
  public private(set) var shown: MascotMood?

  /// Whether an animation is playing. The caller reports its end with `finishAnimation()`.
  public private(set) var isAnimating = false

  private var queued: MascotMood?

  /// Creates a director with `mood` already on screen, or nothing yet.
  public init(showing mood: MascotMood? = nil) {
    shown = mood
  }

  /// The newest mood requested: the queued one, or else the one shown.
  public var target: MascotMood? {
    queued ?? shown
  }

  /// Returns how the cat gets from `from` to `to`. In quiet hours every change is a cut.
  public static func transition(
    from: MascotMood?,
    to: MascotMood,
    quietHours: Bool = false
  ) -> Transition {
    guard let from else { return .cut }
    guard from != to else { return .none }
    guard !quietHours else { return .cut }
    switch to {
    case .waking:
      return .play(.wakeUp)
    case .drowsiness(let state) where state == from.settledState:
      return .cut
    case .drowsiness(.yawning):
      return .play(.yawn)
    case .drowsiness(.noddingOff):
      return .play(.nodOff)
    case .drowsiness:
      return .play(.crossfade)
    }
  }

  /// Asks for `mood`. Returns the step to take now, or `nil` when there is nothing to do yet:
  /// the mood is already shown, or an animation is playing and the mood waits for it.
  ///
  /// `.waking` doesn't wait: plugging in always shows the wake-up, so it replaces whatever is
  /// playing and drops anything queued. Waiting would let the end of `waking` overwrite it in the
  /// queue before it ever played. The caller stops the replaced animation.
  public mutating func request(_ mood: MascotMood, quietHours: Bool = false) -> Step? {
    if isAnimating {
      guard mood == .waking, shown != .waking else {
        queued = mood
        return nil
      }
      isAnimating = false
      queued = nil
    }
    switch Self.transition(from: shown, to: mood, quietHours: quietHours) {
    case .none:
      return nil
    case .cut:
      shown = mood
      return Step(animation: nil, target: mood)
    case .play(let animation):
      shown = mood
      isAnimating = true
      return Step(animation: animation, target: mood)
    }
  }

  /// Records that the current animation ended. Returns the step for the mood that waited, if any.
  public mutating func finishAnimation(quietHours: Bool = false) -> Step? {
    isAnimating = false
    guard let queued else { return nil }
    self.queued = nil
    return request(queued, quietHours: quietHours)
  }

  /// Shows `mood` at once, dropping any animation and anything queued. For changes nobody should
  /// see animate, such as while the overlay is hidden.
  public mutating func jump(to mood: MascotMood) -> Step {
    shown = mood
    isAnimating = false
    queued = nil
    return Step(animation: nil, target: mood)
  }
}
