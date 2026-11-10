import Foundation
import XCTest

/// Compares rendered images with the reference PNGs under `Tests/DrowsyDockTests/Snapshots/`.
///
/// `RECORD_SNAPSHOTS=1 swift test` rewrites every reference it reaches, and fails each of those
/// tests, so a recording run never passes as a check. A mismatch writes the actual image and a
/// diff image under `.build/snapshot-failures/` and names them in the failure.
enum Snapshot {
  private static let supportDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

  static let referenceDirectory = supportDirectory.deletingLastPathComponent()
    .appendingPathComponent("Snapshots")

  static let failureDirectory = supportDirectory.deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent(".build/snapshot-failures")

  static var isRecording: Bool {
    ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
  }

  /// Skips the test on a Mac whose GPU didn't draw the references. They were recorded on Apple
  /// silicon; an Intel GPU antialiases edges differently.
  static func skipUnlessReferenceArchitecture() throws {
    #if !arch(arm64)
      throw XCTSkip("Snapshot references were recorded on Apple silicon (arm64)")
    #endif
  }

  static func assert(
    _ image: Bitmap,
    named name: String,
    within tolerance: SnapshotTolerance,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let reference = referenceDirectory.appendingPathComponent("\(name).png")
    if isRecording {
      do {
        try image.writePNG(to: reference)
        XCTFail(
          "Recorded \(reference.path). Run again without RECORD_SNAPSHOTS.", file: file, line: line)
      } catch {
        XCTFail("Couldn't record \(reference.path): \(error)", file: file, line: line)
      }
      return
    }
    guard let expected = try? Bitmap(contentsOf: reference) else {
      let actualURL = writeFailure(image, named: "\(name).actual")
      XCTFail(
        "No reference at \(reference.path). Record it with RECORD_SNAPSHOTS=1 swift test. "
          + "Actual: \(actualURL?.path ?? "not written")",
        file: file,
        line: line
      )
      return
    }
    let comparison = SnapshotComparison(
      expected: expected,
      actual: image,
      channelTolerance: tolerance.channel
    )
    guard !comparison.matches(within: tolerance) else {
      removeFailures(named: name)
      return
    }
    let actualURL = writeFailure(image, named: "\(name).actual")
    let diffURL = writeFailure(comparison.diff, named: "\(name).diff")
    let what =
      comparison.sizesDiffer
      ? "Size \(image.width)×\(image.height) differs from \(expected.width)×\(expected.height)"
      : "\(comparison.differingPixels) pixels differ by more than \(tolerance.channel) "
        + "(at most \(tolerance.differingPixels) may)"
    XCTFail(
      "\(name): \(what). Actual: \(actualURL?.path ?? "not written"). "
        + "Diff: \(diffURL?.path ?? "not written").",
      file: file,
      line: line
    )
  }

  // A pass removes the images an earlier failure left, so the folder only shows current failures.
  private static func removeFailures(named name: String) {
    for suffix in ["actual", "diff"] {
      try? FileManager.default.removeItem(
        at: failureDirectory.appendingPathComponent("\(name).\(suffix).png")
      )
    }
  }

  private static func writeFailure(_ image: Bitmap, named name: String) -> URL? {
    let url = failureDirectory.appendingPathComponent("\(name).png")
    return (try? image.writePNG(to: url)) != nil ? url : nil
  }
}
