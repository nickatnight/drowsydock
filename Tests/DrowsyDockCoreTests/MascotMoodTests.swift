import DrowsyDockCore
import XCTest

final class MascotMoodTests: XCTestCase {
  func testADischargingPhaseShowsItsState() {
    for state in DrowsinessState.allCases {
      XCTAssertEqual(DrowsinessTracker.Phase.discharging(state).mood, .drowsiness(state))
    }
  }

  func testWakingShowsTheWakeUp() {
    XCTAssertEqual(DrowsinessTracker.Phase.waking.mood, .waking)
  }

  func testOnExternalPowerTheCatIsAwake() {
    XCTAssertEqual(DrowsinessTracker.Phase.onExternalPower.mood, .drowsiness(.awake))
  }

  func testTheWakeUpSettlesAwake() {
    XCTAssertEqual(MascotMood.waking.settledState, .awake)
  }

  func testADrowsinessMoodSettlesInItsState() {
    for state in DrowsinessState.allCases {
      XCTAssertEqual(MascotMood.drowsiness(state).settledState, state)
    }
  }
}
