import Foundation
import XCTest

extension XCTestCase {
  /// Runs the main run loop until `condition` holds, for work that arrives asynchronously, such as
  /// a task that a test clock woke. Fails after `timeout` seconds of real time, which only a broken
  /// test reaches.
  @MainActor
  func waitUntil(
    _ description: String,
    timeout: TimeInterval = 2,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: () -> Bool
  ) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
      guard Date() < deadline else {
        XCTFail("Timed out waiting until \(description)", file: file, line: line)
        return
      }
      RunLoop.main.run(until: Date().addingTimeInterval(0.001))
    }
  }
}
