import CoreGraphics
import DockOverlayKit
import XCTest

final class DockTrackerTests: XCTestCase {
  private let laptop = DisplayLayout(primary: CGRect(x: 0, y: 0, width: 1440, height: 900))
  private let sprite = CGSize(width: 64, height: 64)

  private var bottomDock: DockGeometry {
    DockGeometry(
      listFrame: AXRect(CGRect(x: 370, y: 830, width: 700, height: 70)),
      iconFrames: [AXRect(CGRect(x: 1000, y: 834, width: 60, height: 60))],
      layout: laptop
    )
  }

  private var autoHiddenDock: DockGeometry {
    DockGeometry(
      listFrame: AXRect(CGRect(x: 370, y: 896, width: 700, height: 70)),
      iconFrames: [],
      layout: laptop
    )
  }

  private var magnifiedDock: DockGeometry {
    DockGeometry(
      listFrame: AXRect(CGRect(x: 350, y: 790, width: 740, height: 110)),
      iconFrames: [AXRect(CGRect(x: 980, y: 794, width: 100, height: 100))],
      layout: laptop
    )
  }

  private var smallerDock: DockGeometry {
    DockGeometry(
      listFrame: AXRect(CGRect(x: 420, y: 850, width: 600, height: 50)),
      iconFrames: [AXRect(CGRect(x: 975, y: 854, width: 40, height: 40))],
      layout: laptop
    )
  }

  private let awayFromTheDock = CGPoint(x: 700, y: 600)
  private let overTheDock = CGPoint(x: 700, y: 30)
  // Above the resting Dock's top edge (y 70) but inside its hover region (up to y 198), where a
  // magnified icon can be.
  private let nearTheDock = CGPoint(x: 700, y: 150)

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

    XCTAssertEqual(tracker.presentation, .shown(bottomDock.perch(for: sprite), on: bottomDock))
  }

  // MARK: - Dock reads

  func testAVisibleDockShowsTheOverlayAtThePerch() {
    var tracker = trackerWithAccessibility()

    tracker.dockRead(bottomDock)

    XCTAssertEqual(
      tracker.presentation,
      .shown(
        DockPerch(frame: CGRect(x: 996, y: 70, width: 64, height: 64), facing: .left),
        on: bottomDock
      )
    )
  }

  func testAnAutoHiddenDockHidesTheOverlay() {
    var tracker = trackerWithAccessibility()
    tracker.dockRead(bottomDock)

    tracker.dockRead(autoHiddenDock)

    XCTAssertEqual(tracker.presentation, .hidden)
  }

  func testTheOverlayReturnsWhenAnAutoHiddenDockComesBackOnScreen() {
    var tracker = trackerWithAccessibility()
    tracker.dockRead(autoHiddenDock)

    tracker.dockRead(bottomDock)

    XCTAssertEqual(tracker.presentation, .shown(bottomDock.perch(for: sprite), on: bottomDock))
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

  func testGrowthOfTwoPointsIsMagnification() {
    let twoPointsTaller = DockGeometry(
      listFrame: AXRect(CGRect(x: 370, y: 828, width: 700, height: 72)),
      iconFrames: [AXRect(CGRect(x: 1000, y: 834, width: 60, height: 60))],
      layout: laptop
    )

    XCTAssertTrue(DockGeometry.isMagnified(current: twoPointsTaller, resting: bottomDock))
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
    XCTAssertEqual(tracker.presentation, .shown(bottomDock.perch(for: sprite), on: bottomDock))
  }

  func testFrameChecksRunWhileThePointerIsOverTheDock() {
    let tracker = trackerHoveringOverTheDock()

    XCTAssertTrue(tracker.runsFrameChecks)
    XCTAssertEqual(tracker.presentation, .shown(bottomDock.perch(for: sprite), on: bottomDock))
  }

  func testFrameChecksStopWhenThePointerLeaves() {
    var tracker = trackerHoveringOverTheDock()

    tracker.pointerMoved(to: awayFromTheDock)

    XCTAssertFalse(tracker.runsFrameChecks)
    XCTAssertTrue(tracker.awaitsSettledRead)
  }

  func testFrameChecksRunWhileThePointerIsNearTheDockAboveItsFrame() {
    var tracker = trackerWithAccessibility()
    tracker.dockRead(bottomDock)

    tracker.pointerMoved(to: nearTheDock)

    XCTAssertTrue(tracker.runsFrameChecks)
  }

  func testThePointerOverAMagnifiedIconAboveTheFrameKeepsTheDockHovered() {
    var tracker = trackerHoveringOverTheDock()
    tracker.frameChecked(magnifiedDock)

    tracker.pointerMoved(to: nearTheDock)

    XCTAssertTrue(tracker.runsFrameChecks)
    XCTAssertFalse(tracker.awaitsSettledRead)
    XCTAssertEqual(tracker.presentation, .fadedOut(bottomDock.perch(for: sprite), on: bottomDock))
  }

  func testThePointerReturningNearTheDockWhileSettlingResumesFrameChecks() {
    var tracker = trackerHoveringOverTheDock()
    tracker.pointerMoved(to: awayFromTheDock)

    tracker.pointerMoved(to: nearTheDock)

    XCTAssertTrue(tracker.runsFrameChecks)
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

    XCTAssertEqual(tracker.presentation, .fadedOut(bottomDock.perch(for: sprite), on: bottomDock))
  }

  func testTheOverlayFadesBackInWhenTheDockReturnsToRest() {
    var tracker = trackerHoveringOverTheDock()
    tracker.frameChecked(magnifiedDock)

    tracker.frameChecked(bottomDock)

    XCTAssertEqual(tracker.presentation, .shown(bottomDock.perch(for: sprite), on: bottomDock))
  }

  func testATriggeredReadWhileMagnifiedKeepsTheRestingPerch() {
    var tracker = trackerHoveringOverTheDock()

    tracker.dockRead(magnifiedDock)

    XCTAssertEqual(tracker.presentation, .fadedOut(bottomDock.perch(for: sprite), on: bottomDock))
    XCTAssertTrue(tracker.runsFrameChecks)
  }

  func testAFrameCheckThatFindsASmallerDockMovesThePerch() {
    var tracker = trackerHoveringOverTheDock()

    tracker.frameChecked(smallerDock)

    XCTAssertEqual(tracker.presentation, .shown(smallerDock.perch(for: sprite), on: smallerDock))
  }

  func testAReadWhileHoveringThatFindsALeftDockShowsTheLeftPerch() {
    var tracker = trackerHoveringOverTheDock()
    let leftDock = DockGeometry(
      listFrame: AXRect(CGRect(x: 0, y: 200, width: 70, height: 500)),
      iconFrames: [AXRect(CGRect(x: 5, y: 205, width: 60, height: 60))],
      layout: laptop
    )

    tracker.dockRead(leftDock)

    XCTAssertEqual(tracker.presentation, .shown(leftDock.perch(for: sprite), on: leftDock))
  }

  func testAReadWhileHoveringThatFindsTheDockOnAnotherDisplayMovesThePerch() {
    let external = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    let twoDisplays = DisplayLayout(primary: laptop.primary.frame, others: [external])
    let dockOnLaptop = DockGeometry(
      listFrame: AXRect(CGRect(x: 370, y: 830, width: 700, height: 70)),
      iconFrames: [],
      layout: twoDisplays
    )
    let tallerDockOnExternal = DockGeometry(
      listFrame: AXRect(CGRect(x: 2000, y: 800, width: 800, height: 100)),
      iconFrames: [],
      layout: twoDisplays
    )
    var tracker = trackerWithAccessibility()
    tracker.dockRead(dockOnLaptop)
    tracker.pointerMoved(to: overTheDock)

    tracker.dockRead(tallerDockOnExternal)

    XCTAssertEqual(
      tracker.presentation,
      .shown(tallerDockOnExternal.perch(for: sprite), on: tallerDockOnExternal))
  }

  func testAFailedTriggeredReadWhileHoveringKeepsTheOverlay() {
    var tracker = trackerHoveringOverTheDock()

    tracker.dockRead(nil)

    XCTAssertEqual(tracker.presentation, .shown(bottomDock.perch(for: sprite), on: bottomDock))
    XCTAssertTrue(tracker.runsFrameChecks)
  }

  func testAFailedFrameCheckChangesNothing() {
    var tracker = trackerHoveringOverTheDock()
    tracker.frameChecked(magnifiedDock)

    tracker.frameChecked(nil)

    XCTAssertEqual(tracker.presentation, .fadedOut(bottomDock.perch(for: sprite), on: bottomDock))
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

    XCTAssertEqual(tracker.presentation, .shown(bottomDock.perch(for: sprite), on: bottomDock))
  }

  // MARK: - Uncovering the label of the icon under the perch

  // The bottom Dock's last icon spans x 1000 to 1060 and AppKit y 6 to 66. The perch sits on top of
  // it, from y 70 to 134. The Dock shows the icon's label right there.
  private let overThePerchIcon = CGPoint(x: 1030, y: 30)
  private let overThePerch = CGPoint(x: 1030, y: 110)

  func testThePointerOverTheIconUnderThePerchFadesTheOverlayOut() {
    var tracker = trackerHoveringOverTheDock()

    tracker.pointerMoved(to: overThePerchIcon)

    XCTAssertEqual(tracker.presentation, .fadedOut(bottomDock.perch(for: sprite), on: bottomDock))
  }

  func testThePointerOverThePerchFadesTheOverlayOut() {
    var tracker = trackerHoveringOverTheDock()

    tracker.pointerMoved(to: overThePerch)

    XCTAssertEqual(tracker.presentation, .fadedOut(bottomDock.perch(for: sprite), on: bottomDock))
  }

  func testTheOverlayFadesBackInWhenThePointerMovesToAnotherIcon() {
    var tracker = trackerHoveringOverTheDock()
    tracker.pointerMoved(to: overThePerchIcon)

    tracker.pointerMoved(to: overTheDock)

    XCTAssertEqual(tracker.presentation, .shown(bottomDock.perch(for: sprite), on: bottomDock))
  }

  func testTheOverlayFadesBackInWhenThePointerLeavesFromThePerchIcon() {
    var tracker = trackerHoveringOverTheDock()
    tracker.pointerMoved(to: overThePerchIcon)

    tracker.pointerMoved(to: awayFromTheDock)

    XCTAssertEqual(tracker.presentation, .shown(bottomDock.perch(for: sprite), on: bottomDock))
  }

  func testOnALeftDockThePointerOverTheFirstIconFadesTheOverlayOut() {
    let leftDock = DockGeometry(
      listFrame: AXRect(CGRect(x: 0, y: 200, width: 70, height: 500)),
      iconFrames: [
        AXRect(CGRect(x: 5, y: 205, width: 60, height: 60)),
        AXRect(CGRect(x: 5, y: 265, width: 60, height: 60)),
      ],
      layout: laptop
    )
    var tracker = trackerWithAccessibility()
    tracker.dockRead(leftDock)

    tracker.pointerMoved(to: CGPoint(x: 35, y: 665))

    XCTAssertEqual(tracker.presentation, .fadedOut(leftDock.perch(for: sprite), on: leftDock))
  }

  // MARK: - Settling after the pointer leaves

  func testTheOverlayStaysFadedUntilTheSettledRead() {
    var tracker = trackerHoveringOverTheDock()
    tracker.frameChecked(magnifiedDock)

    tracker.pointerMoved(to: awayFromTheDock)

    XCTAssertEqual(tracker.presentation, .fadedOut(bottomDock.perch(for: sprite), on: bottomDock))
  }

  func testAnUnmagnifiedDockStaysShownWhileSettling() {
    var tracker = trackerHoveringOverTheDock()

    tracker.pointerMoved(to: awayFromTheDock)

    XCTAssertEqual(tracker.presentation, .shown(bottomDock.perch(for: sprite), on: bottomDock))
  }

  func testAFailedSettledReadHidesTheOverlay() {
    var tracker = trackerHoveringOverTheDock()
    tracker.pointerMoved(to: awayFromTheDock)

    tracker.dockRead(nil)

    XCTAssertEqual(tracker.presentation, .hidden)
  }

  func testTheSettledReadShowsTheOverlayAtTheNewPerch() {
    var tracker = trackerHoveringOverTheDock()
    tracker.frameChecked(magnifiedDock)
    tracker.pointerMoved(to: awayFromTheDock)

    tracker.dockRead(smallerDock)

    XCTAssertEqual(tracker.presentation, .shown(smallerDock.perch(for: sprite), on: smallerDock))
    XCTAssertFalse(tracker.awaitsSettledRead)
  }

  func testThePointerReturningBeforeTheSettledReadResumesFrameChecks() {
    var tracker = trackerHoveringOverTheDock()
    tracker.frameChecked(magnifiedDock)
    tracker.pointerMoved(to: awayFromTheDock)

    tracker.pointerMoved(to: overTheDock)

    XCTAssertTrue(tracker.runsFrameChecks)
    XCTAssertFalse(tracker.awaitsSettledRead)
    XCTAssertEqual(tracker.presentation, .fadedOut(bottomDock.perch(for: sprite), on: bottomDock))
  }

  // MARK: - Reading at once on a Dock event

  func testADockEventReadsAtOnceWhileNoReadHasSucceeded() {
    let tracker = trackerWithAccessibility()

    XCTAssertTrue(tracker.readsAtOnceOnDockChange)
  }

  func testADockEventReadsAtOnceWhileTheDockIsOffScreen() {
    var tracker = trackerWithAccessibility()
    tracker.dockRead(autoHiddenDock)

    XCTAssertTrue(tracker.readsAtOnceOnDockChange)
  }

  func testADockEventReadsAtOnceWhileTheDockRests() {
    var tracker = trackerWithAccessibility()
    tracker.dockRead(bottomDock)

    XCTAssertTrue(tracker.readsAtOnceOnDockChange)
  }

  func testADockEventWaitsForTheFrameChecksWhileThePointerIsNearTheDock() {
    let tracker = trackerHoveringOverTheDock()

    XCTAssertFalse(tracker.readsAtOnceOnDockChange)
  }

  func testADockEventWaitsForTheSettledReadAfterThePointerLeaves() {
    var tracker = trackerHoveringOverTheDock()
    tracker.pointerMoved(to: awayFromTheDock)

    XCTAssertFalse(tracker.readsAtOnceOnDockChange)
  }

  func testADockEventReadsNothingWithoutTheGrant() {
    XCTAssertFalse(DockTrackerState(spriteSize: sprite).readsAtOnceOnDockChange)
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
