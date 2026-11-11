import CoreGraphics
import DrowsyDockCore
import Foundation
import LiveQAKit
import XCTest

// scripts/qa/check-app-log.sh runs qa-live.sh's log functions over Fixtures/qa.log. These tests pin
// that the fixture is what the app writes and what the helper reads.
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

  func testTheHelperReadsTheFixturesOverlayLineAsTheAppPlacedIt() throws {
    let shown = try fixtureLines()[4]

    XCTAssertEqual(OverlayLog.perchFrame(in: shown), CGRect(x: 1070, y: 84, width: 64, height: 80))
    XCTAssertEqual(OverlayLog.perchFacing(in: shown), "left")
    XCTAssertEqual(try XCTUnwrap(OverlayLog.time(of: shown)), 1_794_270_667.123, accuracy: 0.0005)
  }
}
