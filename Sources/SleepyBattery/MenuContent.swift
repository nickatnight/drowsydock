import AppKit
import DrowsyDockCore
import SwiftUI

struct MenuContent: View {
  let monitor: BatteryMonitor

  var body: some View {
    Text(monitor.statusText)

    Divider()

    Menu("Debug") {
      Picker("Simulate battery", selection: simulation) {
        ForEach(BatterySimulation.menuChoices, id: \.self) { choice in
          Text(choice.title).tag(choice)
        }
      }
      .pickerStyle(.menu)
    }

    Divider()

    Button("Quit Sleepy Battery") {
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
