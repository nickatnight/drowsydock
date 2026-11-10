import CoreGraphics
import DockOverlayKit
import LiveQAKit
import XCTest

final class OverlayLogTests: XCTestCase {
  private let dock = DockGeometry(
    listFrame: AXRect(CGRect(x: 373, y: 893, width: 766, height: 79)),
    iconFrames: [AXRect(CGRect(x: 1071, y: 898, width: 63, height: 79))],
    layout: DisplayLayout(primary: CGRect(x: 0, y: 0, width: 1512, height: 982))
  )

  // DockTracker logs `Overlay: \(String(describing: presentation))`.
  func testThePerchIsReadFromTheLineDockTrackerLogs() throws {
    let perch = dock.perch(for: CGSize(width: 64, height: 80))
    for presentation in [OverlayPresentation.shown(perch, on: dock), .fadedOut(perch, on: dock)] {
      let line = "2026-11-09 22:10:01.123 Db DrowsyDock[123:456] Overlay: \(presentation)"

      XCTAssertEqual(OverlayLog.perchFrame(in: line), perch.frame)
    }
  }

  func testALineWithoutAPerchHasNone() {
    XCTAssertNil(OverlayLog.perchFrame(in: "Overlay: hidden"))
    XCTAssertNil(OverlayLog.perchFrame(in: "DockPerch(frame: (1, 2, 3), facing"))
  }
}
