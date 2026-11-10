import CoreGraphics
import Foundation
import ImageIO

/// A screenshot's brightness: the mean of each pixel's red, green and blue, from 0 to 255, with
/// rows from top to bottom as the screen shows them.
public struct LumaImage: Equatable, Sendable {
  public enum LumaImageError: Error {
    case unreadable(URL)
  }

  public let width: Int
  public let height: Int
  public let values: [Double]

  public init(width: Int, height: Int, values: [Double]) {
    precondition(values.count == width * height, "one value per pixel")
    self.width = width
    self.height = height
    self.values = values
  }

  /// Reads a PNG, such as one `screencapture` wrote.
  public init(contentsOf url: URL) throws {
    guard
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    else { throw LumaImageError.unreadable(url) }
    let (width, height) = (image.width, image.height)
    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: width * 4,
          space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { throw LumaImageError.unreadable(url) }
    var values = [Double](repeating: 0, count: width * height)
    for index in values.indices {
      let start = index * 4
      values[index] = (Double(rgba[start]) + Double(rgba[start + 1]) + Double(rgba[start + 2])) / 3
    }
    self.init(width: width, height: height, values: values)
  }

  /// The brightness of the pixel in column `x` and row `y` from the top.
  public subscript(x: Int, y: Int) -> Double {
    values[y * width + x]
  }

  /// Returns, for each row in `rows`, the mean brightness over `columns`: a profile down the image
  /// that averages out noise across a band.
  public func profileDown(columns: ClosedRange<Int>, rows: ClosedRange<Int>) -> [Double] {
    rows.map { y in
      columns.reduce(0) { $0 + self[$1, y] } / Double(columns.count)
    }
  }

  /// Returns, for each column in `columns`, the mean brightness over `rows`: a profile across the
  /// image.
  public func profileAcross(rows: ClosedRange<Int>, columns: ClosedRange<Int>) -> [Double] {
    columns.map { x in
      rows.reduce(0) { $0 + self[x, $1] } / Double(rows.count)
    }
  }

  /// Returns each pixel's brightness as a share of the same pixel's in `other`, which must have
  /// the same size: 0.72 where a veil at 0.28 darkens it, 1 where nothing changed. Where `other` is
  /// darker than `floor` the share can't be told, and counts as 1.
  public func ratio(to other: LumaImage, floor: Double) -> LumaImage {
    precondition(width == other.width && height == other.height, "same size")
    return LumaImage(
      width: width,
      height: height,
      values: zip(values, other.values).map { $1 < floor ? 1 : $0 / $1 }
    )
  }

  /// Returns how much brighter each pixel of `self` is than the same pixel of `other`, which must
  /// have the same size.
  public func subtracting(_ other: LumaImage) -> LumaImage {
    precondition(width == other.width && height == other.height, "same size")
    return LumaImage(
      width: width,
      height: height,
      values: zip(values, other.values).map { $0 - $1 }
    )
  }
}
