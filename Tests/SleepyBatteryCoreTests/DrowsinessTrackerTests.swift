import SleepyBatteryCore
import XCTest

final class DrowsinessTrackerTests: XCTestCase {
  private func onBattery(_ percentage: Int) -> BatteryReading {
    BatteryReading(percentage: percentage, powerState: .discharging)!
  }

  private func charging(_ percentage: Int) -> BatteryReading {
    BatteryReading(percentage: percentage, powerState: .charging)!
  }

  // MARK: - Starting state

  func testStartsInTheDerivedStateWhenOnBattery() {
    let tracker = DrowsinessTracker(reading: onBattery(25))

    XCTAssertEqual(tracker.phase, .discharging(.yawning))
  }

  func testStartsAwakeWithoutWakingWhenLaunchedOnExternalPower() {
    let tracker = DrowsinessTracker(reading: charging(5))

    XCTAssertEqual(tracker.phase, .onExternalPower)
  }

  func testStartsWithNoBatteryWhenThereIsNoReading() {
    let tracker = DrowsinessTracker(reading: nil)

    XCTAssertEqual(tracker.phase, .noBattery)
  }

  // MARK: - Discharging

  func testGetsSleepierAsTheBatteryDrains() {
    var tracker = DrowsinessTracker(reading: onBattery(51))

    var phases: [DrowsinessTracker.Phase] = []
    for percentage in [49, 29, 19, 9] {
      tracker.update(onBattery(percentage))
      phases.append(tracker.phase)
    }

    XCTAssertEqual(
      phases,
      [
        .discharging(.drowsy),
        .discharging(.yawning),
        .discharging(.noddingOff),
        .discharging(.asleep),
      ]
    )
  }

  func testOnePercentJitterAroundAThresholdNeverFlipsBackUp() {
    var tracker = DrowsinessTracker(reading: onBattery(50))

    tracker.update(onBattery(49))
    tracker.update(onBattery(50))
    tracker.update(onBattery(49))
    tracker.update(onBattery(51))

    XCTAssertEqual(tracker.phase, .discharging(.drowsy))
  }

  func testJitterAtEveryLowerThresholdNeverFlipsBackUp() {
    let lowSides: [(percentage: Int, state: DrowsinessState)] = [
      (29, .yawning),
      (19, .noddingOff),
      (9, .asleep),
    ]

    for (percentage, state) in lowSides {
      var tracker = DrowsinessTracker(reading: onBattery(percentage))

      tracker.update(onBattery(percentage + 1))

      XCTAssertEqual(tracker.phase, .discharging(state), "\(percentage)% then \(percentage + 1)%")
    }
  }

  func testRecordsTheLatestReadingEvenWhenTheStateHolds() {
    var tracker = DrowsinessTracker(reading: onBattery(49))

    tracker.update(onBattery(50))

    XCTAssertEqual(tracker.reading, onBattery(50))
  }

  // MARK: - Charging

  func testChargeEdgeWakesThenStaysAwakeOnceWakingFinishes() {
    var tracker = DrowsinessTracker(reading: onBattery(5))

    tracker.update(charging(5))
    let afterEdge = tracker.phase
    tracker.update(charging(6))
    let whileStillWaking = tracker.phase
    tracker.finishWaking()
    let afterWaking = tracker.phase
    tracker.update(BatteryReading(percentage: 100, powerState: .pluggedIn)!)

    XCTAssertEqual(afterEdge, .waking)
    XCTAssertEqual(whileStillWaking, .waking)
    XCTAssertEqual(afterWaking, .onExternalPower)
    XCTAssertEqual(tracker.phase, .onExternalPower)
  }

  func testUnpluggingAfterChargingStartsAFreshCycleFromTheDerivedState() {
    var tracker = DrowsinessTracker(reading: onBattery(5))
    tracker.update(charging(5))
    tracker.finishWaking()

    tracker.update(onBattery(60))

    XCTAssertEqual(tracker.phase, .discharging(.awake))
  }

  func testUnpluggingWhileWakingReturnsToTheDerivedState() {
    var tracker = DrowsinessTracker(reading: onBattery(5))
    tracker.update(charging(5))

    tracker.update(onBattery(5))

    XCTAssertEqual(tracker.phase, .discharging(.asleep))
  }

  func testFinishWakingDoesNothingUnlessWaking() {
    var tracker = DrowsinessTracker(reading: onBattery(25))

    tracker.finishWaking()

    XCTAssertEqual(tracker.phase, .discharging(.yawning))
  }

  // MARK: - No battery

  func testLosingTheBatteryReportsNoBattery() {
    var tracker = DrowsinessTracker(reading: onBattery(40))

    tracker.update(nil)

    XCTAssertEqual(tracker.phase, .noBattery)
    XCTAssertNil(tracker.reading)
  }

  func testPluggingInWithNoPriorBatteryDoesNotWake() {
    var tracker = DrowsinessTracker(reading: nil)

    tracker.update(charging(80))

    XCTAssertEqual(tracker.phase, .onExternalPower)
  }

  // MARK: - Threshold changes

  func testThresholdChangeRederivesUpward() {
    var tracker = DrowsinessTracker(reading: onBattery(45))
    let lower = Thresholds(drowsy: 40, yawning: 30, noddingOff: 20, asleep: 10)!

    tracker.setThresholds(lower)

    XCTAssertEqual(tracker.phase, .discharging(.awake))
    XCTAssertEqual(tracker.thresholds, lower)
  }

  func testThresholdChangeRederivesDownward() {
    var tracker = DrowsinessTracker(reading: onBattery(55))

    tracker.setThresholds(Thresholds(drowsy: 60, yawning: 30, noddingOff: 20, asleep: 10)!)

    XCTAssertEqual(tracker.phase, .discharging(.drowsy))
  }

  func testNewThresholdsApplyToLaterReadings() {
    var tracker = DrowsinessTracker(reading: onBattery(70))
    tracker.setThresholds(Thresholds(drowsy: 60, yawning: 50, noddingOff: 40, asleep: 30)!)

    tracker.update(onBattery(45))

    XCTAssertEqual(tracker.phase, .discharging(.yawning))
  }

  func testThresholdChangeOnExternalPowerStaysAwake() {
    var tracker = DrowsinessTracker(reading: charging(15))

    tracker.setThresholds(Thresholds(drowsy: 90, yawning: 80, noddingOff: 70, asleep: 60)!)

    XCTAssertEqual(tracker.phase, .onExternalPower)
  }
}
