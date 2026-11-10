import DrowsyDockCore
import Observation
import os

@MainActor
protocol PowerSource {
  var isLowPowerModeOn: Bool { get }

  func readBattery() -> BatteryReading?

  func subscribe(onChange: @escaping @MainActor @Sendable () -> Void) throws -> AnyObject
}

@MainActor
@Observable
final class BatteryMonitor {
  private static let logger = Logger(
    subsystem: "com.drowsydock.DrowsyDock",
    category: "battery"
  )

  private(set) var session: BatterySession
  private(set) var isLowPowerModeOn: Bool

  /// Called after each change of the tracker's phase, with the new phase.
  @ObservationIgnored var onPhaseChange: ((DrowsinessTracker.Phase) -> Void)?

  @ObservationIgnored private let source: any PowerSource
  @ObservationIgnored private let clock: any Clock<Duration>
  @ObservationIgnored private var powerChanges: AnyObject?
  @ObservationIgnored private var wakingTask: Task<Void, Never>?

  var statusText: String {
    StatusLine.text(for: session.tracker, isLowPowerModeOn: isLowPowerModeOn)
  }

  init(
    source: any PowerSource = IOKitPowerSource(),
    clock: any Clock<Duration> = ContinuousClock()
  ) {
    self.source = source
    self.clock = clock
    session = BatterySession(realReading: source.readBattery())
    isLowPowerModeOn = source.isLowPowerModeOn
    Self.logger.notice("Started: \(self.logLine, privacy: .public)")

    do {
      powerChanges = try source.subscribe { [weak self] in
        self?.powerSourceDidChange()
      }
    } catch {
      Self.logger.error(
        "No power source notifications, so the status will not update: \(error, privacy: .public)"
      )
    }
  }

  func simulate(_ simulation: BatterySimulation) {
    changeStatus { session.simulate(simulation) }
  }

  private func powerSourceDidChange() {
    Self.logger.debug("Power source notification")
    let reading = source.readBattery()
    changeStatus {
      isLowPowerModeOn = source.isLowPowerModeOn
      session.receive(reading)
    }
  }

  private func changeStatus(_ change: () -> Void) {
    let previousPhase = session.tracker.phase
    let previousLogLine = logLine
    change()
    scheduleEndOfWakingIfEntered(from: previousPhase)
    logStatusIfChanged(from: previousLogLine)
    if session.tracker.phase != previousPhase {
      onPhaseChange?(session.tracker.phase)
    }
  }

  private func scheduleEndOfWakingIfEntered(from previousPhase: DrowsinessTracker.Phase) {
    guard session.tracker.phase == .waking, previousPhase != .waking else { return }
    wakingTask?.cancel()
    wakingTask = Task { [weak self, clock] in
      guard (try? await clock.sleep(for: DrowsinessTracker.wakingDuration)) != nil, let self else {
        return
      }
      changeStatus { session.finishWaking() }
    }
  }

  private func logStatusIfChanged(from previousLogLine: String) {
    guard logLine != previousLogLine else { return }
    Self.logger.notice("Changed: \(self.logLine, privacy: .public)")
  }

  private var logLine: String {
    let source = session.simulation == .real ? "real" : "simulated \(session.simulation.title)"
    return "\(statusText) (\(source))"
  }
}
