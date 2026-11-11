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

  func testTheFacingIsReadFromTheSameLine() {
    for facing in [DockPerch.Facing.left, .right] {
      let perch = DockPerch(frame: CGRect(x: 10, y: 84, width: 64, height: 80), facing: facing)
      let line = "Overlay: \(OverlayPresentation.shown(perch, on: dock))"

      XCTAssertEqual(OverlayLog.perchFacing(in: line), facing == .left ? "left" : "right")
    }
    XCTAssertNil(OverlayLog.perchFacing(in: "Overlay: hidden"))
  }

  func testTheTimeIsReadFromTheLinesTimestamp() throws {
    let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
    let line =
      "2026-11-10 00:31:07.123 Df DrowsyDock[123:456] [com.drowsydock.DrowsyDock:dock] Overlay: hidden"

    let time = try XCTUnwrap(OverlayLog.time(of: line, in: utc))

    XCTAssertEqual(time, 1_794_270_667.123, accuracy: 0.0005)
    XCTAssertNil(OverlayLog.time(of: "Overlay: hidden"))
  }
}
