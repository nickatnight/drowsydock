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

  func testThePerchIsReadFromTheLineDockTrackerLogs() throws {
    let perch = dock.perch(for: CGSize(width: 64, height: 80))
    for presentation in [OverlayPresentation.shown(perch, on: dock), .fadedOut(perch, on: dock)] {
      let line =
        "2026-11-09T22:10:01.123+01:00 DrowsyDock[123] debug dock: Overlay: \(presentation)"

      XCTAssertEqual(OverlayLog.perchFrame(in: line), perch.frame)
    }
  }

  func testALineWithoutAPerchHasNone() {
    XCTAssertNil(OverlayLog.perchFrame(in: "Overlay: hidden"))
    XCTAssertNil(OverlayLog.perchFrame(in: "DockPerch(frame: (1, 2, 3), facing"))
  }

  func testTheFacingIsReadFromTheSameLine() {
    for facing in [DockPerch.Facing.left, .right] {
      let perch = DockPerch(frame: CGRect(x: 10, y: 84, width: 64, height: 80), facing: facing)
      let line = "Overlay: \(OverlayPresentation.shown(perch, on: dock))"

      XCTAssertEqual(OverlayLog.perchFacing(in: line), facing == .left ? "left" : "right")
    }
    XCTAssertNil(OverlayLog.perchFacing(in: "Overlay: hidden"))
  }

  func testTheTimeIsReadFromTheLinesTimestampWithItsOffsetFromUTC() throws {
    let local = "2026-11-10T01:31:07.123+01:00 DrowsyDock[123] debug dock: Overlay: hidden"
    let utc = "2026-11-10T00:31:07.123Z DrowsyDock[123] debug dock: Overlay: hidden"

    XCTAssertEqual(try XCTUnwrap(OverlayLog.time(of: local)), 1_794_270_667.123, accuracy: 0.0005)
    XCTAssertEqual(try XCTUnwrap(OverlayLog.time(of: utc)), 1_794_270_667.123, accuracy: 0.0005)
    XCTAssertNil(OverlayLog.time(of: "Overlay: hidden"))
    XCTAssertNil(OverlayLog.time(of: ""))
  }
}
