import XCTest

@testable import DockOverlayKit

final class RepeatedFailureFilterTests: XCTestCase {
  private enum Failure: Equatable {
    case revoked
    case frozen
  }

  func testTheFirstFailureIsReported() {
    var filter = RepeatedFailureFilter<Failure>()

    XCTAssertTrue(filter.shouldReport(.revoked))
  }

  func testTheSameFailureAgainIsSuppressed() {
    var filter = RepeatedFailureFilter<Failure>()
    _ = filter.shouldReport(.revoked)

    XCTAssertFalse(filter.shouldReport(.revoked))
    XCTAssertFalse(filter.shouldReport(.revoked))
  }

  func testADifferentFailureIsReported() {
    var filter = RepeatedFailureFilter<Failure>()
    _ = filter.shouldReport(.revoked)

    XCTAssertTrue(filter.shouldReport(.frozen))
  }

  func testTheSameFailureAfterASuccessIsReportedAgain() {
    var filter = RepeatedFailureFilter<Failure>()
    _ = filter.shouldReport(.revoked)

    filter.succeeded()

    XCTAssertTrue(filter.shouldReport(.revoked))
  }
}
