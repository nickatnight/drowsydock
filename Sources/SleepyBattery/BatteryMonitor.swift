import Foundation
import Observation
import SleepyBatteryCore
import os

/// Owns the battery session for the app's lifetime and logs every change to it.
@MainActor
@Observable
final class BatteryMonitor {
  /// How long the wake-up phase lasts. The spec caps the wake-up animation at 3 s.
  private static let wakingDuration = Duration.seconds(3)

  private static let logger = Logger(
    subsystem: "com.drowsydock.SleepyBattery",
    category: "battery"
  )

  private(set) var session: BatterySession
  private(set) var isLowPowerModeOn: Bool

  private let powerSource = IOKitPowerSource()
  @ObservationIgnored private var wakingTask: Task<Void, Never>?

  /// The menu's battery line, such as "63% · Discharging · Drowsy".
  var statusText: String {
    StatusLine.text(for: session.tracker, isLowPowerModeOn: isLowPowerModeOn)
  }

  init() {
    session = BatterySession(realReading: powerSource.readBattery())
    isLowPowerModeOn = powerSource.isLowPowerModeOn
    Self.logger.notice("Started: \(self.logLine, privacy: .public)")

    let observing = powerSource.startObserving { [weak self] in
      self?.powerSourceDidChange()
    }
    if !observing {
      Self.logger.error("IOKit gave no power source notification; the status will not update")
    }
  }

  /// Switches the Debug ▸ Simulate battery choice.
  func simulate(_ simulation: BatterySimulation) {
    update { session.simulate(simulation) }
  }

  private func powerSourceDidChange() {
    Self.logger.debug("Power source notification")
    let reading = powerSource.readBattery()
    update {
      isLowPowerModeOn = powerSource.isLowPowerModeOn
      session.receive(reading)
    }
  }

  /// Applies `change`, starts the wake-up timer on entering `waking`, and logs the new status if
  /// it differs. IOKit also notifies for changes the menu doesn't show, such as time remaining.
  private func update(_ change: () -> Void) {
    let previousLine = logLine
    let previousPhase = session.tracker.phase
    change()
    if session.tracker.phase == .waking && previousPhase != .waking {
      scheduleEndOfWaking()
    }
    if logLine != previousLine {
      Self.logger.notice("Changed: \(self.logLine, privacy: .public)")
    }
  }

  private func scheduleEndOfWaking() {
    wakingTask?.cancel()
    wakingTask = Task { [weak self] in
      guard (try? await Task.sleep(for: Self.wakingDuration)) != nil, let self else { return }
      update { session.finishWaking() }
    }
  }

  private var logLine: String {
    let source = session.simulation == .real ? "real" : "simulated \(session.simulation.title)"
    return "\(statusText) (\(source))"
  }
}
