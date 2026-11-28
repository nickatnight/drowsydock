import DrowsyDockCore
import XCTest

final class DrowsinessTrackerTests: XCTestCase {
  private func onBattery(_ percentage: Int) -> BatteryReading {
    BatteryReading(clampingPercentage: percentage, powerState: .discharging)
  }

  private func charging(_ percentage: Int) -> BatteryReading {
    BatteryReading(clampingPercentage: percentage, powerState: .charging)
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

    var phases: [DrowsinessTracker.Phase] = []
    for percentage in [49, 50, 49, 51] {
      tracker.update(onBattery(percentage))
      phases.append(tracker.phase)
    }

    XCTAssertEqual(phases, Array(repeating: .discharging(.drowsy), count: 4))
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

  func testLargeUpwardJumpsWhileDischargingNeverWakeTheMascot() {
    let jumps: [(from: Int, to: Int, state: DrowsinessState)] = [
      (9, 60, .asleep),
      (49, 100, .drowsy),
    ]

    for (from, to, state) in jumps {
      var tracker = DrowsinessTracker(reading: onBattery(from))

      tracker.update(onBattery(to))

      XCTAssertEqual(tracker.phase, .discharging(state), "\(from)% then \(to)%")
    }
  }

  func testEveryPairOfDischargingReadingsKeepsTheSleepierState() {
    for first in 0...100 {
      for second in 0...100 {
        var tracker = DrowsinessTracker(reading: onBattery(first))

        tracker.update(onBattery(second))

        let sleepier = max(
          DrowsinessState(percentage: first, thresholds: .default),
          DrowsinessState(percentage: second, thresholds: .default)
        )
        guard tracker.phase == .discharging(sleepier) else {
          XCTFail("\(first)% then \(second)% gave \(tracker.phase), expected \(sleepier)")
          return
        }
      }
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
    tracker.update(BatteryReading(clampingPercentage: 100, powerState: .pluggedIn))

    XCTAssertEqual(afterEdge, .waking)
    XCTAssertEqual(whileStillWaking, .waking)
    XCTAssertEqual(afterWaking, .onExternalPower)
    XCTAssertEqual(tracker.phase, .onExternalPower)
  }

  func testPluggingInWakesWhetherTheBatteryChargesOrIsHeld() {
    let powerStates: [BatteryReading.PowerState] = [.charging, .pluggedIn]

    for powerState in powerStates {
      var tracker = DrowsinessTracker(reading: onBattery(85))

      tracker.update(BatteryReading(clampingPercentage: 85, powerState: powerState))
      let afterEdge = tracker.phase
      tracker.finishWaking()

      XCTAssertEqual(afterEdge, .waking, "\(powerState)")
      XCTAssertEqual(tracker.phase, .onExternalPower, "\(powerState)")
    }
  }

  func testBatteryFillingUpDuringWakingKeepsWaking() {
    var tracker = DrowsinessTracker(reading: onBattery(99))
    tracker.update(charging(99))

    tracker.update(BatteryReading(clampingPercentage: 100, powerState: .pluggedIn))

    XCTAssertEqual(tracker.phase, .waking)
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

  // MARK: - Threshold changes

  func testThresholdChangeRederivesUpward() {
    var tracker = DrowsinessTracker(reading: onBattery(45))
    let lower = Thresholds(drowsyBelow: 40, yawningBelow: 30, noddingOffBelow: 20, asleepBelow: 10)!

    tracker.setThresholds(lower)

    XCTAssertEqual(tracker.phase, .discharging(.awake))
    XCTAssertEqual(tracker.thresholds, lower)
  }

  func testThresholdChangeRederivesDownward() {
    var tracker = DrowsinessTracker(reading: onBattery(55))

    tracker.setThresholds(
      Thresholds(drowsyBelow: 60, yawningBelow: 30, noddingOffBelow: 20, asleepBelow: 10)!)

    XCTAssertEqual(tracker.phase, .discharging(.drowsy))
  }

  func testNewThresholdsApplyToLaterReadings() {
    var tracker = DrowsinessTracker(reading: onBattery(70))
    tracker.setThresholds(
      Thresholds(drowsyBelow: 60, yawningBelow: 50, noddingOffBelow: 40, asleepBelow: 30)!)

    tracker.update(onBattery(45))

    XCTAssertEqual(tracker.phase, .discharging(.yawning))
  }

  func testThresholdChangeWhileWakingKeepsWaking() {
    var tracker = DrowsinessTracker(reading: onBattery(15))
    tracker.update(charging(15))

    tracker.setThresholds(
      Thresholds(drowsyBelow: 90, yawningBelow: 80, noddingOffBelow: 70, asleepBelow: 60)!)

    XCTAssertEqual(tracker.phase, .waking)
  }

  func testThresholdChangeOnExternalPowerStaysAwake() {
    var tracker = DrowsinessTracker(reading: charging(15))

    tracker.setThresholds(
      Thresholds(drowsyBelow: 90, yawningBelow: 80, noddingOffBelow: 70, asleepBelow: 60)!)

    XCTAssertEqual(tracker.phase, .onExternalPower)
  }
}
