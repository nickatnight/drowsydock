/// Keeps one `DrowsinessTracker` for the real battery and one for the Debug simulator, and shows
/// one of them.
///
/// The real battery's tracker sees every real reading, even while the simulator is shown, so
/// returning to Real shows its own history. The simulator's tracker takes the same calls, so it
/// shows exactly what a real battery at that level would.
public struct BatterySession: Sendable, Equatable {
  /// The active simulator choice.
  public private(set) var simulation: BatterySimulation = .real

  private var real: DrowsinessTracker?
  private var simulated: DrowsinessTracker?
  private let thresholds: Thresholds

  /// Creates a session showing the real battery.
  public init(realReading: BatteryReading?, thresholds: Thresholds = .default) {
    self.thresholds = thresholds
    real = realReading.map { DrowsinessTracker(reading: $0, thresholds: thresholds) }
  }

  /// The tracker shown: the real battery's, or the simulator's while `simulation` isn't `.real`.
  /// `nil` while the battery shown is missing.
  public var tracker: DrowsinessTracker? {
    simulation == .real ? real : simulated
  }

  /// Records a reading from the real battery.
  public mutating func receive(_ reading: BatteryReading?) {
    real = updated(real, with: reading)
    settleHiddenWakeUp()
  }

  /// Switches the simulator choice.
  ///
  /// Picking a level is a jump rather than a discharge, so its state is derived afresh: 80% after
  /// 5% shows `awake`. Picking Charging from a discharging state goes through the tracker's charge
  /// edge and wakes the mascot. Picking Real shows the real battery's tracker as it is.
  public mutating func simulate(_ simulation: BatterySimulation) {
    let shown = tracker
    self.simulation = simulation
    switch simulation {
    case .real, .noBattery:
      simulated = nil
    case .discharging(let percentage):
      simulated = DrowsinessTracker(
        reading: BatteryReading(clampingPercentage: percentage, powerState: .discharging),
        thresholds: thresholds
      )
    case .charging:
      let percentage = shown?.reading.percentage ?? real?.reading.percentage ?? 100
      simulated = updated(
        shown,
        with: BatteryReading(clampingPercentage: percentage, powerState: .charging)
      )
    }
    settleHiddenWakeUp()
  }

  /// Ends the shown tracker's wake-up. See `DrowsinessTracker.finishWaking()`.
  public mutating func finishWaking() {
    if simulation == .real {
      real?.finishWaking()
    } else {
      simulated?.finishWaking()
    }
  }

  // A battery that appears starts a fresh tracker, so it never wakes the mascot; one that goes
  // leaves none.
  private func updated(
    _ tracker: DrowsinessTracker?,
    with reading: BatteryReading?
  ) -> DrowsinessTracker? {
    guard let reading else { return nil }
    guard var tracker else { return DrowsinessTracker(reading: reading, thresholds: thresholds) }
    tracker.update(reading)
    return tracker
  }

  // Nobody sees the real battery's wake-up while the simulator is shown, and the app ends only the
  // shown tracker's, so a hidden one settles at once.
  private mutating func settleHiddenWakeUp() {
    guard simulation != .real else { return }
    real?.finishWaking()
  }
}
