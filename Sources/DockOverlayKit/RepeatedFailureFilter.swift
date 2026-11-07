/// Decides which failures to log, so that a run of identical failures logs once.
///
/// After the grant is revoked, for example, every display, Space or preference change fails the
/// same way until the user opens the menu.
struct RepeatedFailureFilter<Failure: Equatable> {
  private var lastReported: Failure?

  /// Returns whether to log `failure`: true unless it repeats the last one logged since the last
  /// success.
  mutating func shouldReport(_ failure: Failure) -> Bool {
    guard failure != lastReported else { return false }
    lastReported = failure
    return true
  }

  /// Records a success, so the next failure is logged whatever it is.
  mutating func succeeded() {
    lastReported = nil
  }
}
