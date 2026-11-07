import SleepyBatteryCore
import XCTest

final class BatteryReadingTests: XCTestCase {
  func testAcceptsZeroToOneHundredPercent() {
    XCTAssertNotNil(BatteryReading(percentage: 0, powerState: .discharging))
    XCTAssertNotNil(BatteryReading(percentage: 100, powerState: .pluggedIn))
  }

  func testRejectsPercentagesOutsideZeroToOneHundred() {
    XCTAssertNil(BatteryReading(percentage: -1, powerState: .discharging))
    XCTAssertNil(BatteryReading(percentage: 101, powerState: .charging))
  }

  func testOnlyDischargingIsOffExternalPower() {
    XCTAssertFalse(BatteryReading.PowerState.discharging.isExternal)
    XCTAssertTrue(BatteryReading.PowerState.charging.isExternal)
    XCTAssertTrue(BatteryReading.PowerState.pluggedIn.isExternal)
  }
}
