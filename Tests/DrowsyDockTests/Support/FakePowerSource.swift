import DrowsyDockCore

@testable import DrowsyDock

/// A battery the test sets, standing in for IOKit. `change(to:)` reports a new reading the way the
/// IOKit notification does.
@MainActor
final class FakePowerSource: PowerSource {
  var reading: BatteryReading?
  var isLowPowerModeOn = false
  private var onChange: (@MainActor @Sendable () -> Void)?

  init(_ reading: BatteryReading?) {
    self.reading = reading
  }

  func readBattery() -> BatteryReading? {
    reading
  }

  func subscribe(onChange: @escaping @MainActor @Sendable () -> Void) throws -> AnyObject {
    self.onChange = onChange
    return self
  }

  func change(to reading: BatteryReading?, lowPowerMode: Bool = false) {
    self.reading = reading
    isLowPowerModeOn = lowPowerMode
    onChange?()
  }
}
