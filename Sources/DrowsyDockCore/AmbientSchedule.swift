/// Something the cat does on its own while it rests in a state.
public enum AmbientAction: Equatable, Sendable {
  case blink
  case slowBlink
  case yawnAndNod
  case floatingZs
  case snore
}

/// What the cat does next while resting: one action after a pause, or one action on a loop.
public enum AmbientBehaviour: Equatable, Sendable {
  /// Wait for `after`, play the action once, then ask `AmbientSchedule` again.
  case oneShot(AmbientAction, after: Duration)

  /// Play the action over and over until the state changes.
  case loop(AmbientAction)
}

/// Decides what the cat does between state changes, and when.
///
/// Idle states play a short action after a random pause, so the scene can stay paused in
/// between. Only `noddingOff` and `asleep` loop.
public enum AmbientSchedule {
  private static let awakeBlinkSeconds = 8.0...20.0

  private static let drowsyBlinkSeconds = 10.0...20.0

  private static let yawnSeconds = 40.0...50.0

  /// Returns what the cat does next in `state`, drawing any pause from `generator`.
  public static func next(
    for state: DrowsinessState,
    using generator: inout some RandomNumberGenerator
  ) -> AmbientBehaviour {
    switch state {
    case .awake:
      return .oneShot(.blink, after: pause(in: awakeBlinkSeconds, using: &generator))
    case .drowsy:
      return .oneShot(.slowBlink, after: pause(in: drowsyBlinkSeconds, using: &generator))
    case .yawning:
      return .oneShot(.yawnAndNod, after: pause(in: yawnSeconds, using: &generator))
    case .noddingOff:
      return .loop(.floatingZs)
    case .asleep:
      return .loop(.snore)
    }
  }

  private static func pause(
    in seconds: ClosedRange<Double>,
    using generator: inout some RandomNumberGenerator
  ) -> Duration {
    .seconds(Double.random(in: seconds, using: &generator))
  }
}
