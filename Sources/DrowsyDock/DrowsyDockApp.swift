import SwiftUI

@main
struct DrowsyDockApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra {
      MenuContent(coordinator: appDelegate.coordinator)
    } label: {
      Image(nsImage: MenuBarGlyph.image())
        .accessibilityLabel(MenuBarGlyph.accessibilityDescription)
    }
  }
}
