import SleepyBatteryCore
import XCTest

final class StatusLineTests: XCTestCase {
  func testDischargingShowsPercentagePowerStateAndMood() {
    let tracker = DrowsinessTracker(
      reading: BatteryReading(percentage: 63, powerState: .discharging),
      thresholds: Thresholds(
        drowsyBelow: 70, yawningBelow: 30, noddingOffBelow: 20, asleepBelow: 10)!
    )

    XCTAssertEqual(
      StatusLine.text(for: tracker, isLowPowerModeOn: false),
      "63% · Discharging · Drowsy"
    )
  }

  func testLowPowerModeIsAppended() {
    let tracker = DrowsinessTracker(
      reading: BatteryReading(percentage: 15, powerState: .discharging)
    )

    XCTAssertEqual(
      StatusLine.text(for: tracker, isLowPowerModeOn: true),
      "15% · Discharging · Nodding off · Low Power"
    )
  }

  func testWakingAfterPluggingIn() {
    var tracker = DrowsinessTracker(
      reading: BatteryReading(percentage: 31, powerState: .discharging)
    )
    tracker.update(BatteryReading(percentage: 31, powerState: .charging))

    XCTAssertEqual(
      StatusLine.text(for: tracker, isLowPowerModeOn: false),
      "31% · Charging · Waking"
    )
  }

  func testPluggedInAndFull() {
    let tracker = DrowsinessTracker(
      reading: BatteryReading(percentage: 100, powerState: .pluggedIn)
    )

    XCTAssertEqual(
      StatusLine.text(for: tracker, isLowPowerModeOn: false),
      "100% · Plugged in · Awake"
    )
  }

  func testEveryDischargingStateHasALabel() {
    let labels = [80, 40, 25, 15, 5].map { percentage in
      StatusLine.text(
        for: DrowsinessTracker(
          reading: BatteryReading(percentage: percentage, powerState: .discharging)
        ),
        isLowPowerModeOn: false
      )
    }

    XCTAssertEqual(
      labels,
      [
        "80% · Discharging · Awake",
        "40% · Discharging · Drowsy",
        "25% · Discharging · Yawning",
        "15% · Discharging · Nodding off",
        "5% · Discharging · Asleep",
      ]
    )
  }

  func testNoBattery() {
    XCTAssertEqual(
      StatusLine.text(for: DrowsinessTracker(reading: nil), isLowPowerModeOn: true),
      "No battery detected"
    )
  }
}
