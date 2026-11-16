import DrowsyDockCore
import XCTest

final class QALogLineTests: XCTestCase {
  private let loggedAt = Date(timeIntervalSince1970: 1_794_270_667.123)

  func testALineIsTheLocalTimeToTheMillisecondThenTheProcessLevelCategoryAndMessage() throws {
    let berlin = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))

    let line = QALogLine(timeZone: berlin).text(
      at: loggedAt,
      processIdentifier: 812,
      level: "notice",
      category: "battery",
      message: "Changed: 80% · Discharging · Awake (simulated 80%)"
    )

    XCTAssertEqual(
      line,
      "2026-11-10T01:31:07.123+01:00 DrowsyDock[812] notice battery: "
        + "Changed: 80% · Discharging · Awake (simulated 80%)"
    )
  }

  func testInUTCTheTimeEndsInZ() throws {
    let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))

    let line = QALogLine(timeZone: utc).text(
      at: loggedAt,
      processIdentifier: 7,
      level: "debug",
      category: "dock",
      message: "Overlay: hidden"
    )

    XCTAssertEqual(line, "2026-11-10T00:31:07.123Z DrowsyDock[7] debug dock: Overlay: hidden")
  }

  func testALineBreakInTheMessageIsWrittenAsAnEscapeSoTheMessageStaysOneLine() throws {
    let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))

    let line = QALogLine(timeZone: utc).text(
      at: loggedAt,
      processIdentifier: 7,
      level: "error",
      category: "dock",
      message: "Dock geometry unavailable:\nfirst\r\nsecond"
    )

    XCTAssertEqual(
      line,
      "2026-11-10T00:31:07.123Z DrowsyDock[7] error dock: Dock geometry unavailable:\\nfirst\\r\\nsecond"
    )
  }
}
