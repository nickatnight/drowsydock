import AppKit
import DrowsyDockCore
import SwiftUI

struct MenuContent: View {
  let coordinator: AppCoordinator

  private var monitor: BatteryMonitor { coordinator.battery }

  var body: some View {
    Text(monitor.statusText)

    if coordinator.isAccessibilityGranted {
      Text("Accessibility: Granted")
    } else {
      Button("Grant Accessibility…") {
        coordinator.grantAccessibility()
      }
    }

    Divider()

    Menu("Debug") {
      Picker("Simulate battery", selection: simulation) {
        ForEach(BatterySimulation.menuChoices, id: \.self) { choice in
          Text(choice.title).tag(choice)
        }
      }
      .pickerStyle(.menu)

      Button("Log Dock geometry") {
        coordinator.logDockGeometry()
      }
    }

    Divider()

    Button("Quit DrowsyDock") {
      NSApplication.shared.terminate(nil)
    }
    .keyboardShortcut("q")
  }

  private var simulation: Binding<BatterySimulation> {
    Binding(
      get: { monitor.session.simulation },
      set: { monitor.simulate($0) }
    )
  }
}
