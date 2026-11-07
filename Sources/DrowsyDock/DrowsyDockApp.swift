import SwiftUI

@main
struct DrowsyDockApp: App {
  @State private var coordinator = AppCoordinator()

  var body: some Scene {
    MenuBarExtra("DrowsyDock", systemImage: "moon.zzz") {
      MenuContent(coordinator: coordinator)
    }
  }
}
