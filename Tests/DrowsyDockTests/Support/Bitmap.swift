import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An sRGB image with 8 bits per channel, premultiplied RGBA, rows from top to bottom.
struct Bitmap: Equatable {
  enum BitmapError: Error {
    case unreadable(URL)
    case unwritable(URL)
  }

  static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

  private static let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

  let width: Int
  let height: Int
  var pixels: [UInt8]

  init(width: Int, height: Int, pixels: [UInt8]) {
    precondition(pixels.count == width * height * 4, "4 bytes per pixel")
    self.width = width
    self.height = height
    self.pixels = pixels
  }

  /// A bitmap filled with one opaque colour, given as RGB bytes.
  init(width: Int, height: Int, filledWith color: (red: UInt8, green: UInt8, blue: UInt8)) {
    let pixel = [color.red, color.green, color.blue, 255]
    self.init(
      width: width,
      height: height,
      pixels: Array([[UInt8]](repeating: pixel, count: width * height).joined())
    )
  }

  /// Draws `image` into a new bitmap of the same size.
  init(_ image: CGImage) {
    self.init(
      width: image.width,
      height: image.height,
      pixels: [UInt8](repeating: 0, count: image.width * image.height * 4)
    )
    draw(image, at: .zero)
  }

  /// Reads a PNG.
  init(contentsOf url: URL) throws {
    guard
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw BitmapError.unreadable(url) }
    self.init(image)
  }

  var cgImage: CGImage {
    let provider = CGDataProvider(data: Data(pixels) as CFData)
    // The provider and the format are always valid for a bitmap built by this type.
    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: width * 4,
      space: Self.colorSpace,
      bitmapInfo: CGBitmapInfo(rawValue: Self.bitmapInfo),
      provider: provider!,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )!
  }

  func writePNG(to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    guard
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else { throw BitmapError.unwritable(url) }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else { throw BitmapError.unwritable(url) }
  }

  /// Draws `image` over this bitmap with its bottom-left corner at `origin`, in pixels from the
  /// bitmap's bottom-left corner, as Core Graphics and AppKit place things.
  mutating func draw(_ image: CGImage, at origin: CGPoint) {
    let (width, height) = (self.width, self.height)
    pixels.withUnsafeMutableBytes { buffer in
      // The buffer holds exactly width × height RGBA pixels, which this format describes.
      let context = CGContext(
        data: buffer.baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: Self.colorSpace,
        bitmapInfo: Self.bitmapInfo
      )!
      context.interpolationQuality = .none
      context.draw(
        image,
        in: CGRect(origin: origin, size: CGSize(width: image.width, height: image.height))
      )
    }
  }

  /// Returns `images` side by side, left to right, on a background of `color`.
  static func row(
    _ images: [Bitmap],
    gap: Int,
    background color: (red: UInt8, green: UInt8, blue: UInt8)
  ) -> Bitmap {
    let width = images.map(\.width).reduce(0, +) + gap * max(images.count - 1, 0)
    let height = images.map(\.height).max() ?? 0
    var row = Bitmap(width: width, height: height, filledWith: color)
    var x = 0
    for image in images {
      row.draw(image.cgImage, at: CGPoint(x: x, y: height - image.height))
      x += image.width + gap
    }
    return row
  }
}
