import DockOverlayKit
import XCTest

@MainActor
final class MirroredLoggerTests: XCTestCase {
  private struct Line: Equatable {
    let level: MirroredLogger.Level
    let category: String
    let message: String
  }

  private var unified: [Line] = []
  private var mirrored: [Line] = []

  private func recordLines(inTheUnifiedLog recordsUnifiedLog: Bool = true) {
    let realUnifiedLog = MirroredLogger.unifiedLog
    if recordsUnifiedLog {
      MirroredLogger.unifiedLog = { [unowned self] _, level, message in
        unified.append(Line(level: level, category: "", message: message))
      }
    }
    MirroredLogger.mirror = { [unowned self] level, category, message in
      mirrored.append(Line(level: level, category: category, message: message))
    }
    addTeardownBlock {
      MirroredLogger.unifiedLog = realUnifiedLog
      MirroredLogger.mirror = nil
    }
  }

  func testEachLevelReachesTheUnifiedLogAndTheMirrorWithTheSameText() {
    recordLines()
    let logger = MirroredLogger(subsystem: "com.drowsydock.tests", category: "dock")

    logger.debug("Overlay: hidden")
    logger.notice("The Dock relaunched")
    logger.error("Dock geometry unavailable: noDock")

    XCTAssertEqual(
      unified.map(\.message),
      ["Overlay: hidden", "The Dock relaunched", "Dock geometry unavailable: noDock"]
    )
    XCTAssertEqual(unified.map(\.level), [.debug, .notice, .error])
    XCTAssertEqual(
      mirrored,
      [
        Line(level: .debug, category: "dock", message: "Overlay: hidden"),
        Line(level: .notice, category: "dock", message: "The Dock relaunched"),
        Line(level: .error, category: "dock", message: "Dock geometry unavailable: noDock"),
      ]
    )
  }

  func testWithoutAMirrorALineStillReachesTheUnifiedLog() {
    recordLines()
    MirroredLogger.mirror = nil

    MirroredLogger(subsystem: "com.drowsydock.tests", category: "dock").notice("Started")

    XCTAssertEqual(unified.map(\.message), ["Started"])
    XCTAssertEqual(mirrored, [])
  }

  func testTheRealUnifiedLogTakesEveryLevelAndTheMirrorStillGetsTheLine() {
    recordLines(inTheUnifiedLog: false)
    let logger = MirroredLogger(subsystem: "com.drowsydock.tests", category: "battery")

    logger.debug("Power source notification")
    logger.notice("Changed: 80%")
    logger.error("No power source notifications")

    XCTAssertEqual(
      mirrored.map(\.message),
      ["Power source notification", "Changed: 80%", "No power source notifications"]
    )
  }
}
