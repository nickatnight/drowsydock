import AppKit
import SwiftUI

@main
struct SleepyBatteryApp: App {
  var body: some Scene {
    MenuBarExtra("Sleepy Battery", systemImage: "moon.zzz") {
      Button("Quit Sleepy Battery") {
        NSApplication.shared.terminate(nil)
      }
      .keyboardShortcut("q")
    }
  }
}
