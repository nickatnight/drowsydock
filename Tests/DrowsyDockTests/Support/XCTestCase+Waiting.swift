import Foundation
import XCTest

extension XCTestCase {
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
