import CoreGraphics

/// Reads what the app placed from its own log, so the live checks use the sprite size the app
/// draws instead of a copy of it.
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

  /// Returns the way the logged perch faces, "left" or "right", or `nil` when the line holds none.
  public static func perchFacing(in line: String) -> String? {
    guard let start = line.range(of: "DockPerch(frame: ") else { return nil }
    let rest = line[start.upperBound...]
    guard let facing = rest.range(of: "Facing.") else { return nil }
    let word = rest[facing.upperBound...].prefix { $0.isLetter }
    return word == "left" || word == "right" ? String(word) : nil
  }
}
