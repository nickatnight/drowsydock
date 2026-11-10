import CoreGraphics

/// Checks QA 8.5 and 8.15 on screenshots of the real Dock: that the Dock's drawn rim, the veil's
/// edges and the cat's paws lie where the Accessibility frames put the Dock's background, within
/// 1 point.
///
/// It takes three screenshots of the same area: `bare` with neither cat nor veil (No battery),
/// `awake` with the cat and no veil (80%), and `asleep` with the veil (5%). The veil darkens what
/// is behind it by the same share whatever its brightness, so `asleep` over `bare` is 0.72 under
/// the veil and 1 elsewhere; the cat is where `awake` differs from `bare`.
public struct DockAlignment {
  /// The screen edge the Dock sits on.
  public enum Edge: String, Sendable {
    case bottom
    case left
    case right
  }

  /// How far from the expected edge to look, in points. Larger than any offset worth reporting,
  /// smaller than the Dock's thickness.
  public static let searchDistance = 6.0

  private static let catThreshold = 20.0

  private static let veilFloor = 8.0

  public let area: CaptureArea
  public let edge: Edge
  public let background: CGRect
  public let perch: CGRect

  public init(area: CaptureArea, edge: Edge, background: CGRect, perch: CGRect) {
    self.area = area
    self.edge = edge
    self.background = background
    self.perch = perch
  }

  /// Returns every check that applies to this Dock.
  public func checks(bare: LumaImage, awake: LumaImage, asleep: LumaImage) -> [EdgeCheck] {
    let veil = asleep.ratio(to: bare, floor: Self.veilFloor)
    let cat = awake.subtracting(bare)
    switch edge {
    case .bottom:
      let columns = bands(from: background.minX, to: perch.minX)
      let rows = bands(from: background.minY, to: background.maxY, axisIsY: true)
      return [
        EdgeCheck(
          name: "Dock rim, top edge (8.5)",
          expected: background.maxY,
          found: edgeY(in: bare, near: background.maxY, columns: columns, finder: .line)
        ),
        EdgeCheck(
          name: "Dock rim, right end (8.5)",
          expected: background.maxX,
          found: edgeX(in: bare, near: background.maxX, rows: rows, finder: .line)
        ),
        EdgeCheck(
          name: "veil, top edge (8.5)",
          expected: background.maxY,
          found: edgeY(in: veil, near: background.maxY, columns: columns, finder: .step)
        ),
        EdgeCheck(
          name: "veil, right end (8.5)",
          expected: background.maxX,
          found: edgeX(in: veil, near: background.maxX, rows: rows, finder: .step)
        ),
        EdgeCheck(
          name: "paws on the Dock's top edge (8.15)", expected: background.maxY,
          found: paws(in: cat)),
      ]
    case .left, .right:
      let inner = edge == .left ? background.maxX : background.minX
      let rows = bands(from: background.minY, to: perch.minY - 10, axisIsY: true)
      return [
        EdgeCheck(
          name: "Dock rim, inner edge (8.9)",
          expected: inner,
          found: edgeX(in: bare, near: inner, rows: rows, finder: .line)
        ),
        EdgeCheck(
          name: "veil, inner edge (8.9)",
          expected: inner,
          found: edgeX(in: veil, near: inner, rows: rows, finder: .step)
        ),
        EdgeCheck(
          name: "paws on the Dock's top end (8.9)", expected: background.maxY, found: paws(in: cat)),
      ]
    }
  }

  // MARK: - Finding edges

  enum Finder {
    // A thin line such as the Dock's rim.
    case line
    // An edge between two areas such as the veil's.
    case step

    // How a profile index becomes a position: a line lies at its pixel's centre, a step at the
    // edge between two pixels, which is the index itself.
    var offsetIntoPixel: Double {
      self == .line ? 0.5 : 0
    }
  }

  // Several narrow bands across an edge, whose median ignores one band that crosses a window edge
  // behind the Dock.
  private static let bandCount = 5

  private static let bandWidth = 4.0

  // How far from each end of an edge the bands stay, as a share of the Dock's thickness, so they
  // miss the rounded corners: the corner radius is 0.28 of the thickness.
  private static let bandInsetPerThickness = 0.4

  private func bands(from start: CGFloat, to end: CGFloat, axisIsY: Bool = false) -> [ClosedRange<
    Int
  >] {
    let inset = min(background.width, background.height) * Self.bandInsetPerThickness
    let first = start + inset
    let last = end - inset
    guard last > first else { return [] }
    return (0..<Self.bandCount).compactMap { index in
      let centre = first + (last - first) * (Double(index) + 0.5) / Double(Self.bandCount)
      let pixel = axisIsY ? area.pixelRow(atY: centre) : area.pixelColumn(atX: centre)
      let halfWidth = Self.bandWidth * area.scale / 2
      let lower = Int((pixel - halfWidth).rounded())
      let upper = Int((pixel + halfWidth).rounded())
      return lower < upper ? lower...upper : nil
    }
  }

  private func searchWindow(around pixel: Double, limit: Int) -> ClosedRange<Int>? {
    let reach = Self.searchDistance * area.scale
    let lower = max(Int((pixel - reach).rounded(.down)), 0)
    let upper = min(Int((pixel + reach).rounded(.up)), limit - 1)
    return lower + 4 <= upper ? lower...upper : nil
  }

  private func edgeY(
    in image: LumaImage,
    near expected: CGFloat,
    columns: [ClosedRange<Int>],
    finder: Finder
  ) -> Double? {
    guard let rows = searchWindow(around: area.pixelRow(atY: expected), limit: image.height)
    else { return nil }
    let found = columns.compactMap { band -> Double? in
      guard band.lowerBound >= 0, band.upperBound < image.width else { return nil }
      let profile = image.profileDown(columns: band, rows: rows)
      guard let index = Self.index(in: profile, using: finder) else { return nil }
      return Double(rows.lowerBound + index) + finder.offsetIntoPixel
    }
    return Self.median(found).map { area.y(atPixelRow: $0) }
  }

  private func edgeX(
    in image: LumaImage,
    near expected: CGFloat,
    rows: [ClosedRange<Int>],
    finder: Finder
  ) -> Double? {
    guard let columns = searchWindow(around: area.pixelColumn(atX: expected), limit: image.width)
    else { return nil }
    let found = rows.compactMap { band -> Double? in
      guard band.lowerBound >= 0, band.upperBound < image.height else { return nil }
      let profile = image.profileAcross(rows: band, columns: columns)
      guard let index = Self.index(in: profile, using: finder) else { return nil }
      return Double(columns.lowerBound + index) + finder.offsetIntoPixel
    }
    return Self.median(found).map { area.x(atPixelColumn: $0) }
  }

  private func paws(in cat: LumaImage) -> Double? {
    let first = max(Int(area.pixelColumn(atX: perch.minX).rounded()), 0)
    let last = min(Int(area.pixelColumn(atX: perch.maxX).rounded()), cat.width) - 1
    let top = max(Int(area.pixelRow(atY: perch.maxY).rounded()), 0)
    let bottom = min(
      Int(area.pixelRow(atY: perch.minY - Self.searchDistance).rounded()), cat.height - 1)
    guard first <= last, top <= bottom else { return nil }
    let lowest = (first...last).compactMap { column -> Int? in
      let profile = (top...bottom).map { cat[column, $0] }
      return Profile.lastIndex(in: profile, above: Self.catThreshold).map { top + $0 }
    }.max()
    return lowest.map { area.y(atPixelRow: Double($0 + 1)) }
  }

  private static func index(in profile: [Double], using finder: Finder) -> Int? {
    switch finder {
    case .line:
      return Profile.thinLine(in: profile)
    case .step:
      return Profile.strongestStep(in: profile)
    }
  }

  private static func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2)
      ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
  }
}
