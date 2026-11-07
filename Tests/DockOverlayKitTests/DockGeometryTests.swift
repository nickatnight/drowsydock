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

  func testThePerchStaysOnTheDisplayWhenANarrowRightDockWouldPushItPastTheEdge() {
    let dock = DockGeometry(
      listFrame: ax(1390, 200, 50, 500),
      iconFrames: [ax(1395, 205, 40, 40)],
      layout: DisplayLayout(primary: laptop)
    )

    XCTAssertEqual(dock.perch(for: mascot).frame, CGRect(x: 1376, y: 700, width: 64, height: 64))
  }
}
