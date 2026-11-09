/// The phase lengths, in seconds, that fix how long the cat's animations take.
///
/// `CatRenderer` builds its SpriteKit timelines from these. Each transition has one phase whose
/// length is whatever its `MascotAnimation.duration` leaves, `flexiblePhase(of:)`, so the
/// timeline ends exactly when the transition does.
public enum MascotTimeline {
  /// The three phases of a blink, in seconds.
  public struct Blink: Equatable, Sendable {
    /// The lids closing.
    public let close: Double

    /// The lids staying shut.
    public let hold: Double

    /// The lids opening.
    public let open: Double

    /// The whole blink.
    public var length: Double { close + hold + open }
  }

  /// An awake cat's blink, which also ends the wake-up.
  public static let blink = Blink(close: 0.08, hold: 0.04, open: 0.12)

  /// A drowsy cat's slow blink.
  public static let slowBlink = Blink(close: 0.4, hold: 0.25, open: 0.45)

  /// The yawn and nod's phases, in order, in seconds. The mouth and the lids follow the head.
  public enum YawnAndNod {
    /// The head leans back and the mouth opens.
    public static let leanBack = 0.5

    /// The yawn at its widest.
    public static let holdYawn = 0.9

    /// The head straightens and the mouth closes.
    public static let straighten = 0.4

    /// The head nods forward.
    public static let nodDown = 0.6

    /// The head jerks back up.
    public static let jerkUp = 0.22

    /// The whole yawn and nod.
    public static let length = leanBack + holdYawn + straighten + nodDown + jerkUp
  }

  /// The nod-off's fixed phases, in seconds. The settle after them is its flexible phase.
  public enum NodOff {
    /// The head droops forward as the eyes fall shut.
    public static let droop = 1.3

    /// The head jerks back up.
    public static let jerk = 0.15
  }

  /// The wake-up's fixed opening, in seconds. The eyes then hold open for the flexible phase and
  /// close the wake-up with a `blink`.
  public enum WakeUp {
    /// The eyes snap open.
    public static let snapOpen = 0.08
  }

  /// How long, in seconds, the parts a loop moves take to ease back into the pose when a
  /// transition interrupts the loop: the breathing body and snore bubble, the bobbing head and
  /// the "z"s in flight. It runs alongside the transition and ends before the shortest one does.
  public static let loopEaseOut = 0.25

  /// Returns the length, in seconds, of the phase that takes whatever `animation`'s duration
  /// leaves: the whole crossfade, the settle before the yawn and nod, the settle after the
  /// nod-off's jerk, or the hold before the wake-up's final blink.
  public static func flexiblePhase(of animation: MascotAnimation) -> Double {
    let total = animation.duration.inSeconds
    switch animation {
    case .crossfade:
      return total
    case .yawn:
      return total - YawnAndNod.length
    case .nodOff:
      return total - NodOff.droop - NodOff.jerk
    case .wakeUp:
      return total - WakeUp.snapOpen - blink.length
    }
  }
}
