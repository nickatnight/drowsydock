import DrowsyDockCore
import XCTest

final class BatteryReadingTests: XCTestCase {
  func testClampingInitPinsPercentagesIntoZeroToOneHundred() {
    XCTAssertEqual(BatteryReading(clampingPercentage: -4, powerState: .discharging).percentage, 0)
    XCTAssertEqual(BatteryReading(clampingPercentage: 57, powerState: .discharging).percentage, 57)
    XCTAssertEqual(BatteryReading(clampingPercentage: 104, powerState: .charging).percentage, 100)
  }

  func testOnlyDischargingIsOffExternalPower() {
    XCTAssertFalse(BatteryReading.PowerState.discharging.isExternal)
    XCTAssertTrue(BatteryReading.PowerState.charging.isExternal)
    XCTAssertTrue(BatteryReading.PowerState.pluggedIn.isExternal)
  }
}
