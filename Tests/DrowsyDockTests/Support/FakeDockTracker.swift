import DockOverlayKit

@testable import DrowsyDock

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
