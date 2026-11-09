import CoreGraphics
import DockOverlayKit
import XCTest

// Display frames are AppKit global coordinates: origin at the bottom-left of the primary display,
// y up. Dock frames go in as Accessibility coordinates: origin at the top-left of the primary
// display, y down. For a 900-point-tall primary display, AppKit y = 900 - AX y - height.
final class DockGeometryTests: XCTestCase {
  private let laptop = CGRect(x: 0, y: 0, width: 1440, height: 900)
  private let mascot = CGSize(width: 64, height: 64)

  private func ax(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> AXRect {
    AXRect(CGRect(x: x, y: y, width: width, height: height))
  }

  // MARK: - Converting Accessibility coordinates

  func testConvertsAnAXRectOnTheOnlyDisplayToAppKitCoordinates() {
    let layout = DisplayLayout(primary: laptop)

    XCTAssertEqual(
      layout.appKitRect(ax(370, 830, 700, 70)),
      CGRect(x: 370, y: 0, width: 700, height: 70)
    )
  }

  func testConvertsAnAXRectOnADisplayStackedAboveThePrimary() {
    let above = CGRect(x: -240, y: 900, width: 1920, height: 1080)
    let layout = DisplayLayout(primary: laptop, others: [above])

    XCTAssertEqual(
      layout.appKitRect(ax(300, -70, 800, 70)),
      CGRect(x: 300, y: 900, width: 800, height: 70)
    )
  }

  func testConvertsAnAXRectOnADisplayWithANegativeOrigin() {
    let leftOfLaptop = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let layout = DisplayLayout(primary: laptop, others: [leftOfLaptop])

    XCTAssertEqual(
      layout.appKitRect(ax(-1920, 100, 70, 500)),
      CGRect(x: -1920, y: 300, width: 70, height: 500)
    )
  }

  // MARK: - Finding the Dock's display

  func testABottomDockOnASingleDisplay() {
    let dock = DockGeometry(
      listFrame: ax(370, 830, 700, 70),
      iconFrames: [ax(380, 834, 60, 60), ax(440, 834, 60, 60), ax(1000, 834, 60, 60)],
      layout: DisplayLayout(primary: laptop)
    )

    XCTAssertEqual(dock.frame, CGRect(x: 370, y: 0, width: 700, height: 70))
    XCTAssertEqual(dock.iconFrames.last, CGRect(x: 1000, y: 6, width: 60, height: 60))
    XCTAssertEqual(dock.screenFrame, laptop)
    XCTAssertEqual(dock.orientation, .bottom)
    XCTAssertFalse(dock.isHidden)
  }

  func testADockOnTheRightOfTwoSideBySideDisplays() {
    let external = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    let dock = DockGeometry(
      listFrame: ax(2000, 830, 800, 70),
      iconFrames: [],
      layout: DisplayLayout(primary: laptop, others: [external])
    )

    XCTAssertEqual(dock.screenFrame, external)
    XCTAssertEqual(dock.frame, CGRect(x: 2000, y: 0, width: 800, height: 70))
    XCTAssertFalse(dock.isHidden)
  }

  func testADockOnADisplayStackedAboveThePrimary() {
    let above = CGRect(x: -240, y: 900, width: 1920, height: 1080)
    let dock = DockGeometry(
      listFrame: ax(300, -70, 800, 70),
      iconFrames: [],
      layout: DisplayLayout(primary: laptop, others: [above])
    )

    XCTAssertEqual(dock.screenFrame, above)
    XCTAssertEqual(dock.orientation, .bottom)
    XCTAssertFalse(dock.isHidden)
  }

  func testALeftDockOnADisplayWithANegativeOrigin() {
    let leftOfLaptop = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let dock = DockGeometry(
      listFrame: ax(-1920, 100, 70, 500),
      iconFrames: [ax(-1915, 105, 60, 60)],
      layout: DisplayLayout(primary: laptop, others: [leftOfLaptop])
    )

    XCTAssertEqual(dock.screenFrame, leftOfLaptop)
    XCTAssertEqual(dock.orientation, .left)
    XCTAssertFalse(dock.isHidden)
  }

  func testARightDock() {
    let dock = DockGeometry(
      listFrame: ax(1370, 200, 70, 500),
      iconFrames: [],
      layout: DisplayLayout(primary: laptop)
    )

    XCTAssertEqual(dock.orientation, .right)
  }

  func testALeftDockOnADisplayToTheRightOfThePrimary() {
    let external = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    let dock = DockGeometry(
      listFrame: ax(1440, 100, 70, 500),
      iconFrames: [ax(1445, 105, 60, 60)],
      layout: DisplayLayout(primary: laptop, others: [external])
    )

    XCTAssertEqual(dock.screenFrame, external)
    XCTAssertEqual(dock.orientation, .left)
    XCTAssertEqual(dock.perch(for: mascot).facing, .right)
  }

  func testARightDockOnADisplayWithANegativeOrigin() {
    let leftOfLaptop = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let dock = DockGeometry(
      listFrame: ax(-70, 100, 70, 500),
      iconFrames: [ax(-65, 105, 60, 60)],
      layout: DisplayLayout(primary: laptop, others: [leftOfLaptop])
    )

    XCTAssertEqual(dock.screenFrame, leftOfLaptop)
    XCTAssertEqual(dock.orientation, .right)
    XCTAssertEqual(dock.perch(for: mascot).facing, .left)
  }

  func testWithThreeDisplaysTheDockBelongsToTheNearestNotTheLastCloserThanThePrimary() {
    let middle = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    let farRight = CGRect(x: 3360, y: 0, width: 1920, height: 1080)
    let dock = DockGeometry(
      listFrame: ax(2800, 830, 500, 70),
      iconFrames: [],
      layout: DisplayLayout(primary: laptop, others: [middle, farRight])
    )

    XCTAssertEqual(dock.screenFrame, middle)
  }

  func testADockStraddlingTwoDisplaysBelongsToTheOneHoldingItsCentre() {
    let external = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    let dock = DockGeometry(
      listFrame: ax(1340, 830, 400, 70),
      iconFrames: [],
      layout: DisplayLayout(primary: laptop, others: [external])
    )

    XCTAssertEqual(dock.screenFrame, external)
  }

  // MARK: - Auto-hide

  func testAnAutoHiddenDockPeekingOverTheEdgeIsHidden() {
    let dock = DockGeometry(
      listFrame: ax(370, 896, 700, 70),
      iconFrames: [],
      layout: DisplayLayout(primary: laptop)
    )

    XCTAssertEqual(dock.screenFrame, laptop)
    XCTAssertTrue(dock.isHidden)
  }

  func testAnAutoHiddenDockFullyOffscreenBelongsToTheNearestDisplay() {
    let external = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    let dock = DockGeometry(
      listFrame: ax(2000, 900, 800, 70),
      iconFrames: [],
      layout: DisplayLayout(primary: laptop, others: [external])
    )

    XCTAssertEqual(dock.screenFrame, external)
    XCTAssertTrue(dock.isHidden)
  }

  func testADockWithAnEmptyFrameIsHidden() {
    let dock = DockGeometry(
      listFrame: ax(720, 900, 0, 0),
      iconFrames: [],
      layout: DisplayLayout(primary: laptop)
    )

    XCTAssertTrue(dock.isHidden)
  }

  func testADockFlushWithTheDisplayEdgesIsVisible() {
    let dock = DockGeometry(
      listFrame: ax(0, 830, 1440, 70),
      iconFrames: [],
      layout: DisplayLayout(primary: laptop)
    )

    XCTAssertFalse(dock.isHidden)
  }

  func testADockHalfAPointPastTheDisplayEdgeIsVisible() {
    let dock = DockGeometry(
      listFrame: ax(370, 830.5, 700, 70),
      iconFrames: [],
      layout: DisplayLayout(primary: laptop)
    )

    XCTAssertFalse(dock.isHidden)
  }

  func testADockTwoPointsPastTheDisplayEdgeIsHidden() {
    let dock = DockGeometry(
      listFrame: ax(370, 832, 700, 70),
      iconFrames: [],
      layout: DisplayLayout(primary: laptop)
    )

    XCTAssertTrue(dock.isHidden)
  }

  // MARK: - Background

  // macOS 26 and later report the list frame 5 points further from the screen edge than the
  // background the Dock draws. The items, the same thickness as the list, line up with the
  // background. These fixtures follow a real bottom Dock on macOS 27: list 79 points thick, items
  // 63 × 79 and 5 points nearer the bottom edge.

  func testABottomDocksBackgroundSlidesDownToHoldItemsThatSitBelowTheList() {
    let dock = DockGeometry(
      listFrame: ax(370, 816, 700, 79),
      iconFrames: [ax(378, 821, 63, 79), ax(999, 821, 63, 79)],
      layout: DisplayLayout(primary: laptop)
    )

    XCTAssertEqual(dock.backgroundFrame, CGRect(x: 370, y: 0, width: 700, height: 79))
  }

  func testALeftDocksBackgroundSlidesLeftToHoldItemsThatSitPastTheList() {
    let dock = DockGeometry(
      listFrame: ax(5, 200, 79, 500),
      iconFrames: [ax(0, 208, 79, 63), ax(0, 271, 79, 63)],
      layout: DisplayLayout(primary: laptop)
    )

    XCTAssertEqual(dock.backgroundFrame, CGRect(x: 0, y: 200, width: 79, height: 500))
  }

  func testARightDocksBackgroundSlidesRightToHoldItemsThatSitPastTheList() {
    let dock = DockGeometry(
      listFrame: ax(1356, 200, 79, 500),
      iconFrames: [ax(1361, 208, 79, 63), ax(1361, 271, 79, 63)],
      layout: DisplayLayout(primary: laptop)
    )

    XCTAssertEqual(dock.backgroundFrame, CGRect(x: 1361, y: 200, width: 79, height: 500))
  }

  func testWhereTheListHoldsItsIconsTheBackgroundIsTheListFrame() {
    let dock = DockGeometry(
      listFrame: ax(370, 830, 700, 70),
      iconFrames: [ax(380, 834, 60, 60), ax(1000, 834, 60, 60)],
      layout: DisplayLayout(primary: laptop)
    )

    XCTAssertEqual(dock.backgroundFrame, dock.frame)
  }

  func testWithNoIconsTheBackgroundIsTheListFrame() {
    let dock = DockGeometry(
      listFrame: ax(370, 830, 700, 70),
      iconFrames: [],
      layout: DisplayLayout(primary: laptop)
    )

    XCTAssertEqual(dock.backgroundFrame, dock.frame)
  }

  // On macOS 27.0.1 a 79-point-thick Dock's drawn corners fit a circle of about 22 points: traced
  // from a 2× screenshot, the outline's inset from the straight edge matched a 44-pixel radius
  // within 2 pixels on every row from 2 to 35 pixels in from the top and bottom edges.
  func testTheBackgroundsCornersMatchTheMeasuredDock() {
    let bottom = DockGeometry(
      listFrame: ax(370, 816, 700, 79),
      iconFrames: [ax(378, 821, 63, 79)],
      layout: DisplayLayout(primary: laptop)
    )
    let left = DockGeometry(
      listFrame: ax(0, 200, 79, 500),
      iconFrames: [ax(0, 208, 79, 63)],
      layout: DisplayLayout(primary: laptop)
    )

    XCTAssertEqual(bottom.backgroundCornerRadius, 22, accuracy: 0.5)
    XCTAssertEqual(left.backgroundCornerRadius, 22, accuracy: 0.5)
  }

  // MARK: - Perch

  func testOnABottomDockThePerchSitsOnTheTopEdgeInsideTheLastIcon() {
    let dock = DockGeometry(
      listFrame: ax(370, 830, 700, 70),
      iconFrames: [ax(380, 834, 60, 60), ax(1000, 834, 60, 60)],
      layout: DisplayLayout(primary: laptop)
    )

    XCTAssertEqual(
      dock.perch(for: mascot),
      DockPerch(frame: CGRect(x: 996, y: 70, width: 64, height: 64), facing: .left)
    )
  }

  func testOnABottomDockWithNoIconsThePerchSitsAtTheTrailingEnd() {
    let dock = DockGeometry(
      listFrame: ax(370, 830, 700, 70),
      iconFrames: [],
      layout: DisplayLayout(primary: laptop)
    )

    XCTAssertEqual(dock.perch(for: mascot).frame, CGRect(x: 1006, y: 70, width: 64, height: 64))
  }

  func testOnALeftDockThePerchSitsAboveTheFirstIconFacingTheScreen() {
    let leftOfLaptop = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let dock = DockGeometry(
      listFrame: ax(-1920, 100, 70, 500),
      iconFrames: [ax(-1915, 105, 60, 60), ax(-1915, 165, 60, 60)],
      layout: DisplayLayout(primary: laptop, others: [leftOfLaptop])
    )

    XCTAssertEqual(
      dock.perch(for: mascot),
      DockPerch(frame: CGRect(x: -1917, y: 800, width: 64, height: 64), facing: .right)
    )
  }

  func testOnARightDockThePerchSitsAboveTheFirstIconFacingTheScreen() {
    let dock = DockGeometry(
      listFrame: ax(1370, 200, 70, 500),
      iconFrames: [ax(1375, 205, 60, 60), ax(1375, 265, 60, 60)],
      layout: DisplayLayout(primary: laptop)
    )

    XCTAssertEqual(
      dock.perch(for: mascot),
      DockPerch(frame: CGRect(x: 1373, y: 700, width: 64, height: 64), facing: .left)
    )
  }

  func testThePerchStaysOnTheDockDisplayWhenATallSideDockLeavesNoRoomAbove() {
    let dock = DockGeometry(
      listFrame: ax(0, 10, 50, 840),
      iconFrames: [ax(5, 15, 40, 40)],
      layout: DisplayLayout(primary: laptop)
    )

    XCTAssertEqual(dock.perch(for: mascot).frame, CGRect(x: 0, y: 836, width: 64, height: 64))
  }

  func testOnATallSideDockThePerchStaysBelowTheMenuBar() {
    let belowTheMenuBar = DisplayLayout.Display(
      frame: laptop,
      visibleFrame: CGRect(x: 50, y: 0, width: 1390, height: 875)
    )
    let dock = DockGeometry(
      listFrame: ax(0, 10, 50, 840),
      iconFrames: [ax(5, 15, 40, 40)],
      layout: DisplayLayout(primary: belowTheMenuBar)
    )

    XCTAssertEqual(dock.perch(for: mascot).frame, CGRect(x: 0, y: 811, width: 64, height: 64))
  }

  func testThePerchOfALeftDockStaysOverTheDockOutsideTheVisibleFrame() {
    let besideTheDock = DisplayLayout.Display(
      frame: laptop,
      visibleFrame: CGRect(x: 70, y: 0, width: 1370, height: 875)
    )
    let dock = DockGeometry(
      listFrame: ax(0, 200, 70, 500),
      iconFrames: [ax(5, 205, 60, 60)],
      layout: DisplayLayout(primary: besideTheDock)
    )

    XCTAssertEqual(dock.perch(for: mascot).frame, CGRect(x: 3, y: 700, width: 64, height: 64))
  }

  func testThePerchOfABottomDockStaysOnTheDockEdgeBelowTheVisibleFrame() {
    let aboveTheDock = DisplayLayout.Display(
      frame: laptop,
      visibleFrame: CGRect(x: 0, y: 75, width: 1440, height: 800)
    )
    let dock = DockGeometry(
      listFrame: ax(370, 830, 700, 70),
      iconFrames: [ax(1000, 834, 60, 60)],
      layout: DisplayLayout(primary: aboveTheDock)
    )

    XCTAssertEqual(dock.perch(for: mascot).frame, CGRect(x: 996, y: 70, width: 64, height: 64))
  }

  // MARK: - Icons along the Dock

  func testOnABottomDockTheIconsRunLeftToRight() {
    let layout = DisplayLayout(primary: laptop)
    let left = ax(380, 834, 60, 60)
    let middle = ax(700, 834, 60, 60)
    let right = ax(1000, 834, 60, 60)
    let dock = DockGeometry(
      listFrame: ax(370, 830, 700, 70),
      iconFrames: [right, left, middle],
      layout: layout
    )

    XCTAssertEqual(dock.iconFramesAlongDock, [left, middle, right].map(layout.appKitRect))
  }

  func testOnALeftDockTheIconsRunTopToBottom() {
    let layout = DisplayLayout(primary: laptop)
    let top = ax(5, 205, 60, 60)
    let middle = ax(5, 400, 60, 60)
    let bottom = ax(5, 600, 60, 60)
    let dock = DockGeometry(
      listFrame: ax(0, 200, 70, 500),
      iconFrames: [middle, top, bottom],
      layout: layout
    )

    XCTAssertEqual(dock.iconFramesAlongDock, [top, middle, bottom].map(layout.appKitRect))
  }

  func testOnARightDockTheIconsRunTopToBottom() {
    let layout = DisplayLayout(primary: laptop)
    let top = ax(1375, 205, 60, 60)
    let bottom = ax(1375, 600, 60, 60)
    let dock = DockGeometry(
      listFrame: ax(1370, 200, 70, 500),
      iconFrames: [bottom, top],
      layout: layout
    )

    XCTAssertEqual(dock.iconFramesAlongDock, [top, bottom].map(layout.appKitRect))
  }

  func testThePerchStaysOnTheDisplayWhenANarrowRightDockWouldPushItPastTheEdge() {
    let dock = DockGeometry(
      listFrame: ax(1390, 200, 50, 500),
      iconFrames: [ax(1395, 205, 40, 40)],
      layout: DisplayLayout(primary: laptop)
    )

    XCTAssertEqual(dock.perch(for: mascot).frame, CGRect(x: 1376, y: 700, width: 64, height: 64))
  }
}
