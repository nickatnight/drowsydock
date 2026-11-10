/// One comparison between an edge found in a screenshot and where the Accessibility frames put
/// it, in points.
public struct EdgeCheck: Equatable, Sendable {
  /// What was compared, such as "veil top edge".
  public let name: String

  /// Where the Accessibility frames put the edge, in AppKit points.
  public let expected: Double

  /// Where the screenshot shows it, or `nil` when no edge was found.
  public let found: Double?

  /// The largest distance, in points, that still passes. QA 8.5 and 8.15 allow 1.
  public let tolerance: Double

  public init(name: String, expected: Double, found: Double?, tolerance: Double = 1) {
    self.name = name
    self.expected = expected
    self.found = found
    self.tolerance = tolerance
  }

  /// How far the found edge lies from the expected one, in points.
  public var offset: Double? {
    found.map { $0 - expected }
  }

  public var passes: Bool {
    offset.map { abs($0) <= tolerance } ?? false
  }

  /// A one-line report, such as "PASS veil top edge: found 84.0, expected 84.0 (off by 0.0 pt)".
  public var report: String {
    let verdict = passes ? "PASS" : "FAIL"
    guard let found, let offset else {
      return "\(verdict) \(name): no edge found near \(format(expected))"
    }
    return
      "\(verdict) \(name): found \(format(found)), expected \(format(expected)) "
      + "(off by \(format(abs(offset))) pt, at most \(format(tolerance)))"
  }

  private func format(_ value: Double) -> String {
    let tenths = (value * 10).rounded() / 10
    return "\(tenths)"
  }
}
