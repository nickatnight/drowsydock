import AppKit
import DockOverlayKit
import DrowsyDockCore
import XCTest

@testable import DrowsyDock

// The app's wiring, driven through AppCoordinator with a fake battery, a fake Dock tracker and a
// test clock, and checked on the menu line, the real overlay windows and the crowd effect.
@MainActor
final class AppCoordinatorTests: XCTestCase {
  @MainActor
  private final class Grant {
    var isGranted: Bool

    init(_ isGranted: Bool) {
      self.isGranted = isGranted
    }
  }

  @MainActor
  private struct Rig {
    let coordinator: AppCoordinator
    let power: FakePowerSource
    let tracker: FakeDockTracker
    let clock: TestClock
    let grant: Grant

    var line: String { coordinator.battery.statusText }
    var overlay: MascotOverlay { coordinator.overlay }

    func simulate(_ simulation: BatterySimulation) {
      coordinator.battery.simulate(simulation)
    }

    func percent(_ percentage: Int) {
      simulate(.discharging(percentage: percentage))
    }
  }

  private let dock = DockFixture.bottom

  private var shown: OverlayPresentation {
    .shown(dock.perch(for: MascotOverlay.spriteSize), on: dock)
  }

  private var fadedOut: OverlayPresentation {
    .fadedOut(dock.perch(for: MascotOverlay.spriteSize), on: dock)
  }

  private func reading(_ percentage: Int) -> BatteryReading {
    BatteryReading(clampingPercentage: percentage, powerState: .discharging)
  }

  private func rig(battery: BatteryReading? = nil, granted: Bool = true) -> Rig {
    let power = FakePowerSource(battery ?? reading(46))
    let clock = TestClock()
    let grant = Grant(granted)
    var tracker: FakeDockTracker?
    let coordinator = AppCoordinator(
      battery: BatteryMonitor(source: power, clock: clock),
      overlay: MascotOverlay(catScene: MascotScene(clock: TestClock())),
      readsAccessibilityGrant: { grant.isGranted },
      makeDockTracker: { onPresentationChange in
        let fake = FakeDockTracker(onPresentationChange: onPresentationChange)
        tracker = fake
        return fake
      }
    )
    addTeardownBlock { coordinator.overlay.show(nil) }
    KeepAlive.keep(coordinator)
    coordinator.startDockTracking()
    // The coordinator calls makeDockTracker in its initializer.
    return Rig(
      coordinator: coordinator,
      power: power,
      tracker: tracker!,
      clock: clock,
      grant: grant
    )
  }

  // The waking task registers its sleep asynchronously, so wait for it before moving the clock.
  private func endWaking(_ rig: Rig) {
    waitUntil("the end of waking is scheduled") { rig.clock.sleeperCount == 1 }
    rig.clock.advance(by: DrowsinessTracker.wakingDuration)
    waitUntil("waking ends") { rig.line.hasSuffix("Awake") }
  }

  private func isWavePlaying(_ rig: Rig) -> Bool {
    rig.overlay.canvasScene.needsAnotherFrame
  }

  // Runs the canvas until the wave has ended.
  private func finishWave(_ rig: Rig) {
    let canvas = OffscreenRenderer(
      scene: rig.overlay.canvasScene,
      size: rig.overlay.canvasWindow.frame.size
    )
    canvas.advance(by: CrowdWave.maximumDuration.inSeconds + 0.1)
  }

  // MARK: - The menu line

  // QA 3.9 to 3.13, and the same levels in reverse order: a simulated level is a jump.
  func testEachSimulatedLevelShowsItsStateInEitherOrder() {
    let rig = rig()
    let lines = [
      (80, "80% · Discharging · Awake"),
      (40, "40% · Discharging · Drowsy"),
      (25, "25% · Discharging · Yawning"),
      (15, "15% · Discharging · Nodding off"),
      (5, "5% · Discharging · Asleep"),
    ]

    for (percentage, line) in lines + lines.reversed() {
      rig.percent(percentage)
      XCTAssertEqual(rig.line, line)
    }
  }

  // QA 3.14: Charging wakes the cat, and 3 s later it settles awake, not earlier.
  func testChargingShowsWakingThenAwakeThreeSecondsLater() {
    let rig = rig()
    rig.percent(5)

    rig.simulate(.charging)
    XCTAssertEqual(rig.line, "5% · Charging · Waking")
    waitUntil("the end of waking is scheduled") { rig.clock.sleeperCount == 1 }
    rig.clock.advance(by: .milliseconds(2900))
    OffscreenRenderer.drainMainQueue()
    XCTAssertEqual(rig.line, "5% · Charging · Waking")
    rig.clock.advance(by: .milliseconds(100))

    waitUntil("waking ends") { rig.line == "5% · Charging · Awake" }
  }

  // QA 3.15
  func testNoBatteryShowsNoBatteryDetected() {
    let rig = rig()

    rig.simulate(.noBattery)

    XCTAssertEqual(rig.line, "No battery detected")
  }

  // QA 3.16: back to the real battery's line, derived afresh, not stuck at Asleep.
  func testRealAfterASimulationShowsTheRealBatteryAgain() {
    let rig = rig()
    rig.percent(5)

    rig.simulate(.real)

    XCTAssertEqual(rig.line, "46% · Discharging · Drowsy")
  }

  // QA 3.1 and 3.5: the real battery's changes and Low Power Mode reach the line.
  func testTheRealBatterysChangesAndLowPowerModeReachTheLine() {
    let rig = rig()

    rig.power.change(to: reading(24), lowPowerMode: true)

    XCTAssertEqual(rig.line, "24% · Discharging · Yawning · Low Power")
  }

  // MARK: - When the overlay shows

  // QA 6.6: without the grant the tracker is told so, and no cat shows anywhere.
  func testWithoutTheGrantTheTrackerIsToldAndNothingShows() {
    let rig = rig(granted: false)

    XCTAssertEqual(rig.tracker.grants, [false])
    XCTAssertFalse(rig.coordinator.isAccessibilityGranted)
    XCTAssertEqual(rig.overlay.catWindow.visibility, .hidden)
    XCTAssertEqual(rig.overlay.canvasWindow.visibility, .hidden)
  }

  // QA 4.3 and 4.4, the app's side: opening the menu re-reads the grant and tells the tracker.
  func testOpeningTheMenuPicksUpAChangedGrant() {
    let rig = rig(granted: false)

    rig.grant.isGranted = true
    NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: nil)
    XCTAssertTrue(rig.coordinator.isAccessibilityGranted)
    rig.grant.isGranted = false
    NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: nil)

    XCTAssertEqual(rig.tracker.grants, [false, true, false])
    XCTAssertFalse(rig.coordinator.isAccessibilityGranted)
  }

  // QA 6.1 and 8.1: the cat shows at the perch once the tracker places it.
  func testTheCatShowsAtThePerchTheTrackerReports() {
    let rig = rig()
    rig.percent(80)

    rig.tracker.present(shown)

    XCTAssertEqual(rig.overlay.catWindow.visibility, .shown)
    XCTAssertEqual(rig.overlay.catWindow.frame, dock.perch(for: MascotOverlay.spriteSize).frame)
    XCTAssertEqual(rig.overlay.canvasWindow.visibility, .hidden)
  }

  // QA 8.8: No battery hides the cat and the veil; 80% brings the cat back.
  func testNoBatteryHidesTheCatAndTheVeilUntilABatteryIsBack() {
    let rig = rig()
    rig.tracker.present(shown)
    rig.percent(5)
    XCTAssertEqual(rig.overlay.canvasWindow.visibility, .shown)

    rig.simulate(.noBattery)
    XCTAssertEqual(rig.overlay.catWindow.visibility, .hidden)
    XCTAssertEqual(rig.overlay.canvasWindow.visibility, .hidden)
    rig.percent(80)

    XCTAssertEqual(rig.overlay.catWindow.visibility, .shown)
    XCTAssertEqual(rig.overlay.canvasWindow.visibility, .hidden)
  }

  // QA 8.5, 8.6 and 10.4: the veil shows at 5% only, over the Dock's drawn background.
  func testTheVeilShowsAtFivePercentAndGoesAtFifteen() {
    let rig = rig()
    rig.tracker.present(shown)
    rig.percent(15)
    XCTAssertEqual(rig.overlay.canvasWindow.visibility, .hidden)

    rig.percent(5)
    XCTAssertEqual(rig.overlay.canvasWindow.visibility, .shown)
    XCTAssertEqual(rig.overlay.canvasWindow.frame, MascotOverlay.canvasFrame(around: dock))
    finishWave(rig)
    XCTAssertEqual(rig.overlay.canvasWindow.visibility, .shown)
    rig.percent(15)

    XCTAssertEqual(rig.overlay.canvasWindow.visibility, .hidden)
  }

  // MARK: - The pointer over the Dock

  // QA 8.11: the cat fades out while the pointer is on its icon and comes back after.
  func testHoveringThePerchFadesTheCatOutAndBack() {
    let rig = rig()
    rig.percent(80)
    rig.tracker.present(shown)

    rig.tracker.present(fadedOut)
    XCTAssertEqual(rig.overlay.catWindow.visibility, .fadedOut)
    rig.tracker.present(shown)

    XCTAssertEqual(rig.overlay.catWindow.visibility, .shown)
  }

  // QA 8.11 and 8.12 at 5%: the veil fades with the cat, and the snore stops while faded.
  func testAtFivePercentTheVeilFadesWithTheCat() {
    let rig = rig()
    rig.percent(5)
    rig.tracker.present(shown)
    XCTAssertTrue(rig.overlay.catScene.needsAnotherFrame)

    rig.tracker.present(fadedOut)
    XCTAssertEqual(rig.overlay.canvasWindow.visibility, .fadedOut)
    XCTAssertFalse(rig.overlay.catScene.needsAnotherFrame)
    rig.tracker.present(shown)

    XCTAssertEqual(rig.overlay.canvasWindow.visibility, .shown)
    XCTAssertTrue(rig.overlay.catScene.needsAnotherFrame)
  }

  // MARK: - The whole Dock nods off

  // QA 11.1, the wiring: falling asleep on a shown Dock plays the wave.
  func testFallingAsleepPlaysTheWave() {
    let rig = rig()
    rig.tracker.present(shown)
    rig.percent(15)

    rig.percent(5)

    XCTAssertTrue(isWavePlaying(rig))
  }

  // QA 11.2 and 11.3: no second wave in the same discharge cycle; a charge arms it again.
  func testTheWavePlaysOncePerDischargeCycle() {
    let rig = rig()
    rig.tracker.present(shown)
    rig.percent(15)
    rig.percent(5)
    finishWave(rig)

    rig.percent(15)
    rig.percent(5)
    XCTAssertFalse(isWavePlaying(rig))
    rig.simulate(.charging)
    endWaking(rig)
    rig.percent(5)

    XCTAssertTrue(isWavePlaying(rig))
  }

  // QA 11.4: picking 5% twice after a charge plays one wave.
  func testPickingFivePercentTwicePlaysOneWave() {
    let rig = rig()
    rig.tracker.present(shown)
    rig.simulate(.charging)
    rig.percent(5)
    XCTAssertTrue(isWavePlaying(rig))
    finishWave(rig)

    rig.percent(5)

    XCTAssertFalse(isWavePlaying(rig))
  }

  // QA 11.6: falling asleep while the Dock is hidden uses up the cycle without a wave, and the cat
  // appears asleep once the Dock shows.
  func testFallingAsleepWhileTheDockIsHiddenUsesUpTheCycle() {
    let rig = rig()
    rig.tracker.present(.hidden)
    rig.simulate(.charging)
    endWaking(rig)
    rig.percent(5)

    rig.tracker.present(shown)
    XCTAssertFalse(isWavePlaying(rig))
    XCTAssertEqual(rig.overlay.catWindow.visibility, .shown)
    XCTAssertEqual(rig.overlay.canvasWindow.visibility, .shown)
    rig.percent(15)
    rig.percent(5)

    XCTAssertFalse(isWavePlaying(rig))
  }

  // QA 11.7: hovering stops the wave, and it doesn't resume when the pointer leaves.
  func testHoveringStopsTheWaveForGood() {
    let rig = rig()
    rig.tracker.present(shown)
    rig.simulate(.charging)
    rig.percent(5)
    XCTAssertTrue(isWavePlaying(rig))

    rig.tracker.present(fadedOut)
    XCTAssertFalse(isWavePlaying(rig))
    rig.tracker.present(shown)

    XCTAssertFalse(isWavePlaying(rig))
  }

  // QA 11.8: launching below 10% plays no wave.
  func testLaunchingAsleepPlaysNoWave() {
    let rig = rig(battery: reading(5))

    rig.tracker.present(shown)

    XCTAssertEqual(rig.line, "5% · Discharging · Asleep")
    XCTAssertFalse(isWavePlaying(rig))
  }
}
