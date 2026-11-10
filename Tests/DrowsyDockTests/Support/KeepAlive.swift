/// Keeps objects alive until the test process ends.
///
/// AppKit runs a window's fade on after the test that started it. A window freed mid-fade crashes
/// whichever later test runs the run loop when the fade's next step fires. The app never frees its
/// overlay windows, so the tests keep theirs too.
@MainActor
enum KeepAlive {
  private static var objects: [AnyObject] = []

  static func keep(_ object: AnyObject) {
    objects.append(object)
  }
}
