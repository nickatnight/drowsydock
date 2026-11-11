import Foundation

/// One line of the QA log, the file that `scripts/qa-live.sh` reads instead of the unified log
/// (ADR 0020).
///
/// A line reads `2026-11-10T01:31:07.123+01:00 DrowsyDock[812] notice battery: Changed: …`: the
/// time to the millisecond with its offset from UTC, the process and its id, the level, the
/// category, and the message. A line break in the message is written as `\n` or `\r`, so each
/// message is one line.
public struct QALogLine {
  private let formatter = ISO8601DateFormatter()

  /// Creates a formatter that writes each time in `timeZone`.
  public init(timeZone: TimeZone) {
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = timeZone
  }

  /// Returns the line for `message`, without a line break at its end.
  public func text(
    at date: Date,
    processIdentifier: Int32,
    level: String,
    category: String,
    message: String
  ) -> String {
    let oneLine = message.replacingOccurrences(of: "\r", with: "\\r")
      .replacingOccurrences(of: "\n", with: "\\n")
    return "\(formatter.string(from: date)) DrowsyDock[\(processIdentifier)] \(level) \(category): "
      + oneLine
  }
}
