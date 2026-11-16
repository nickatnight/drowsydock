import CoreGraphics

/// Checks QA 8.5, 8.15 and 6.1 on screenshots of the real Dock: that the Dock's drawn rim, the veil's
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

  /// The screen area the three screenshots cover.
  public let area: CaptureArea
  /// The screen edge the Dock sits on.
  public let edge: Edge
  /// The Dock's drawn background as the Accessibility frames put it, in AppKit points.
  public let background: CGRect
  /// Where the app placed the cat's window, in AppKit points.
  public let perch: CGRect

  /// Creates the checks for one Dock.
  public init(area: CaptureArea, edge: Edge, background: CGRect, perch: CGRect) {
    self.area = area
    self.edge = edge
    self.background = background
    self.perch = perch
  }

  /// Returns every check that applies to this Dock: for each edge it can see, the rim and the veil
  /// against the Accessibility frames and the veil against the rim itself, then the paws. Each
  /// check's name ends with the QA rows it checks, in parentheses.
  public func checks(bare: LumaImage, awake: LumaImage, asleep: LumaImage) -> [EdgeCheck] {
    let veil = asleep.ratio(to: bare, floor: Self.veilFloor)
    let cat = awake.subtracting(bare)
    var checks: [EdgeCheck] = []
    for side in sides {
      let rim = find(side, in: bare, finder: .line)
      let veilEdge = find(side, in: veil, finder: .step)
      checks += [
        EdgeCheck(name: "Dock rim, \(side.name) (\(qaRow))", expected: side.expected, found: rim),
        EdgeCheck(name: "veil, \(side.name) (\(qaRow))", expected: side.expected, found: veilEdge),
        EdgeCheck(
          name: "veil against the rim, \(side.name) (\(qaRow))",
          expected: rim ?? side.expected,
          found: rim == nil ? nil : veilEdge
        ),
      ]
    }
    let pawsName =
      edge == .bottom
      ? "paws on the Dock's top edge (8.15 6.1)" : "paws on the Dock's top end (8.9)"
    checks.append(EdgeCheck(name: pawsName, expected: background.maxY, found: paws(in: cat)))
    return checks
  }

  private var qaRow: String {
    edge == .bottom ? "8.5" : "8.9"
  }

  private struct Side {
    let name: String
    let expected: CGFloat
    let isHorizontal: Bool
    let bands: [PixelBand]
  }

  private var sides: [Side] {
    let columns = bands(from: background.minX, to: perch.minX)
    switch edge {
    case .bottom:
      let rows = bands(from: background.minY, to: background.maxY, axisIsY: true)
      return [
        Side(name: "top edge", expected: background.maxY, isHorizontal: true, bands: columns),
        Side(name: "bottom edge", expected: background.minY, isHorizontal: true, bands: columns),
        Side(name: "left end", expected: background.minX, isHorizontal: false, bands: rows),
        Side(name: "right end", expected: background.maxX, isHorizontal: false, bands: rows),
      ]
    case .left, .right:
      let rows = bands(from: background.minY, to: perch.minY - 10, axisIsY: true)
      let across = bands(from: background.minX, to: background.maxX)
      let inner = edge == .left ? background.maxX : background.minX
      return [
        Side(name: "inner edge", expected: inner, isHorizontal: false, bands: rows),
        Side(name: "bottom end", expected: background.minY, isHorizontal: true, bands: across),
      ]
    }
  }

  private func find(_ side: Side, in image: LumaImage, finder: Finder) -> Double? {
    side.isHorizontal
      ? edgeY(in: image, near: side.expected, columns: side.bands, finder: finder)
      : edgeX(in: image, near: side.expected, rows: side.bands, finder: finder)
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

  // A run of pixel columns or rows.
  typealias PixelBand = ClosedRange<Int>

  private func bands(from start: CGFloat, to end: CGFloat, axisIsY: Bool = false) -> [PixelBand] {
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

  private func searchWindow(around pixel: Double, limit: Int) -> PixelBand? {
    let reach = Self.searchDistance * area.scale
    let lower = max(Int((pixel - reach).rounded(.down)), 0)
    let upper = min(Int((pixel + reach).rounded(.up)), limit - 1)
    return lower + 4 <= upper ? lower...upper : nil
  }

  private func edgeY(
    in image: LumaImage,
    near expected: CGFloat,
    columns: [PixelBand],
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
    rows: [PixelBand],
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
