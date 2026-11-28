/// The battery line at the top of the menu, such as "63% · Discharging · Drowsy".
public enum StatusLine {
  /// Returns the menu's battery line for `tracker`, with " · Low Power" appended when Low Power
  /// Mode is on.
  ///
  /// - Parameters:
  ///   - tracker: The battery's tracker, or `nil` when the Mac has no battery.
  ///   - isLowPowerModeOn: Whether Low Power Mode is on.
  /// - Returns: The line, or "No battery detected" when there is no tracker.
  public static func text(for tracker: DrowsinessTracker?, isLowPowerModeOn: Bool) -> String {
    guard let tracker else { return "No battery detected" }

    var parts = [
      "\(tracker.reading.percentage)%",
      label(for: tracker.reading.powerState),
      label(for: tracker.phase),
    ]
    if isLowPowerModeOn {
      parts.append("Low Power")
    }
    return parts.joined(separator: " · ")
  }

  private static func label(for powerState: BatteryReading.PowerState) -> String {
    switch powerState {
    case .discharging: "Discharging"
    case .charging: "Charging"
    case .pluggedIn: "Plugged in"
    }
  }

  private static func label(for phase: DrowsinessTracker.Phase) -> String {
    switch phase {
    case .discharging(.awake), .onExternalPower: "Awake"
    case .discharging(.drowsy): "Drowsy"
    case .discharging(.yawning): "Yawning"
    case .discharging(.noddingOff): "Nodding off"
    case .discharging(.asleep): "Asleep"
    case .waking: "Waking"
    }
  }
}
