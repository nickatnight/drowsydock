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

  // The bottom Dock while the pointer magnifies it: the list is 40 points taller and the last
  // icon has grown from 60 to 100 points.
  private var magnifiedDock: DockGeometry {
    DockGeometry(
      listFrame: AXRect(CGRect(x: 350, y: 790, width: 740, height: 110)),
      iconFrames: [AXRect(CGRect(x: 980, y: 794, width: 100, height: 100))],
      layout: laptop
    )
  }

  // The bottom Dock after the user made it smaller.
  private var smallerDock: DockGeometry {
    DockGeometry(
      listFrame: AXRect(CGRect(x: 420, y: 850, width: 600, height: 50)),
      iconFrames: [AXRect(CGRect(x: 975, y: 854, width: 40, height: 40))],
      layout: laptop
    )
  }

  private let awayFromTheDock = CGPoint(x: 700, y: 600)
  private let overTheDock = CGPoint(x: 700, y: 30)

  private func trackerHoveringOverTheDock() -> DockTrackerState {
    var tracker = trackerWithAccessibility()
    tracker.dockRead(bottomDock)
    tracker.pointerMoved(to: overTheDock)
    return tracker
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

  // MARK: - Magnification

  func testTheRestingDockIsNotMagnified() {
    XCTAssertFalse(DockGeometry.isMagnified(current: bottomDock, resting: bottomDock))
  }

  func testATallerListIsMagnified() {
    let taller = DockGeometry(
      listFrame: AXRect(CGRect(x: 370, y: 800, width: 700, height: 100)),
      iconFrames: [AXRect(CGRect(x: 1000, y: 834, width: 60, height: 60))],
      layout: laptop
    )

    XCTAssertTrue(DockGeometry.isMagnified(current: taller, resting: bottomDock))
  }

  func testAWiderSideDockIsMagnified() {
    let restingLeftDock = DockGeometry(
      listFrame: AXRect(CGRect(x: 0, y: 200, width: 70, height: 500)),
      iconFrames: [],
      layout: laptop
    )
    let magnifiedLeftDock = DockGeometry(
      listFrame: AXRect(CGRect(x: 0, y: 200, width: 110, height: 500)),
      iconFrames: [],
      layout: laptop
    )

    XCTAssertTrue(DockGeometry.isMagnified(current: magnifiedLeftDock, resting: restingLeftDock))
  }

  func testAGrownIconInAnUnchangedListIsMagnified() {
    let grownIcon = DockGeometry(
      listFrame: AXRect(CGRect(x: 370, y: 830, width: 700, height: 70)),
      iconFrames: [AXRect(CGRect(x: 990, y: 820, width: 80, height: 80))],
      layout: laptop
    )

    XCTAssertTrue(DockGeometry.isMagnified(current: grownIcon, resting: bottomDock))
  }

  func testASmallerDockIsNotMagnified() {
    XCTAssertFalse(DockGeometry.isMagnified(current: smallerDock, resting: bottomDock))
  }

  func testGrowthWithinAPointIsRoundingNotMagnification() {
    let rounded = DockGeometry(
      listFrame: AXRect(CGRect(x: 370, y: 829.5, width: 700.5, height: 70.5)),
      iconFrames: [AXRect(CGRect(x: 1000, y: 833.5, width: 60.5, height: 60.5))],
      layout: laptop
    )

    XCTAssertFalse(DockGeometry.isMagnified(current: rounded, resting: bottomDock))
  }

  func testIconsAddedOrRemovedAreNotMagnification() {
    let oneMoreIcon = DockGeometry(
      listFrame: AXRect(CGRect(x: 370, y: 830, width: 700, height: 70)),
      iconFrames: [
        AXRect(CGRect(x: 380, y: 834, width: 80, height: 60)),
        AXRect(CGRect(x: 1000, y: 834, width: 60, height: 60)),
      ],
      layout: laptop
    )

    XCTAssertFalse(DockGeometry.isMagnified(current: oneMoreIcon, resting: bottomDock))
  }

  // MARK: - Hover region

  func testTheHoverRegionReachesAMagnifiedIconsHeightAboveTheDock() {
    XCTAssertTrue(bottomDock.hoverRegion.contains(CGPoint(x: 700, y: 70 + 127)))
    XCTAssertFalse(bottomDock.hoverRegion.contains(CGPoint(x: 700, y: 70 + 129)))
  }

  func testTheHoverRegionReachesPastBothEndsOfTheDock() {
    XCTAssertTrue(bottomDock.hoverRegion.contains(CGPoint(x: 370 - 127, y: 30)))
    XCTAssertTrue(bottomDock.hoverRegion.contains(CGPoint(x: 1070 + 127, y: 30)))
    XCTAssertFalse(bottomDock.hoverRegion.contains(CGPoint(x: 1070 + 129, y: 30)))
  }

  // MARK: - Frame checks run only while the pointer is near the Dock

  func testNoFrameChecksRunWhileThePointerIsAwayFromTheDock() {
    var tracker = trackerWithAccessibility()
    tracker.dockRead(bottomDock)

    tracker.pointerMoved(to: awayFromTheDock)

    XCTAssertFalse(tracker.runsFrameChecks)
    XCTAssertEqual(tracker.presentation, .shown(bottomDock.perch(for: sprite)))
  }

  func testFrameChecksRunWhileThePointerIsOverTheDock() {
    let tracker = trackerHoveringOverTheDock()

    XCTAssertTrue(tracker.runsFrameChecks)
    XCTAssertEqual(tracker.presentation, .shown(bottomDock.perch(for: sprite)))
  }

  func testFrameChecksStopWhenThePointerLeaves() {
    var tracker = trackerHoveringOverTheDock()

    tracker.pointerMoved(to: awayFromTheDock)

    XCTAssertFalse(tracker.runsFrameChecks)
    XCTAssertTrue(tracker.awaitsSettledRead)
  }

  func testNoFrameChecksRunWithoutTheGrantWhereverThePointerIs() {
    var tracker = trackerHoveringOverTheDock()

    tracker.accessibilityChanged(isGranted: false)
    tracker.pointerMoved(to: overTheDock)

    XCTAssertFalse(tracker.runsFrameChecks)
    XCTAssertEqual(tracker.presentation, .hidden)
  }

  func testNoFrameChecksRunWhileTheDockIsOffScreen() {
    var tracker = trackerWithAccessibility()
    tracker.dockRead(autoHiddenDock)

    tracker.pointerMoved(to: overTheDock)

    XCTAssertFalse(tracker.runsFrameChecks)
    XCTAssertEqual(tracker.presentation, .hidden)
  }

  // MARK: - Fading out while magnified

  func testAMagnifiedDockFadesTheOverlayOutAtTheRestingPerch() {
    var tracker = trackerHoveringOverTheDock()

    tracker.frameChecked(magnifiedDock)

    XCTAssertEqual(tracker.presentation, .fadedOut(bottomDock.perch(for: sprite)))
  }

  func testTheOverlayFadesBackInWhenTheDockReturnsToRest() {
    var tracker = trackerHoveringOverTheDock()
    tracker.frameChecked(magnifiedDock)

    tracker.frameChecked(bottomDock)

    XCTAssertEqual(tracker.presentation, .shown(bottomDock.perch(for: sprite)))
  }

  func testATriggeredReadWhileMagnifiedKeepsTheRestingPerch() {
    var tracker = trackerHoveringOverTheDock()

    tracker.dockRead(magnifiedDock)

    XCTAssertEqual(tracker.presentation, .fadedOut(bottomDock.perch(for: sprite)))
    XCTAssertTrue(tracker.runsFrameChecks)
  }

  func testAFrameCheckThatFindsASmallerDockMovesThePerch() {
    var tracker = trackerHoveringOverTheDock()

    tracker.frameChecked(smallerDock)

    XCTAssertEqual(tracker.presentation, .shown(smallerDock.perch(for: sprite)))
  }

  func testAFailedFrameCheckChangesNothing() {
    var tracker = trackerHoveringOverTheDock()
    tracker.frameChecked(magnifiedDock)

    tracker.frameChecked(nil)

    XCTAssertEqual(tracker.presentation, .fadedOut(bottomDock.perch(for: sprite)))
    XCTAssertTrue(tracker.runsFrameChecks)
  }

  func testAFrameCheckThatFindsTheDockOffScreenHidesTheOverlay() {
    var tracker = trackerHoveringOverTheDock()

    tracker.frameChecked(autoHiddenDock)

    XCTAssertEqual(tracker.presentation, .hidden)
    XCTAssertFalse(tracker.runsFrameChecks)
  }

  func testAFrameCheckWhileThePointerIsAwayIsIgnored() {
    var tracker = trackerWithAccessibility()
    tracker.dockRead(bottomDock)

    tracker.frameChecked(magnifiedDock)

    XCTAssertEqual(tracker.presentation, .shown(bottomDock.perch(for: sprite)))
  }

  // MARK: - Settling after the pointer leaves

  func testTheOverlayStaysFadedUntilTheSettledRead() {
    var tracker = trackerHoveringOverTheDock()
    tracker.frameChecked(magnifiedDock)

    tracker.pointerMoved(to: awayFromTheDock)

    XCTAssertEqual(tracker.presentation, .fadedOut(bottomDock.perch(for: sprite)))
  }

  func testTheSettledReadShowsTheOverlayAtTheNewPerch() {
    var tracker = trackerHoveringOverTheDock()
    tracker.frameChecked(magnifiedDock)
    tracker.pointerMoved(to: awayFromTheDock)

    tracker.dockRead(smallerDock)

    XCTAssertEqual(tracker.presentation, .shown(smallerDock.perch(for: sprite)))
    XCTAssertFalse(tracker.awaitsSettledRead)
  }

  func testThePointerReturningBeforeTheSettledReadResumesFrameChecks() {
    var tracker = trackerHoveringOverTheDock()
    tracker.frameChecked(magnifiedDock)
    tracker.pointerMoved(to: awayFromTheDock)

    tracker.pointerMoved(to: overTheDock)

    XCTAssertTrue(tracker.runsFrameChecks)
    XCTAssertFalse(tracker.awaitsSettledRead)
    XCTAssertEqual(tracker.presentation, .fadedOut(bottomDock.perch(for: sprite)))
  }

  func testPointerMovesAwayFromARestingDockChangeNothing() {
    var tracker = trackerWithAccessibility()
    tracker.dockRead(bottomDock)
    tracker.pointerMoved(to: awayFromTheDock)

    tracker.pointerMoved(to: CGPoint(x: 100, y: 800))

    XCTAssertFalse(tracker.awaitsSettledRead)
    XCTAssertFalse(tracker.runsFrameChecks)
  }
}
