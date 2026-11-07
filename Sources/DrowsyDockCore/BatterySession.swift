/// Feeds one `DrowsinessTracker` from either the real battery or the Debug simulator.
///
/// Real readings and simulated ones reach the tracker through the same calls, so the simulator
/// shows exactly what a real battery at that level would.
public struct BatterySession: Sendable, Equatable {
  /// The tracker both sources drive.
  public private(set) var tracker: DrowsinessTracker

  /// The active simulator choice.
  public private(set) var simulation: BatterySimulation = .real

  private var realReading: BatteryReading?

  /// Creates a session showing the real battery.
  public init(realReading: BatteryReading?, thresholds: Thresholds = .default) {
    self.realReading = realReading
    self.tracker = DrowsinessTracker(reading: realReading, thresholds: thresholds)
  }

  /// Records a reading from the real battery. The tracker sees it only while `simulation` is
  /// `.real`.
  public mutating func receive(_ reading: BatteryReading?) {
    realReading = reading
    guard simulation == .real else { return }
    tracker.update(reading)
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
      tracker.update(reading)
    } else {
      tracker = DrowsinessTracker(reading: reading, thresholds: tracker.thresholds)
    }
  }

  /// Ends the wake-up animation's phase. See `DrowsinessTracker.finishWaking()`.
  public mutating func finishWaking() {
    tracker.finishWaking()
  }

  private func reading(for simulation: BatterySimulation) -> BatteryReading? {
    switch simulation {
    case .real:
      return realReading
    case .discharging(let percentage):
      return BatteryReading(clampingPercentage: percentage, powerState: .discharging)
    case .charging:
      let percentage = tracker.reading?.percentage ?? realReading?.percentage ?? 100
      return BatteryReading(clampingPercentage: percentage, powerState: .charging)
    case .noBattery:
      return nil
    }
  }
}
