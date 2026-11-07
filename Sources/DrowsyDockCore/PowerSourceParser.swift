/// Parses the power source descriptions IOKit returns into a battery reading.
///
/// The input is one dictionary per power source, as `IOPSGetPowerSourceDescription` returns for
/// each entry of `IOPSCopyPowerSourcesList`. The keys are the string values of the `kIOPS…Key`
/// constants from `IOKit/ps/IOPSKeys.h`, repeated here so that this module needs no IOKit import.
public enum PowerSourceParser {
  private enum Key {
    static let type = "Type"
    static let isPresent = "Is Present"
    static let currentCapacity = "Current Capacity"
    static let maxCapacity = "Max Capacity"
    static let powerSourceState = "Power Source State"
    static let isCharging = "Is Charging"
  }

  private enum Value {
    static let internalBattery = "InternalBattery"
    static let acPower = "AC Power"
    static let batteryPower = "Battery Power"
  }

  /// Returns the reading for the first internal battery that is present, or `nil` when there is
  /// none or its description lacks a usable capacity or power state. A capacity outside
  /// 0...max capacity is clamped into it.
  public static func reading(from descriptions: [[String: Any]]) -> BatteryReading? {
    let battery = descriptions.first { description in
      description[Key.type] as? String == Value.internalBattery
        && description[Key.isPresent] as? Bool != false
    }
    guard
      let battery,
      let currentCapacity = battery[Key.currentCapacity] as? Int,
      let maxCapacity = battery[Key.maxCapacity] as? Int,
      overflowSafeMaxCapacities.contains(maxCapacity),
      let powerState = powerState(of: battery)
    else { return nil }

    return BatteryReading(
      clampingPercentage: roundedPercentage(of: currentCapacity, outOf: maxCapacity),
      powerState: powerState
    )
  }

  /// `roundedPercentage` computes at most `maxCapacity * 101`, which fits in an `Int` for these.
  private static let overflowSafeMaxCapacities = 1...(Int.max / 101)

  private static func roundedPercentage(of capacity: Int, outOf maxCapacity: Int) -> Int {
    let clampedCapacity = min(max(capacity, 0), maxCapacity)
    return (clampedCapacity * 100 + maxCapacity / 2) / maxCapacity
  }

  private static func powerState(of battery: [String: Any]) -> BatteryReading.PowerState? {
    switch battery[Key.powerSourceState] as? String {
    case Value.batteryPower:
      return .discharging
    case Value.acPower:
      return battery[Key.isCharging] as? Bool == true ? .charging : .pluggedIn
    default:
      return nil
    }
  }
}
