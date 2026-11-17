import Foundation
import Metal
import XCTest

enum Snapshot {
  private static let supportDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

  static let referenceDirectory = supportDirectory.deletingLastPathComponent()
    .appendingPathComponent("Snapshots")

  static let failureDirectory = supportDirectory.deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent(".build/snapshot-failures")

  static let backdrop: (red: UInt8, green: UInt8, blue: UInt8) = (214, 220, 230)

  // The Mac the references were drawn on, written beside them when recording. Another GPU or a
  // SpriteKit change in a macOS update can move antialiased edges and fail every snapshot; the
  // failure message names both environments so that reads as a change of machine, not of code.
  static let environmentFile = referenceDirectory.appendingPathComponent("RECORDED_ON")

  static var environment: String {
    let os = ProcessInfo.processInfo.operatingSystemVersionString
    let gpu = MTLCreateSystemDefaultDevice()?.name ?? "no Metal device"
    return "macOS \(os), \(gpu)"
  }

  static var recordedOn: String {
    (try? String(contentsOf: environmentFile, encoding: .utf8))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
  }

  static var isRecording: Bool {
    ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
  }

  static func skipsSnapshots(in environment: [String: String]) -> Bool {
    environment["DROWSYDOCK_SKIP_SNAPSHOTS"] == "1"
  }

  static func skipUnlessComparable(
    in environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws {
    #if !arch(arm64)
      throw XCTSkip("Snapshot references were recorded on Apple silicon (arm64)")
    #endif
    if skipsSnapshots(in: environment) {
      throw XCTSkip(
        "DROWSYDOCK_SKIP_SNAPSHOTS=1: snapshot references were recorded on \(recordedOn)")
    }
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
        try "\(environment)\n".write(to: environmentFile, atomically: true, encoding: .utf8)
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
        + "Diff: \(diffURL?.path ?? "not written"). References recorded on \(recordedOn); "
        + "this run on \(environment). Look at the diff before re-recording.",
      file: file,
      line: line
    )
  }

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
