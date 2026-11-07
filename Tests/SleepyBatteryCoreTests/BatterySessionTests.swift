import SleepyBatteryCore
import XCTest

final class BatterySessionTests: XCTestCase {
  private func onBattery(_ percentage: Int) -> BatteryReading {
    BatteryReading(percentage: percentage, powerState: .discharging)!
  }

  private func charging(_ percentage: Int) -> BatteryReading {
    BatteryReading(percentage: percentage, powerState: .charging)!
  }

  // MARK: - Real source

  func testRealReadingsDriveTheTracker() {
    var session = BatterySession(realReading: onBattery(60))

    session.receive(onBattery(25))

    XCTAssertEqual(session.tracker.phase, .discharging(.yawning))
    XCTAssertEqual(session.tracker.reading, onBattery(25))
  }

  func testRealReadingsAreHeldBackWhileSimulating() {
    var session = BatterySession(realReading: onBattery(60))
    session.simulate(.discharging(percentage: 40))

    session.receive(onBattery(10))

    XCTAssertEqual(session.tracker.phase, .discharging(.drowsy))
    XCTAssertEqual(session.tracker.reading, onBattery(40))
  }

  func testReturningToRealShowsTheLatestRealReading() {
    var session = BatterySession(realReading: onBattery(60))
    session.simulate(.discharging(percentage: 5))
    session.receive(onBattery(58))

    session.simulate(.real)

    XCTAssertEqual(session.tracker.phase, .discharging(.awake))
    XCTAssertEqual(session.tracker.reading, onBattery(58))
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

      XCTAssertEqual(session.tracker.phase, .discharging(state), "\(percentage)%")
    }
  }

  func testSwitchingToAHigherSimulatedLevelRederivesInsteadOfStayingSleepier() {
    var session = BatterySession(realReading: onBattery(60))
    session.simulate(.discharging(percentage: 5))

    session.simulate(.discharging(percentage: 80))

    XCTAssertEqual(session.tracker.phase, .discharging(.awake))
  }

  func testSimulatingNoBatteryReportsNoBattery() {
    var session = BatterySession(realReading: onBattery(60))

    session.simulate(.noBattery)

    XCTAssertEqual(session.tracker.phase, .noBattery)
  }

  // MARK: - Simulated charging

  func testSimulatedChargingWakesAtTheCurrentPercentageThenSettles() {
    var session = BatterySession(realReading: onBattery(60))
    session.simulate(.discharging(percentage: 5))

    session.simulate(.charging)
    let afterPlugIn = session.tracker.phase
    session.finishWaking()

    XCTAssertEqual(afterPlugIn, .waking)
    XCTAssertEqual(session.tracker.reading, charging(5))
    XCTAssertEqual(session.tracker.phase, .onExternalPower)
  }

  func testSimulatedChargingWithNoBatteryAnywhereChargesAtOneHundredPercent() {
    var session = BatterySession(realReading: nil)

    session.simulate(.charging)

    XCTAssertEqual(session.tracker.reading, charging(100))
    XCTAssertEqual(session.tracker.phase, .onExternalPower)
  }

  func testReturningToRealWhileTheMacIsPluggedInWakes() {
    var session = BatterySession(realReading: charging(50))
    session.simulate(.discharging(percentage: 5))

    session.simulate(.real)

    XCTAssertEqual(session.tracker.phase, .waking)
  }

  // MARK: - Menu

  func testMenuOffersTheSpecChoicesInOrder() {
    XCTAssertEqual(
      BatterySimulation.menuChoices.map(\.title),
      ["Real", "80%", "40%", "25%", "15%", "5%", "Charging", "No battery"]
    )
  }
}
