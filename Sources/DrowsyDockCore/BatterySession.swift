/// Keeps one `DrowsinessTracker` for the real battery and one for the Debug simulator, and shows
/// one of them.
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
  ///
  /// - Parameter reading: The reading, or `nil` when the Mac reports no battery.
  public mutating func receive(_ reading: BatteryReading?) {
    real = updated(real, with: reading)
  }

  /// Records a reading from the real battery taken after the Mac woke from sleep.
  ///
  /// Anything may have happened to the battery during sleep, including a charge, so the real
  /// battery's state is derived afresh, as at launch: on AC power it is awake without a wake-up.
  ///
  /// - Parameter reading: The reading taken after the wake, or `nil` when the Mac reports no
  ///   battery.
  public mutating func resync(_ reading: BatteryReading?) {
    real = reading.map { DrowsinessTracker(reading: $0, thresholds: thresholds) }
  }

  /// Switches the simulator choice.
  ///
  /// Picking a level is a jump rather than a discharge, so its state is derived afresh: 80% after
  /// 5% shows `awake`. Picking Charging from a discharging state goes through the tracker's charge
  /// edge and wakes the mascot. Picking Real shows the real battery's tracker with any wake-up it
  /// had while hidden already over, since nobody saw it.
  ///
  /// - Parameter simulation: The Debug menu's choice.
  public mutating func simulate(_ simulation: BatterySimulation) {
    let shown = tracker
    let realWasHidden = self.simulation != .real
    self.simulation = simulation
    switch simulation {
    case .real:
      simulated = nil
      if realWasHidden {
        real?.finishWaking()
      }
    case .noBattery:
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
  }

  /// Ends the shown tracker's wake-up. See `DrowsinessTracker.finishWaking()`.
  public mutating func finishWaking() {
    if simulation == .real {
      real?.finishWaking()
    } else {
      simulated?.finishWaking()
    }
  }

  private func updated(
    _ tracker: DrowsinessTracker?,
    with reading: BatteryReading?
  ) -> DrowsinessTracker? {
    guard let reading else { return nil }
    guard var tracker else { return DrowsinessTracker(reading: reading, thresholds: thresholds) }
    tracker.update(reading)
    return tracker
  }
}
