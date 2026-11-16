/// Finds features in a brightness profile: a list of values along a line through an image.
public enum Profile {
  /// Returns the index of the first sample after the largest jump between neighbours, or `nil`
  /// for a flat profile or one shorter than two samples. That is where an edge between two areas
  /// lies, such as the veil's edge over the window behind the Dock.
  public static func strongestStep(in profile: [Double]) -> Int? {
    guard profile.count >= 2 else { return nil }
    let jump = { (index: Int) in abs(profile[index] - profile[index - 1]) }
    let index = (1..<profile.count).max { jump($0) < jump($1) }
    return index.flatMap { jump($0) > 0 ? $0 : nil }
  }

  /// Returns the index of the sample that stands out most from the samples two either side of it,
  /// brighter or darker, or `nil` for a flat profile or one shorter than five samples. That is
  /// where a thin line lies, such as the Dock's rim.
  public static func thinLine(in profile: [Double]) -> Int? {
    guard profile.count >= 5 else { return nil }
    let index = (2..<profile.count - 2).max {
      contrast(profile, at: $0) < contrast(profile, at: $1)
    }
    return index.flatMap { contrast(profile, at: $0) > 0 ? $0 : nil }
  }

  /// Returns the index of the last sample whose size is above `threshold`, or `nil` when none is.
  public static func lastIndex(in profile: [Double], above threshold: Double) -> Int? {
    profile.lastIndex { abs($0) > threshold }
  }

  private static func contrast(_ profile: [Double], at index: Int) -> Double {
    abs(2 * profile[index] - profile[index - 2] - profile[index + 2])
  }
}
