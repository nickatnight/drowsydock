import DrowsyDockCore
import XCTest

final class CrowdEffectRuleTests: XCTestCase {
  private let awake = DrowsinessTracker.Phase.discharging(.awake)
  private let noddingOff = DrowsinessTracker.Phase.discharging(.noddingOff)
  private let asleep = DrowsinessTracker.Phase.discharging(.asleep)

  // MARK: - Firing once per discharge cycle

  func testItPlaysOnTheFirstEntryIntoAsleep() {
    var rule = CrowdEffectRule(startingIn: noddingOff)

    XCTAssertTrue(rule.phaseChanged(to: asleep))
  }

  func testItPlaysWhenAnAwakeCatDropsStraightToAsleep() {
    var rule = CrowdEffectRule(startingIn: awake)

    XCTAssertTrue(rule.phaseChanged(to: asleep))
  }

  func testItDoesNotPlayForTheOtherStates() {
    var rule = CrowdEffectRule(startingIn: awake)

    for state in [DrowsinessState.drowsy, .yawning, .noddingOff] {
      XCTAssertFalse(rule.phaseChanged(to: .discharging(state)), "\(state)")
    }
  }

  func testItPlaysOnlyOnceWhileTheCatStaysAsleep() {
    var rule = CrowdEffectRule(startingIn: noddingOff)
    _ = rule.phaseChanged(to: asleep)

    XCTAssertFalse(rule.phaseChanged(to: asleep))
  }

  func testLeavingAsleepAndComingBackWithoutChargingDoesNotReplayIt() {
    var rule = CrowdEffectRule(startingIn: noddingOff)
    _ = rule.phaseChanged(to: asleep)
    _ = rule.phaseChanged(to: noddingOff)

    XCTAssertFalse(rule.phaseChanged(to: asleep))
  }

  // MARK: - Re-arming on AC power

  func testChargingAndUnpluggingIntoAsleepPlaysItAgain() {
    var rule = CrowdEffectRule(startingIn: noddingOff)
    _ = rule.phaseChanged(to: asleep)
    _ = rule.phaseChanged(to: .waking)
    _ = rule.phaseChanged(to: .onExternalPower)

    XCTAssertTrue(rule.phaseChanged(to: asleep))
  }

  func testTheWakeUpAloneReArmsIt() {
    var rule = CrowdEffectRule(startingIn: noddingOff)
    _ = rule.phaseChanged(to: asleep)
    _ = rule.phaseChanged(to: .waking)

    XCTAssertTrue(rule.phaseChanged(to: asleep))
  }

  func testLosingTheBatteryDoesNotReArmIt() {
    var rule = CrowdEffectRule(startingIn: noddingOff)
    _ = rule.phaseChanged(to: asleep)
    _ = rule.phaseChanged(to: nil)

    XCTAssertFalse(rule.phaseChanged(to: asleep))
  }

  // MARK: - Suppression

  func testItNeverPlaysWhileDisabled() {
    var rule = CrowdEffectRule(startingIn: noddingOff)

    XCTAssertFalse(rule.phaseChanged(to: asleep, isEnabled: false))
  }

  func testItNeverPlaysInQuietHours() {
    var rule = CrowdEffectRule(startingIn: noddingOff)

    XCTAssertFalse(rule.phaseChanged(to: asleep, quietHours: true))
  }

  func testASuppressedEntryStillUsesUpTheCycle() {
    var rule = CrowdEffectRule(startingIn: noddingOff)
    _ = rule.phaseChanged(to: asleep, quietHours: true)
    _ = rule.phaseChanged(to: noddingOff)

    XCTAssertFalse(rule.phaseChanged(to: asleep))
  }

  // MARK: - Launch and wake resync

  func testLaunchingAsleepDoesNotPlayItOrLaterWithoutACharge() {
    var rule = CrowdEffectRule(startingIn: asleep)
    _ = rule.phaseChanged(to: noddingOff)

    XCTAssertFalse(rule.phaseChanged(to: asleep))
  }

  func testAWakeResyncIntoAsleepDoesNotPlayIt() {
    var rule = CrowdEffectRule(startingIn: awake)

    rule.resynced(to: asleep)

    XCTAssertFalse(rule.phaseChanged(to: asleep))
    _ = rule.phaseChanged(to: noddingOff)
    XCTAssertFalse(rule.phaseChanged(to: asleep))
  }

  func testAWakeResyncOntoACPowerReArmsIt() {
    var rule = CrowdEffectRule(startingIn: asleep)

    rule.resynced(to: .onExternalPower)

    XCTAssertTrue(rule.phaseChanged(to: asleep))
  }

  func testAResyncIntoAnotherStateLeavesTheNextEntryArmed() {
    var rule = CrowdEffectRule(startingIn: awake)

    rule.resynced(to: noddingOff)

    XCTAssertTrue(rule.phaseChanged(to: asleep))
  }
}
