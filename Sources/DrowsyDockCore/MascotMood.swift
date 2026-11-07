/// What the mascot shows: a drowsiness state, or the wake-up after AC power is connected.
public enum MascotMood: Hashable, Sendable {
  case drowsiness(DrowsinessState)
  case waking

  /// The state the mascot rests in: its own state, or `awake` once the wake-up ends.
  public var settledState: DrowsinessState {
    switch self {
    case .drowsiness(let state): state
    case .waking: .awake
    }
  }
}

extension DrowsinessTracker.Phase {
  /// What the mascot shows in this phase, or `nil` when there is no battery and so no mascot.
  public var mood: MascotMood? {
    switch self {
    case .noBattery: nil
    case .discharging(let state): .drowsiness(state)
    case .waking: .waking
    case .onExternalPower: .drowsiness(.awake)
    }
  }
}
