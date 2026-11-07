/// Decides when the whole Dock nods off: once per discharge cycle, as the cat first falls asleep.
///
/// The rule is armed at the start of a discharge cycle. Being in `asleep` uses it up, whether the
/// effect played or was suppressed, so staying asleep never replays it. Only AC power arms it
/// again.
public struct CrowdEffectRule: Equatable, Sendable {
  private var isArmed = true

  /// Creates the rule for an app that starts in `phase`. Starting asleep counts as this cycle's
  /// entry, so the effect waits for the next cycle.
  public init(startingIn phase: DrowsinessTracker.Phase) {
    record(phase)
  }

  /// Records a change of the tracker's phase, and returns whether the effect plays now.
  ///
  /// - Parameters:
  ///   - phase: The new phase.
  ///   - isEnabled: Whether the user has the effect turned on.
  ///   - quietHours: Whether quiet hours are on now.
  public mutating func phaseChanged(
    to phase: DrowsinessTracker.Phase,
    isEnabled: Bool = true,
    quietHours: Bool = false
  ) -> Bool {
    let plays = phase == .discharging(.asleep) && isArmed && isEnabled && !quietHours
    record(phase)
    return plays
  }

  /// Records a jump to `phase` after the Mac wakes from sleep. The effect never plays for it, and
  /// a jump into `asleep` uses up the cycle.
  public mutating func resynced(to phase: DrowsinessTracker.Phase) {
    record(phase)
  }

  private mutating func record(_ phase: DrowsinessTracker.Phase) {
    switch phase {
    case .waking, .onExternalPower:
      isArmed = true
    case .discharging(.asleep):
      isArmed = false
    case .discharging, .noBattery:
      break
    }
  }
}
