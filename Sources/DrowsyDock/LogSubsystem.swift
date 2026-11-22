/// The unified-log subsystem of every `MirroredLogger` in the app.
///
/// It equals `CFBundleIdentifier` in `Resources/Info.plist`, which `LogSubsystemTests` checks. It
/// is spelled out rather than read from `Bundle.main`, which under `swift test` is the test runner.
enum LogSubsystem {
  static let app = "app.drowsydock.DrowsyDock"
}
