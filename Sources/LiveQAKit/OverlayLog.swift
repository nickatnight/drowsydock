import CoreGraphics
import Foundation

/// Reads what the app placed from its QA log (ADR 0020), so the live checks use the sprite size
/// the app draws instead of a copy of it.
public enum OverlayLog {
  /// Returns the perch frame in a `DockTracker` line such as `Overlay: shown(DockPerch(frame:
  /// (1066.8, 84.0, 64.0, 80.0), facing: …), on: …)`, or `nil` when the line holds none.
  public static func perchFrame(in line: String) -> CGRect? {
    guard let start = line.range(of: "DockPerch(frame: (") else { return nil }
    let rest = line[start.upperBound...]
    guard let end = rest.firstIndex(of: ")") else { return nil }
    let numbers = rest[..<end].split(separator: ",").compactMap {
      Double($0.filter { $0 != " " })
    }
    guard numbers.count == 4 else { return nil }
    return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
  }

  /// Returns when the app logged `line`, in seconds since 1970, from the time that starts each
  /// line of the QA log (`2026-11-10T01:31:07.123+01:00`), or `nil` when the line has none. It is
  /// the app's own clock, read as it wrote the line, so the time the script took to see the line
  /// doesn't count.
  public static func time(of line: String) -> Double? {
    guard let stamp = line.split(separator: " ", maxSplits: 1).first else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: String(stamp))?.timeIntervalSince1970
  }

  /// Returns the way the logged perch faces, "left" or "right", or `nil` when the line holds none.
  public static func perchFacing(in line: String) -> String? {
    guard let start = line.range(of: "DockPerch(frame: ") else { return nil }
    let rest = line[start.upperBound...]
    guard let facing = rest.range(of: "Facing.") else { return nil }
    let word = rest[facing.upperBound...].prefix { $0.isLetter }
    return word == "left" || word == "right" ? String(word) : nil
  }
}
