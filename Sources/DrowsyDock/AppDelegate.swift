import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let coordinator: AppCoordinator

  override init() {
    QALogFile.startIfRequested(by: CommandLine.arguments)
    coordinator = AppCoordinator()
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    coordinator.startDockTracking()
  }
}
