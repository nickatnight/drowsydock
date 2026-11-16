import XCTest

final class SnapshotComparisonTests: XCTestCase {
  private let grey = Bitmap(width: 3, height: 2, filledWith: (100, 100, 100))

  private func grey(withPixel index: Int, setTo value: UInt8) -> Bitmap {
    var image = grey
    image.pixels[index * 4 + 1] = value
    return image
  }

  func testIdenticalImagesHaveNoDifferingPixels() {
    let comparison = SnapshotComparison(expected: grey, actual: grey, channelTolerance: 0)

    XCTAssertEqual(comparison.differingPixels, 0)
    XCTAssertTrue(comparison.matches(within: SnapshotTolerance(channel: 0, differingPixels: 0)))
  }

  func testAChannelWithinTheToleranceDoesNotCount() {
    let comparison = SnapshotComparison(
      expected: grey,
      actual: grey(withPixel: 4, setTo: 102),
      channelTolerance: 2
    )

    XCTAssertEqual(comparison.differingPixels, 0)
  }

  func testAChannelPastTheToleranceCountsItsPixelOnce() {
    let comparison = SnapshotComparison(
      expected: grey,
      actual: grey(withPixel: 4, setTo: 97),
      channelTolerance: 2
    )

    XCTAssertEqual(comparison.differingPixels, 1)
    XCTAssertEqual(Array(comparison.diff.pixels[16..<20]), [255, 0, 0, 255])
    XCTAssertEqual(Array(comparison.diff.pixels[0..<4]), [178, 178, 178, 255])
  }

  func testTheDifferingPixelCountDecidesTheMatch() {
    let comparison = SnapshotComparison(
      expected: grey,
      actual: grey(withPixel: 0, setTo: 0),
      channelTolerance: 2
    )

    XCTAssertTrue(comparison.matches(within: SnapshotTolerance(channel: 2, differingPixels: 1)))
    XCTAssertFalse(comparison.matches(within: SnapshotTolerance(channel: 2, differingPixels: 0)))
  }

  func testImagesOfDifferentSizesNeverMatch() {
    let wider = Bitmap(width: 4, height: 2, filledWith: (100, 100, 100))
    let comparison = SnapshotComparison(expected: grey, actual: wider, channelTolerance: 255)

    XCTAssertTrue(comparison.sizesDiffer)
    XCTAssertFalse(
      comparison.matches(within: SnapshotTolerance(channel: 255, differingPixels: 100)))
  }

  func testABitmapSurvivesAPNGRoundTrip() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapshotComparisonTests-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: url) }
    let image = grey(withPixel: 3, setTo: 7)

    try image.writePNG(to: url)

    XCTAssertEqual(try Bitmap(contentsOf: url), image)
  }
}
