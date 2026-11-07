/// A battery the Debug menu can substitute for the real one, so every state can be seen without
/// draining the battery.
public enum BatterySimulation: Hashable, Sendable {
  /// Use the real battery.
  case real
  /// Pretend to be on battery at `percentage`.
  case discharging(percentage: Int)
  /// Pretend AC power was connected, keeping the percentage shown at the time.
  case charging
  /// Pretend the Mac has no battery.
  case noBattery

  /// The choices in the Debug ▸ Simulate battery menu, in menu order.
  public static let menuChoices: [BatterySimulation] = [
    .real,
    .discharging(percentage: 80),
    .discharging(percentage: 40),
    .discharging(percentage: 25),
    .discharging(percentage: 15),
    .discharging(percentage: 5),
    .charging,
    .noBattery,
  ]

  /// The menu item title.
  public var title: String {
    switch self {
    case .real: "Real"
    case .discharging(let percentage): "\(percentage)%"
    case .charging: "Charging"
    case .noBattery: "No battery"
    }
  }
}
