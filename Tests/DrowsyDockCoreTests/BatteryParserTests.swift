import DrowsyDockCore
import Foundation
import XCTest

final class BatteryParserTests: XCTestCase {
  // Shaped like `IOPSGetPowerSourceDescription` output on a MacBook (macOS 27, Apple silicon).
  private let laptopDischarging: [String: Any] = [
    "Battery Provides Time Remaining": true,
    "Current": 0,
    "Current Capacity": 31,
    "DesignCycleCount": 300,
    "Is Charging": false,
    "Is Present": true,
    "LPM Active": false,
    "Max Capacity": 100,
    "Name": "InternalBattery-0",
    "Power Source ID": 23_199_843,
    "Power Source State": "Battery Power",
    "Time to Empty": 128,
    "Time to Full Charge": 0,
    "Transport Type": "Internal",
    "Type": "InternalBattery",
  ]

  private let laptopCharging: [String: Any] = [
    "Current Capacity": 62,
    "Is Charging": true,
    "Is Present": true,
    "Max Capacity": 100,
    "Name": "InternalBattery-0",
    "Power Source State": "AC Power",
    "Time to Full Charge": 54,
    "Transport Type": "Internal",
    "Type": "InternalBattery",
  ]

  private let laptopOnACFull: [String: Any] = [
    "Current Capacity": 100,
    "Is Charged": true,
    "Is Charging": false,
    "Is Present": true,
    "Max Capacity": 100,
    "Name": "InternalBattery-0",
    "Power Source State": "AC Power",
    "Transport Type": "Internal",
    "Type": "InternalBattery",
  ]

  private let upsOnDesktop: [String: Any] = [
    "Current Capacity": 100,
    "Is Charging": false,
    "Is Present": true,
    "Max Capacity": 100,
    "Name": "Back-UPS",
    "Power Source State": "AC Power",
    "Transport Type": "USB",
    "Type": "UPS",
  ]

  // MARK: - Fixtures

  func testLaptopDischarging() {
    XCTAssertEqual(
      PowerSourceParser.reading(from: [laptopDischarging]),
      BatteryReading(percentage: 31, powerState: .discharging)
    )
  }

  func testLaptopCharging() {
    XCTAssertEqual(
      PowerSourceParser.reading(from: [laptopCharging]),
      BatteryReading(percentage: 62, powerState: .charging)
    )
  }

  func testLaptopOnACAndFull() {
    XCTAssertEqual(
      PowerSourceParser.reading(from: [laptopOnACFull]),
      BatteryReading(percentage: 100, powerState: .pluggedIn)
    )
  }

  func testDesktopWithNoPowerSources() {
    XCTAssertNil(PowerSourceParser.reading(from: []))
  }

  func testDesktopWithOnlyAUPS() {
    XCTAssertNil(PowerSourceParser.reading(from: [upsOnDesktop]))
  }

  // MARK: - Choosing the battery

  func testPicksTheInternalBatteryWhenAUPSComesFirst() {
    XCTAssertEqual(
      PowerSourceParser.reading(from: [upsOnDesktop, laptopDischarging]),
      BatteryReading(percentage: 31, powerState: .discharging)
    )
  }

  func testIgnoresABatteryThatIsNotPresent() {
    var removed = laptopDischarging
    removed["Is Present"] = false

    XCTAssertNil(PowerSourceParser.reading(from: [removed]))
  }

  func testTreatsAMissingIsPresentKeyAsPresent() {
    var raw = laptopDischarging
    raw["Is Present"] = nil

    XCTAssertEqual(
      PowerSourceParser.reading(from: [raw]),
      BatteryReading(percentage: 31, powerState: .discharging)
    )
  }

  func testTreatsACPowerWithoutAnIsChargingKeyAsPluggedIn() {
    var raw = laptopOnACFull
    raw["Is Charging"] = nil

    XCTAssertEqual(PowerSourceParser.reading(from: [raw])?.powerState, .pluggedIn)
  }

  // MARK: - Values

  func testReadsNSNumberValuesAsIOKitDeliversThem() {
    let bridged: NSDictionary = [
      "Current Capacity": NSNumber(value: 47),
      "Is Charging": kCFBooleanFalse as Any,
      "Is Present": kCFBooleanTrue as Any,
      "Max Capacity": NSNumber(value: 100),
      "Power Source State": "Battery Power" as NSString,
      "Type": "InternalBattery" as NSString,
    ]

    XCTAssertEqual(
      PowerSourceParser.reading(from: [bridged as! [String: Any]]),
      BatteryReading(percentage: 47, powerState: .discharging)
    )
  }

  func testScalesCapacityWhenMaxCapacityIsNotOneHundred() {
    var raw = laptopDischarging
    raw["Current Capacity"] = 4_000
    raw["Max Capacity"] = 5_000

    XCTAssertEqual(PowerSourceParser.reading(from: [raw])?.percentage, 80)
  }

  func testRoundsToTheNearestPercent() {
    var raw = laptopDischarging
    raw["Current Capacity"] = 2
    raw["Max Capacity"] = 3

    XCTAssertEqual(PowerSourceParser.reading(from: [raw])?.percentage, 67)
  }

  func testClampsCapacityAboveMaxToOneHundred() {
    var raw = laptopOnACFull
    raw["Current Capacity"] = 103

    XCTAssertEqual(PowerSourceParser.reading(from: [raw])?.percentage, 100)
  }

  func testAnAbsurdCurrentCapacityClampsInsteadOfOverflowing() {
    var raw = laptopDischarging
    raw["Current Capacity"] = Int.max

    XCTAssertEqual(PowerSourceParser.reading(from: [raw])?.percentage, 100)
  }

  func testRejectsAnAbsurdMaxCapacityInsteadOfOverflowing() {
    var raw = laptopDischarging
    raw["Current Capacity"] = Int.max / 2
    raw["Max Capacity"] = Int.max

    XCTAssertNil(PowerSourceParser.reading(from: [raw]))
  }

  func testRejectsAZeroMaxCapacity() {
    var raw = laptopDischarging
    raw["Max Capacity"] = 0

    XCTAssertNil(PowerSourceParser.reading(from: [raw]))
  }

  func testRejectsAMissingCapacity() {
    var raw = laptopDischarging
    raw["Current Capacity"] = nil

    XCTAssertNil(PowerSourceParser.reading(from: [raw]))
  }

  func testRejectsAnUnknownPowerSourceState() {
    var raw = laptopDischarging
    raw["Power Source State"] = "Off Line"

    XCTAssertNil(PowerSourceParser.reading(from: [raw]))
  }
}
