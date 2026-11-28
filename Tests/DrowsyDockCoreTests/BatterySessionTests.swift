import DrowsyDockCore
import XCTest

final class BatterySessionTests: XCTestCase {
  private func onBattery(_ percentage: Int) -> BatteryReading {
    BatteryReading(clampingPercentage: percentage, powerState: .discharging)
  }

  private func charging(_ percentage: Int) -> BatteryReading {
    BatteryReading(clampingPercentage: percentage, powerState: .charging)
  }

  // MARK: - Real source

  func testRealReadingsDriveTheTracker() {
    var session = BatterySession(realReading: onBattery(60))

    session.receive(onBattery(25))

    XCTAssertEqual(session.tracker?.phase, .discharging(.yawning))
    XCTAssertEqual(session.tracker?.reading, onBattery(25))
  }

  func testRealReadingsAreHeldBackWhileSimulating() {
    var session = BatterySession(realReading: onBattery(60))
    session.simulate(.discharging(percentage: 40))

    session.receive(onBattery(10))

    XCTAssertEqual(session.tracker?.phase, .discharging(.drowsy))
    XCTAssertEqual(session.tracker?.reading, onBattery(40))
  }

  func testReturningToRealShowsTheLatestRealReading() {
    var session = BatterySession(realReading: onBattery(60))
    session.simulate(.discharging(percentage: 5))
    session.receive(onBattery(58))

    session.simulate(.real)

    XCTAssertEqual(session.tracker?.phase, .discharging(.awake))
    XCTAssertEqual(session.tracker?.reading, onBattery(58))
  }

  func testLosingTheRealBatteryLeavesNoTracker() {
    var session = BatterySession(realReading: onBattery(40))

    session.receive(nil)

    XCTAssertNil(session.tracker)
  }

  func testARealBatteryThatAppearsOnACPowerDoesNotWake() {
    var session = BatterySession(realReading: nil)

    session.receive(charging(80))

    XCTAssertEqual(session.tracker?.phase, .onExternalPower)
  }

  func testARealBatteryThatAppearsOnBatteryStartsAtItsDerivedState() {
    var session = BatterySession(realReading: nil)

    session.receive(onBattery(25))

    XCTAssertEqual(session.tracker?.phase, .discharging(.yawning))
  }

  // MARK: - Simulated levels

  func testEachSimulatedLevelShowsItsSpecState() {
    let expected: [(percentage: Int, state: DrowsinessState)] = [
      (80, .awake),
      (40, .drowsy),
      (25, .yawning),
      (15, .noddingOff),
      (5, .asleep),
    ]
    var session = BatterySession(realReading: onBattery(60))

    for (percentage, state) in expected {
      session.simulate(.discharging(percentage: percentage))

      XCTAssertEqual(session.tracker?.phase, .discharging(state), "\(percentage)%")
    }
  }

  func testSwitchingToAHigherSimulatedLevelRederivesInsteadOfStayingSleepier() {
    var session = BatterySession(realReading: onBattery(60))
    session.simulate(.discharging(percentage: 5))

    session.simulate(.discharging(percentage: 80))

    XCTAssertEqual(session.tracker?.phase, .discharging(.awake))
  }

  func testSimulatedLevelsUseTheSessionsThresholds() {
    var session = BatterySession(
      realReading: onBattery(70),
      thresholds: Thresholds(
        drowsyBelow: 60, yawningBelow: 50, noddingOffBelow: 40, asleepBelow: 30)!
    )

    session.simulate(.discharging(percentage: 45))

    XCTAssertEqual(session.tracker?.phase, .discharging(.yawning))
  }

  func testSimulatingNoBatteryLeavesNoTracker() {
    var session = BatterySession(realReading: onBattery(60))

    session.simulate(.noBattery)

    XCTAssertNil(session.tracker)
  }

  // MARK: - Simulated charging

  func testSimulatedChargingWakesAtTheCurrentPercentageThenSettles() {
    var session = BatterySession(realReading: onBattery(60))
    session.simulate(.discharging(percentage: 5))

    session.simulate(.charging)
    let afterPlugIn = session.tracker?.phase
    session.finishWaking()

    XCTAssertEqual(afterPlugIn, .waking)
    XCTAssertEqual(session.tracker?.reading, charging(5))
    XCTAssertEqual(session.tracker?.phase, .onExternalPower)
  }

  func testSimulatedChargingWithNoBatteryAnywhereChargesAtOneHundredPercent() {
    var session = BatterySession(realReading: nil)

    session.simulate(.charging)

    XCTAssertEqual(session.tracker?.reading, charging(100))
    XCTAssertEqual(session.tracker?.phase, .onExternalPower)
  }

  func testSimulatedChargingAfterNoBatteryUsesTheRealPercentage() {
    var session = BatterySession(realReading: onBattery(60))
    session.simulate(.noBattery)

    session.simulate(.charging)

    XCTAssertEqual(session.tracker?.reading, charging(60))
  }

  // MARK: - Returning to Real

  func testReturningToRealKeepsTheRealBatterysHistory() {
    var session = BatterySession(realReading: onBattery(51))
    session.receive(onBattery(49))
    session.receive(onBattery(50))
    session.simulate(.discharging(percentage: 80))

    session.simulate(.real)

    XCTAssertEqual(session.tracker?.phase, .discharging(.drowsy))
    XCTAssertEqual(session.tracker?.reading, onBattery(50))
  }

  func testRealReadingsWhileSimulatingStillOnlyMakeTheRealBatterySleepier() {
    var session = BatterySession(realReading: onBattery(60))
    session.simulate(.discharging(percentage: 80))
    session.receive(onBattery(25))
    session.receive(onBattery(35))

    session.simulate(.real)

    XCTAssertEqual(session.tracker?.phase, .discharging(.yawning))
  }

  func testReturningToRealWhileTheMacIsPluggedInShowsItAwakeWithoutAWakeUp() {
    var session = BatterySession(realReading: charging(50))
    session.simulate(.discharging(percentage: 5))

    session.simulate(.real)

    XCTAssertEqual(session.tracker?.phase, .onExternalPower)
  }

  func testPluggingInWhileSimulatingSettlesTheRealBatteryWithoutAWakeUp() {
    var session = BatterySession(realReading: onBattery(40))
    session.simulate(.discharging(percentage: 5))
    session.receive(charging(40))

    session.simulate(.real)

    XCTAssertEqual(session.tracker?.phase, .onExternalPower)
  }

  func testFinishingTheWakeUpWhileRealIsShownSettlesTheRealBattery() {
    var session = BatterySession(realReading: onBattery(40))
    session.receive(charging(40))

    session.finishWaking()

    XCTAssertEqual(session.tracker?.phase, .onExternalPower)
  }

  func testPickingRealAgainDuringItsWakeUpKeepsWaking() {
    var session = BatterySession(realReading: onBattery(40))
    session.receive(charging(40))

    session.simulate(.real)

    XCTAssertEqual(session.tracker?.phase, .waking)
  }

  func testLeavingRealDuringTheWakeUpSettlesIt() {
    var session = BatterySession(realReading: onBattery(40))
    session.receive(charging(40))
    session.simulate(.discharging(percentage: 80))

    session.simulate(.real)

    XCTAssertEqual(session.tracker?.phase, .onExternalPower)
  }

  // MARK: - Resync after the Mac wakes

  func testAResyncFromAwakeToAsleepGoesStraightToAsleep() {
    var session = BatterySession(realReading: onBattery(80))

    session.resync(onBattery(5))

    XCTAssertEqual(session.tracker?.phase, .discharging(.asleep))
    XCTAssertEqual(session.tracker?.reading, onBattery(5))
  }

  func testAResyncDerivesAfreshEvenWhenThatIsLessSleepy() {
    var session = BatterySession(realReading: onBattery(5))

    session.resync(onBattery(80))

    XCTAssertEqual(session.tracker?.phase, .discharging(.awake))
  }

  func testAResyncOntoACPowerIsAwakeWithoutAWakeUp() {
    var session = BatterySession(realReading: onBattery(5))

    session.resync(charging(5))

    XCTAssertEqual(session.tracker?.phase, .onExternalPower)
  }

  func testAResyncWithNoBatteryLeavesNoTracker() {
    var session = BatterySession(realReading: onBattery(40))

    session.resync(nil)

    XCTAssertNil(session.tracker)
  }

  func testAResyncWhileSimulatingChangesOnlyTheRealBattery() {
    var session = BatterySession(realReading: onBattery(80))
    session.simulate(.discharging(percentage: 40))

    session.resync(onBattery(5))
    let whileSimulating = session.tracker?.phase
    session.simulate(.real)

    XCTAssertEqual(whileSimulating, .discharging(.drowsy))
    XCTAssertEqual(session.tracker?.phase, .discharging(.asleep))
  }

  // MARK: - Menu

  func testMenuOffersTheSpecChoicesInOrder() {
    XCTAssertEqual(
      BatterySimulation.menuChoices.map(\.title),
      ["Real", "80%", "40%", "25%", "15%", "5%", "Charging", "No battery"]
    )
  }
}
