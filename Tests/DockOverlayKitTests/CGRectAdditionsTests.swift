import CoreGraphics
import DockOverlayKit
import XCTest

// NSWindow.setFrame aborts the app on a null or non-finite frame (security review round 3, M-1).
final class CGRectAdditionsTests: XCTestCase {
  func testAFiniteFrameWithASizeIsUsable() {
    XCTAssertTrue(CGRect(x: -100, y: 20, width: 64, height: 80).isUsableWindowFrame)
  }

  func testTheNullFrameIsNotUsable() {
    XCTAssertFalse(CGRect.null.isUsableWindowFrame)
  }

  func testTheNullIntersectionOfTwoDisjointFramesIsNotUsable() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let farBelow = CGRect(x: 0, y: -5000, width: 700, height: 79)

    XCTAssertFalse(farBelow.intersection(screen).isUsableWindowFrame)
  }

  func testAFrameWithANaNComponentIsNotUsable() {
    XCTAssertFalse(CGRect(x: 100, y: CGFloat.nan, width: 64, height: 80).isUsableWindowFrame)
    XCTAssertFalse(CGRect(x: 100, y: 0, width: CGFloat.nan, height: 80).isUsableWindowFrame)
  }

  func testAnInfiniteFrameIsNotUsable() {
    XCTAssertFalse(CGRect.infinite.isUsableWindowFrame)
    XCTAssertFalse(CGRect(x: 0, y: 0, width: 64, height: CGFloat.infinity).isUsableWindowFrame)
  }

  func testAFrameWithNoAreaIsNotUsable() {
    XCTAssertFalse(CGRect(x: 10, y: 10, width: 0, height: 80).isUsableWindowFrame)
  }
}
