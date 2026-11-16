import CoreGraphics
import DockOverlayKit
import DrowsyDockCore
import Foundation
import LiveQAKit
import XCTest

final class QALogFixtureTests: XCTestCase {
  private static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appending(path: "Fixtures/qa.log")

  private func fixtureLines() throws -> [String] {
    try String(contentsOf: Self.fixture, encoding: .utf8).split(separator: "\n").map(String.init)
  }

  func testEachFixtureLineIsTheLineTheAppWritesForItsTimeProcessLevelCategoryAndMessage() throws {
    let format = QALogLine(timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 3600)))
    let lines = try fixtureLines()
    XCTAssertEqual(lines.count, 9)

    for line in lines {
      let time = try XCTUnwrap(OverlayLog.time(of: line), line)
      let match = try XCTUnwrap(
        line.wholeMatch(of: #/\S+ DrowsyDock\[(\d+)\] (\w+) ([\w-]+): (.*)/#),
        line
      )
      let (_, processIdentifier, level, category, message) = match.output

      let written = format.text(
        at: Date(timeIntervalSince1970: time),
        processIdentifier: try XCTUnwrap(Int32(processIdentifier)),
        level: String(level),
        category: String(category),
        message: String(message)
      )

      XCTAssertEqual(written, line)
    }
  }

  @MainActor
  func testTheFixturesOverlayLinesAreDockTrackersMessagesForTheirDock() throws {
    let format = QALogLine(timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 3600)))
    let dock = DockGeometry(
      listFrame: AXRect(CGRect(x: 373, y: 893, width: 766, height: 79)),
      iconFrames: [AXRect(CGRect(x: 1071, y: 898, width: 63, height: 79))],
      layout: DisplayLayout(primary: CGRect(x: 0, y: 0, width: 1512, height: 982))
    )
    let perch = dock.perch(for: CGSize(width: 64, height: 80))
    let lines = try fixtureLines()

    for (number, presentation) in [
      (5, OverlayPresentation.shown(perch, on: dock)),
      (7, .fadedOut(perch, on: dock)),
      (9, .hidden),
    ] {
      let line = lines[number - 1]
      let written = format.text(
        at: Date(timeIntervalSince1970: try XCTUnwrap(OverlayLog.time(of: line))),
        processIdentifier: 4242,
        level: "debug",
        category: "dock",
        message: DockTracker.overlayMessage(presentation)
      )

      XCTAssertEqual(written, line, "fixture line \(number)")
    }
  }

  func testTheHelperReadsTheFixturesOverlayLineAsTheAppPlacedIt() throws {
    let shown = try fixtureLines()[4]

    XCTAssertEqual(OverlayLog.perchFrame(in: shown), CGRect(x: 1070, y: 84, width: 64, height: 80))
    XCTAssertEqual(OverlayLog.perchFacing(in: shown), "left")
    XCTAssertEqual(try XCTUnwrap(OverlayLog.time(of: shown)), 1_794_270_667.123, accuracy: 0.0005)
  }
}
