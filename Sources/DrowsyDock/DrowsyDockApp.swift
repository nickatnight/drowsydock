import SwiftUI

@main
struct DrowsyDockApp: App {
  @State private var monitor = BatteryMonitor()

  var body: some Scene {
    MenuBarExtra("Sleepy Battery", systemImage: "moon.zzz") {
      MenuContent(monitor: monitor)
    }
  }
}
