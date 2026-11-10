import DockOverlayKit

@testable import DrowsyDock

/// Stands in for `DockTracker`: it records the grant it hears about, and the test decides what the
/// overlay shows with `present(_:)`.
@MainActor
final class FakeDockTracker: DockTracking {
  private(set) var grants: [Bool] = []
  private let onPresentationChange: @MainActor (OverlayPresentation) -> Void

  init(onPresentationChange: @escaping @MainActor (OverlayPresentation) -> Void) {
    self.onPresentationChange = onPresentationChange
  }

  func accessibilityChanged(isGranted: Bool) {
    grants.append(isGranted)
  }

  func present(_ presentation: OverlayPresentation) {
    onPresentationChange(presentation)
  }
}
