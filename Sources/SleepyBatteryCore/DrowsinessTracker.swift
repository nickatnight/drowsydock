/// Turns a stream of battery readings into the mascot's phase.
///
/// While discharging, the state only gets sleepier, so a reading that jitters by 1% around a
/// threshold never flips the mascot back up. Plugging in, unplugging after a charge, or changing
/// the thresholds derives the state afresh.
public struct DrowsinessTracker: Sendable, Equatable {
  /// What the mascot is doing.
  public enum Phase: Sendable, Equatable {
    /// The Mac has no internal battery, so there is nothing to show.
    case noBattery
    /// On battery, at the sleepiest state reached during this discharge cycle.
    case discharging(DrowsinessState)
    /// AC power was just connected and the wake-up is playing. `finishWaking()` ends it.
    case waking
    /// On AC power and awake, whatever the percentage.
    case onExternalPower
  }

  /// What the mascot is doing now.
  public private(set) var phase: Phase

  /// The latest reading, or `nil` when the Mac has no battery.
  public private(set) var reading: BatteryReading?

  /// The thresholds the discharging states derive from.
  public private(set) var thresholds: Thresholds

  /// Creates a tracker that starts in the state `reading` derives to, without a wake-up.
  public init(reading: BatteryReading?, thresholds: Thresholds = .default) {
    self.reading = reading
    self.thresholds = thresholds
    self.phase = Self.derivedPhase(for: reading, thresholds: thresholds)
  }

  /// Records a new reading. Pass `nil` when the battery is gone.
  public mutating func update(_ reading: BatteryReading?) {
    self.reading = reading
    guard let reading else {
      phase = .noBattery
      return
    }

    switch (phase, reading.powerState.isExternal) {
    case (.discharging(let sleepiest), false):
      let derived = DrowsinessState(percentage: reading.percentage, thresholds: thresholds)
      phase = .discharging(max(sleepiest, derived))
    case (.discharging, true):
      phase = .waking
    case (.waking, true), (.onExternalPower, true):
      break
    case (.noBattery, _), (.waking, false), (.onExternalPower, false):
      phase = Self.derivedPhase(for: reading, thresholds: thresholds)
    }
  }

  /// Ends the wake-up and settles on `onExternalPower`. Does nothing unless the phase is `waking`.
  public mutating func finishWaking() {
    guard phase == .waking else { return }
    phase = .onExternalPower
  }

  /// Replaces the thresholds and re-derives a discharging state from the latest reading, even if
  /// that makes the mascot less sleepy.
  public mutating func setThresholds(_ thresholds: Thresholds) {
    self.thresholds = thresholds
    guard case .discharging = phase else { return }
    phase = Self.derivedPhase(for: reading, thresholds: thresholds)
  }

  private static func derivedPhase(for reading: BatteryReading?, thresholds: Thresholds) -> Phase {
    guard let reading else { return .noBattery }
    guard !reading.powerState.isExternal else { return .onExternalPower }
    return .discharging(DrowsinessState(percentage: reading.percentage, thresholds: thresholds))
  }
}
