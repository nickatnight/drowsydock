import SwiftUI

@main
struct DrowsyDockApp: App {
  @State private var monitor = BatteryMonitor()

  var body: some Scene {
    MenuBarExtra("DrowsyDock", systemImage: "moon.zzz") {
      MenuContent(monitor: monitor)
    }
  }
}
