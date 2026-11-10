import DockOverlayKit

@testable import DrowsyDock

@MainActor
final class FakeDockTracker: DockTracking {
  private(set) var grants: [Bool] = []
  var onPresentationChange: (@MainActor (OverlayPresentation) -> Void)?

  // Like DockTracker, a missing grant hides the overlay.
  func accessibilityChanged(isGranted: Bool) {
    grants.append(isGranted)
    if !isGranted {
      present(.hidden)
    }
  }

  func present(_ presentation: OverlayPresentation) {
    onPresentationChange?(presentation)
  }
}
