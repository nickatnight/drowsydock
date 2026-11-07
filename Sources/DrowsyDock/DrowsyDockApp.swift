import SwiftUI

@main
struct DrowsyDockApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra("DrowsyDock", systemImage: "moon.zzz") {
      MenuContent(coordinator: appDelegate.coordinator)
    }
  }
}
