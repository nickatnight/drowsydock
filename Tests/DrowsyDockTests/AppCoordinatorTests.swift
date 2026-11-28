import AppKit
import DockOverlayKitTestSupport
import DrowsyDockCore
import XCTest

@testable import DockOverlayKit
@testable import DrowsyDock

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
    let catFades: FadeRecorder
    let canvasFades: FadeRecorder
    let workspace: NotificationCenter

    var line: String { coordinator.battery.statusText }
    var overlay: MascotOverlay { coordinator.overlay }

    func simulate(_ simulation: BatterySimulation) {
      coordinator.battery.simulate(simulation)
    }

    func percent(_ percentage: Int) {
      simulate(.discharging(percentage: percentage))
    }

    func wakeFromSleep(to reading: BatteryReading?) {
      power.reading = reading
      workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
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
    let tracker = FakeDockTracker()
    let workspace = NotificationCenter()
    let coordinator = AppCoordinator(
      battery: BatteryMonitor(source: power, clock: clock),
      overlay: MascotOverlay(catScene: MascotScene(clock: TestClock())),
      readsAccessibilityGrant: { grant.isGranted },
      workspaceNotifications: workspace,
      makeDockTracker: { onPresentationChange in
        tracker.onPresentationChange = onPresentationChange
        return tracker
      }
    )
    addTeardownBlock { coordinator.overlay.show(nil) }
    KeepAlive.keep(coordinator)
    coordinator.startDockTracking()
    return Rig(
      coordinator: coordinator,
      power: power,
      tracker: tracker,
      clock: clock,
      grant: grant,
      catFades: FadeRecorder(coordinator.overlay.catWindow),
      canvasFades: FadeRecorder(coordinator.overlay.canvasWindow),
      workspace: workspace
    )
  }

  private func endWaking(_ rig: Rig) {
    waitUntil("the end of waking is scheduled") { rig.clock.sleeperCount == 1 }
    rig.clock.advance(by: DrowsinessTracker.wakingDuration)
    waitUntil("waking ends") { rig.line.hasSuffix("Awake") }
  }

  private func isWavePlaying(_ rig: Rig) -> Bool {
    rig.overlay.canvasScene.needsAnotherFrame
  }

  private func finishWave(_ rig: Rig) {
    let canvas = OffscreenRenderer(
      scene: rig.overlay.canvasScene,
      size: rig.overlay.canvasWindow.frame.size
    )
    canvas.advance(by: CrowdWave.maximumDuration.inSeconds + 0.1)
  }

  // MARK: - The menu line

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

  func testNoBatteryShowsNoBatteryDetected() {
    let rig = rig()

    rig.simulate(.noBattery)

    XCTAssertEqual(rig.line, "No battery detected")
  }

  func testRealAfterASimulationShowsTheRealBatteryAgain() {
    let rig = rig()
    rig.percent(5)

    rig.simulate(.real)

    XCTAssertEqual(rig.line, "46% · Discharging · Drowsy")
  }

  func testTheRealBatterysChangesAndLowPowerModeReachTheLine() {
    let rig = rig()

    rig.power.change(to: reading(24), lowPowerMode: true)

    XCTAssertEqual(rig.line, "24% · Discharging · Yawning · Low Power")
  }

  func testUnpluggingShowsTheDischargingState() {
    let rig = rig()
    rig.power.change(to: BatteryReading(clampingPercentage: 46, powerState: .charging))

    rig.power.change(to: reading(46))

    XCTAssertEqual(rig.line, "46% · Discharging · Drowsy")
  }

  func testAFullBatteryOnACPowerSettlesOnPluggedInAwake() {
    let rig = rig()

    rig.power.change(to: BatteryReading(clampingPercentage: 100, powerState: .pluggedIn))
    XCTAssertEqual(rig.line, "100% · Plugged in · Waking")
    endWaking(rig)

    XCTAssertEqual(rig.line, "100% · Plugged in · Awake")
  }

  func testWakingEndsThreeSecondsAfterTheLastPlugIn() {
    let rig = rig()
    let charging = BatteryReading(clampingPercentage: 46, powerState: .charging)
    rig.power.change(to: charging)
    waitUntil("the end of waking is scheduled") { rig.clock.sleeperCount == 1 }
    rig.clock.advance(by: .seconds(2))

    rig.power.change(to: reading(46))
    rig.power.change(to: charging)
    waitUntil("the new end of waking is scheduled") { rig.clock.sleeperCount == 1 }
    rig.clock.advance(by: .milliseconds(2900))
    OffscreenRenderer.drainMainQueue()
    XCTAssertEqual(rig.line, "46% · Charging · Waking")
    rig.clock.advance(by: .milliseconds(100))

    waitUntil("waking ends") { rig.line == "46% · Charging · Awake" }
  }

  // MARK: - When the overlay shows

  func testTheGrantReachesTheTrackerAndItsHiddenPresentationHidesTheCat() {
    let rig = rig(granted: false)
    XCTAssertEqual(rig.tracker.grants, [false])
    XCTAssertFalse(rig.coordinator.isAccessibilityGranted)
    XCTAssertEqual(rig.overlay.catWindow.visibility, .hidden)
    rig.grant.isGranted = true
    NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: nil)
    rig.percent(80)
    rig.tracker.present(shown)
    XCTAssertEqual(rig.overlay.catWindow.visibility, .shown)

    rig.grant.isGranted = false
    NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: nil)

    XCTAssertEqual(rig.tracker.grants, [false, true, false])
    XCTAssertEqual(rig.overlay.catWindow.visibility, .hidden)
    XCTAssertEqual(rig.overlay.canvasWindow.visibility, .hidden)
  }

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

  func testTheCatShowsAtThePerchTheTrackerReports() {
    let rig = rig()
    rig.percent(80)

    rig.tracker.present(shown)

    XCTAssertEqual(rig.overlay.catWindow.visibility, .shown)
    XCTAssertEqual(rig.overlay.catWindow.frame, dock.perch(for: MascotOverlay.spriteSize).frame)
    XCTAssertEqual(rig.overlay.canvasWindow.visibility, .hidden)
  }

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
    XCTAssertEqual(rig.canvasFades.lastFade?.alpha, 1, "the veil fades in as usual")
    XCTAssertEqual(rig.canvasFades.lastFade?.duration, 0.2)
    rig.percent(15)

    XCTAssertEqual(rig.overlay.canvasWindow.visibility, .hidden)
    XCTAssertEqual(rig.canvasFades.lastFade?.alpha, 0, "the veil fades out (10.11)")
    XCTAssertEqual(rig.canvasFades.lastFade?.duration, 0.2)
    XCTAssertFalse(rig.overlay.canvasWindow.window.isVisible)
  }

  func testARefusedPerchFrameHidesTheCatAndStopsItsScene() {
    let rig = rig()
    rig.percent(5)
    let unusable = DockPerch(
      frame: CGRect(x: CGFloat.infinity, y: 0, width: 64, height: 80),
      facing: .left
    )

    rig.tracker.present(.shown(unusable, on: dock))

    XCTAssertEqual(rig.overlay.catWindow.visibility, .hidden)
    XCTAssertFalse(rig.overlay.catScene.needsAnotherFrame)
  }

  // MARK: - The pointer over the Dock

  func testHoveringThePerchFadesTheCatOutAndBack() {
    let rig = rig()
    rig.percent(80)
    rig.tracker.present(shown)

    rig.tracker.present(fadedOut)
    XCTAssertEqual(rig.overlay.catWindow.visibility, .fadedOut)
    XCTAssertEqual(rig.catFades.lastFade?.alpha, 0)
    XCTAssertEqual(rig.catFades.lastFade?.duration, 0.2, "the label is readable within 0.2 s")
    XCTAssertEqual(rig.overlay.catWindow.window.alphaValue, 0)
    XCTAssertTrue(rig.overlay.catWindow.window.isVisible)
    rig.tracker.present(shown)

    XCTAssertEqual(rig.overlay.catWindow.visibility, .shown)
    XCTAssertEqual(rig.catFades.lastFade?.alpha, 1)
    XCTAssertEqual(rig.overlay.catWindow.window.alphaValue, 1)
  }

  func testAtFivePercentTheVeilFadesWithTheCat() {
    let rig = rig()
    rig.percent(5)
    rig.tracker.present(shown)
    XCTAssertTrue(rig.overlay.catScene.needsAnotherFrame)

    rig.tracker.present(fadedOut)
    XCTAssertEqual(rig.overlay.canvasWindow.visibility, .fadedOut)
    XCTAssertEqual(rig.canvasFades.lastFade?.alpha, 0)
    XCTAssertEqual(rig.catFades.lastFade?.alpha, 0)
    XCTAssertEqual(rig.overlay.canvasWindow.window.alphaValue, 0)
    XCTAssertFalse(rig.overlay.catScene.needsAnotherFrame)
    rig.tracker.present(shown)

    XCTAssertEqual(rig.overlay.canvasWindow.visibility, .shown)
    XCTAssertEqual(rig.overlay.canvasWindow.window.alphaValue, 1)
    XCTAssertTrue(rig.overlay.catScene.needsAnotherFrame)
  }

  // MARK: - The whole Dock nods off

  func testFallingAsleepPlaysTheWave() {
    let rig = rig()
    rig.tracker.present(shown)
    rig.percent(15)

    rig.percent(5)

    XCTAssertTrue(isWavePlaying(rig))
  }

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

  func testHoveringStopsTheWaveForGood() {
    let rig = rig()
    rig.tracker.present(shown)
    rig.simulate(.charging)
    rig.percent(5)
    XCTAssertTrue(isWavePlaying(rig))

    rig.tracker.present(fadedOut)
    XCTAssertFalse(isWavePlaying(rig))
    XCTAssertEqual(rig.canvasFades.lastFade?.alpha, 0)
    rig.tracker.present(shown)

    XCTAssertFalse(isWavePlaying(rig))
  }

  func testLaunchingAsleepPlaysNoWave() {
    let rig = rig(battery: reading(5))

    rig.tracker.present(shown)

    XCTAssertEqual(rig.line, "5% · Discharging · Asleep")
    XCTAssertFalse(isWavePlaying(rig))
  }

  // MARK: - Waking the Mac from sleep

  func testAChangeOnBatteryAnimatesTheCat() {
    let rig = rig(battery: reading(60))
    rig.tracker.present(shown)

    rig.power.change(to: reading(35))

    XCTAssertTrue(rig.overlay.catScene.needsAnotherFrame)
  }

  func testWakingFromSleepJumpsToTheBatterysStateWithoutATransition() {
    let rig = rig(battery: reading(60))
    rig.tracker.present(shown)

    rig.wakeFromSleep(to: reading(35))

    XCTAssertEqual(rig.line, "35% · Discharging · Drowsy")
    XCTAssertEqual(rig.overlay.catScene.director.shown, .drowsiness(.drowsy))
    XCTAssertFalse(rig.overlay.catScene.needsAnotherFrame)
  }

  func testWakingFromSleepIntoAsleepPlaysNoWaveAndUsesUpTheCycle() {
    let rig = rig(battery: reading(80))
    rig.tracker.present(shown)

    rig.wakeFromSleep(to: reading(5))
    XCTAssertEqual(rig.line, "5% · Discharging · Asleep")
    XCTAssertFalse(isWavePlaying(rig))
    XCTAssertEqual(rig.overlay.canvasWindow.visibility, .shown)
    rig.percent(15)
    rig.percent(5)

    XCTAssertFalse(isWavePlaying(rig))
  }

  func testWakingFromSleepOnACPowerShowsAwakeWithoutTheWakeUp() {
    let rig = rig(battery: reading(5))
    rig.tracker.present(shown)

    rig.wakeFromSleep(to: BatteryReading(clampingPercentage: 5, powerState: .charging))

    XCTAssertEqual(rig.line, "5% · Charging · Awake")
    XCTAssertEqual(rig.overlay.catScene.director.shown, .drowsiness(.awake))
    XCTAssertFalse(rig.overlay.catScene.needsAnotherFrame)
  }

  func testWakingFromSleepDuringTheWakeUpCutsItShort() {
    let rig = rig(battery: reading(5))
    rig.tracker.present(shown)
    let charging = BatteryReading(clampingPercentage: 5, powerState: .charging)
    rig.power.change(to: charging)
    XCTAssertEqual(rig.line, "5% · Charging · Waking")
    waitUntil("the end of waking is scheduled") { rig.clock.sleeperCount == 1 }

    rig.wakeFromSleep(to: charging)
    XCTAssertEqual(rig.line, "5% · Charging · Awake")
    XCTAssertEqual(rig.overlay.catScene.director.shown, .drowsiness(.awake))
    XCTAssertFalse(rig.overlay.catScene.needsAnotherFrame)
    rig.clock.advance(by: DrowsinessTracker.wakingDuration)
    OffscreenRenderer.drainMainQueue()

    XCTAssertEqual(rig.line, "5% · Charging · Awake")
    XCTAssertFalse(isWavePlaying(rig))
  }

  func testWakingFromSleepRereadsLowPowerMode() {
    let rig = rig(battery: reading(60))
    rig.power.isLowPowerModeOn = true

    rig.wakeFromSleep(to: reading(60))

    XCTAssertEqual(rig.line, "60% · Discharging · Awake · Low Power")
  }

  func testWakingFromSleepWithNoBatteryHidesTheOverlay() {
    let rig = rig(battery: reading(5))
    rig.tracker.present(shown)

    rig.wakeFromSleep(to: nil)

    XCTAssertEqual(rig.line, "No battery detected")
    XCTAssertEqual(rig.overlay.catWindow.visibility, .hidden)
    XCTAssertEqual(rig.overlay.canvasWindow.visibility, .hidden)
  }
}
