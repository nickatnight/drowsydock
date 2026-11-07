import CoreGraphics
import DockOverlayKit
import XCTest

final class DockTrackerTests: XCTestCase {
  private let laptop = DisplayLayout(primary: CGRect(x: 0, y: 0, width: 1440, height: 900))
  private let sprite = CGSize(width: 64, height: 64)

  // A bottom Dock 700 x 70 points at the bottom of a 1440 x 900 display.
  private var bottomDock: DockGeometry {
    DockGeometry(
      listFrame: AXRect(CGRect(x: 370, y: 830, width: 700, height: 70)),
      iconFrames: [AXRect(CGRect(x: 1000, y: 834, width: 60, height: 60))],
      layout: laptop
    )
  }

  // The same Dock, auto-hidden: all but 4 points of it lie below the display.
  private var autoHiddenDock: DockGeometry {
    DockGeometry(
      listFrame: AXRect(CGRect(x: 370, y: 896, width: 700, height: 70)),
      iconFrames: [],
      layout: laptop
    )
  }

  private func trackerWithAccessibility() -> DockTrackerState {
    var tracker = DockTrackerState(spriteSize: sprite)
    tracker.accessibilityChanged(isGranted: true)
    return tracker
  }

  // MARK: - Accessibility

  func testTheOverlayIsHiddenBeforeTheGrantIsKnown() {
    XCTAssertEqual(DockTrackerState(spriteSize: sprite).presentation, .hidden)
  }

  func testTheOverlayStaysHiddenWithoutTheGrant() {
    var tracker = DockTrackerState(spriteSize: sprite)
    tracker.accessibilityChanged(isGranted: false)
    tracker.dockRead(bottomDock)

    XCTAssertEqual(tracker.presentation, .hidden)
  }

  func testRevokingTheGrantHidesTheOverlay() {
    var tracker = trackerWithAccessibility()
    tracker.dockRead(bottomDock)

    tracker.accessibilityChanged(isGranted: false)

    XCTAssertEqual(tracker.presentation, .hidden)
  }

  func testAfterTheGrantReturnsTheOverlayWaitsForAFreshRead() {
    var tracker = trackerWithAccessibility()
    tracker.dockRead(bottomDock)
    tracker.accessibilityChanged(isGranted: false)

    tracker.accessibilityChanged(isGranted: true)

    XCTAssertEqual(tracker.presentation, .hidden)
  }

  func testARepeatedGrantKeepsTheOverlayInPlace() {
    var tracker = trackerWithAccessibility()
    tracker.dockRead(bottomDock)

    tracker.accessibilityChanged(isGranted: true)

    XCTAssertEqual(tracker.presentation, .shown(bottomDock.perch(for: sprite)))
  }

  // MARK: - Dock reads

  func testAVisibleDockShowsTheOverlayAtThePerch() {
    var tracker = trackerWithAccessibility()

    tracker.dockRead(bottomDock)

    XCTAssertEqual(
      tracker.presentation,
      .shown(DockPerch(frame: CGRect(x: 996, y: 70, width: 64, height: 64), facing: .left))
    )
  }

  func testAnAutoHiddenDockHidesTheOverlay() {
    var tracker = trackerWithAccessibility()
    tracker.dockRead(bottomDock)

    tracker.dockRead(autoHiddenDock)

    XCTAssertEqual(tracker.presentation, .hidden)
  }

  func testAFailedReadHidesTheOverlay() {
    var tracker = trackerWithAccessibility()
    tracker.dockRead(bottomDock)

    tracker.dockRead(nil)

    XCTAssertEqual(tracker.presentation, .hidden)
  }
}
