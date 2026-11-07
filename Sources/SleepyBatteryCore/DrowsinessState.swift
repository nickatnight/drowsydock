/// How sleepy the mascot is, ordered from `awake` to `asleep`.
public enum DrowsinessState: Int, CaseIterable, Comparable, Sendable {
  case awake
  case drowsy
  case yawning
  case noddingOff
  case asleep

  /// Creates the state a discharging battery at `percentage` maps to under `thresholds`.
  public init(percentage: Int, thresholds: Thresholds) {
    switch percentage {
    case thresholds.drowsy...: self = .awake
    case thresholds.yawning...: self = .drowsy
    case thresholds.noddingOff...: self = .yawning
    case thresholds.asleep...: self = .noddingOff
    default: self = .asleep
    }
  }

  public static func < (lhs: DrowsinessState, rhs: DrowsinessState) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}
