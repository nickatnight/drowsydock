import DockOverlayKit

@testable import DrowsyDock

@MainActor
final class FakeDockTracker: DockTracking {
  private(set) var grants: [Bool] = []
  var onPresentationChange: (@MainActor (OverlayPresentation) -> Void)?

  func accessibilityChanged(isGranted: Bool) {
    grants.append(isGranted)
  }

  func present(_ presentation: OverlayPresentation) {
    onPresentationChange?(presentation)
  }
}
