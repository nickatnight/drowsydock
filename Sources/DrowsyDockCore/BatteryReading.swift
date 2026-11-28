/// One sample of the internal battery: its charge and where its power comes from.
public struct BatteryReading: Sendable, Equatable {
  /// Where the Mac draws power from, as the power source reports it.
  public enum PowerState: Sendable, Equatable {
    case discharging
    case charging
    /// On AC power and not charging, because the battery is full or macOS is holding the charge.
    case pluggedIn

    /// Whether the Mac is connected to AC power.
    public var isExternal: Bool { self != .discharging }
  }

  /// The charge, from 0 to 100.
  public let percentage: Int

  /// Where the Mac draws power from.
  public let powerState: PowerState

  /// Creates a reading with `percentage` clamped into 0...100.
  public init(clampingPercentage percentage: Int, powerState: PowerState) {
    self.percentage = min(max(percentage, 0), 100)
    self.powerState = powerState
  }
}
