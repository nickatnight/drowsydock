import Observation
import SleepyBatteryCore
import os

@MainActor
@Observable
final class BatteryMonitor {
  private static let wakingDuration = Duration.seconds(3)

  private static let logger = Logger(
    subsystem: "com.drowsydock.SleepyBattery",
    category: "battery"
  )

  private(set) var session: BatterySession
  private(set) var isLowPowerModeOn: Bool

  @ObservationIgnored private var powerChanges: IOKitPowerSource.Subscription?
  @ObservationIgnored private var wakingTask: Task<Void, Never>?

  var statusText: String {
    StatusLine.text(for: session.tracker, isLowPowerModeOn: isLowPowerModeOn)
  }

  init() {
    session = BatterySession(realReading: IOKitPowerSource.readBattery())
    isLowPowerModeOn = IOKitPowerSource.isLowPowerModeOn
    Self.logger.notice("Started: \(self.logLine, privacy: .public)")

    do {
      powerChanges = try IOKitPowerSource.Subscription { [weak self] in
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
    let reading = IOKitPowerSource.readBattery()
    changeStatus {
      isLowPowerModeOn = IOKitPowerSource.isLowPowerModeOn
      session.receive(reading)
    }
  }

  private func changeStatus(_ change: () -> Void) {
    let previousPhase = session.tracker.phase
    let previousLogLine = logLine
    change()
    scheduleEndOfWakingIfEntered(from: previousPhase)
    logStatusIfChanged(from: previousLogLine)
  }

  private func scheduleEndOfWakingIfEntered(from previousPhase: DrowsinessTracker.Phase) {
    guard session.tracker.phase == .waking, previousPhase != .waking else { return }
    wakingTask?.cancel()
    wakingTask = Task { [weak self] in
      guard (try? await Task.sleep(for: Self.wakingDuration)) != nil, let self else { return }
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
