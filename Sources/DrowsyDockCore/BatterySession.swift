/// Feeds one `DrowsinessTracker` from either the real battery or the Debug simulator.
///
/// Real readings and simulated ones reach the tracker through the same calls, so the simulator
/// shows exactly what a real battery at that level would.
public struct BatterySession: Sendable, Equatable {
  /// The tracker both sources drive, or `nil` while the battery shown is missing.
  public private(set) var tracker: DrowsinessTracker?

  /// The active simulator choice.
  public private(set) var simulation: BatterySimulation = .real

  private var realReading: BatteryReading?
  private let thresholds: Thresholds

  /// Creates a session showing the real battery.
  public init(realReading: BatteryReading?, thresholds: Thresholds = .default) {
    self.realReading = realReading
    self.thresholds = thresholds
    tracker = realReading.map { DrowsinessTracker(reading: $0, thresholds: thresholds) }
  }

  /// Records a reading from the real battery. The tracker sees it only while `simulation` is
  /// `.real`.
  public mutating func receive(_ reading: BatteryReading?) {
    realReading = reading
    guard simulation == .real else { return }
    tracker = updated(tracker, with: reading)
  }

  /// Switches the simulator choice.
  ///
  /// A switch is a jump rather than a discharge, so a discharging state is derived afresh: picking
  /// 80% after 5% shows `awake`. Switching onto AC power from a discharging state still goes
  /// through the tracker's charge edge and wakes the mascot.
  public mutating func simulate(_ simulation: BatterySimulation) {
    self.simulation = simulation
    let reading = reading(for: simulation)
    if reading?.powerState.isExternal == true {
      tracker = updated(tracker, with: reading)
    } else {
      tracker = reading.map { DrowsinessTracker(reading: $0, thresholds: thresholds) }
    }
  }

  /// Ends the wake-up animation's phase. See `DrowsinessTracker.finishWaking()`.
  public mutating func finishWaking() {
    tracker?.finishWaking()
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

  private func reading(for simulation: BatterySimulation) -> BatteryReading? {
    switch simulation {
    case .real:
      return realReading
    case .discharging(let percentage):
      return BatteryReading(clampingPercentage: percentage, powerState: .discharging)
    case .charging:
      let percentage = tracker?.reading.percentage ?? realReading?.percentage ?? 100
      return BatteryReading(clampingPercentage: percentage, powerState: .charging)
    case .noBattery:
      return nil
    }
  }
}
