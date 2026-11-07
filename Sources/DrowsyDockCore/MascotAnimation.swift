/// A one-shot animation that carries the cat from one mood to the next.
public enum MascotAnimation: Equatable, Sendable {
  /// A short blend of the pose: eyelids, head, ears, "z"s, bubble and veil.
  case crossfade
  /// Into `yawning`: a yawn and a nod.
  case yawn
  /// Into `noddingOff`: the head droops, the eyes shut, then a jerk awake into the new pose.
  case nodOff
  /// Into `waking`: the eyes snap open, a stretch and a sparkle, ending awake.
  case wakeUp

  /// How long the animation runs.
  public var duration: Duration {
    switch self {
    case .crossfade: .milliseconds(600)
    case .yawn: .milliseconds(3400)
    case .nodOff: .milliseconds(2200)
    // The spec allows at most 3 s, and the waking phase lasts `DrowsinessTracker.wakingDuration`.
    case .wakeUp: .milliseconds(2800)
    }
  }
}
