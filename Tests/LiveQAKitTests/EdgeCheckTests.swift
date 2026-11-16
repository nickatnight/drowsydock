import LiveQAKit
import XCTest

final class EdgeCheckTests: XCTestCase {
  func testAnEdgeWithinAPointPasses() {
    let check = EdgeCheck(name: "veil, top edge", expected: 84, found: 83.25)

    XCTAssertTrue(check.passes)
    XCTAssertEqual(check.offset, -0.75)
    XCTAssertEqual(
      check.report,
      "PASS veil, top edge: found 83.3, expected 84.0 (off by 0.8 pt, at most 1.0)"
    )
  }

  func testAnEdgeMoreThanAPointOffFails() {
    let check = EdgeCheck(name: "veil, top edge", expected: 84, found: 89)

    XCTAssertFalse(check.passes)
    XCTAssertTrue(check.report.hasPrefix("FAIL veil, top edge: found 89.0"))
  }

  func testNoEdgeFoundFails() {
    let check = EdgeCheck(name: "paws", expected: 84, found: nil)

    XCTAssertFalse(check.passes)
    XCTAssertEqual(check.report, "FAIL paws: no edge found near 84.0")
  }
}
