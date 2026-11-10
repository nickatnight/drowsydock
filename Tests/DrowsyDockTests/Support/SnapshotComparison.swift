/// How far an image may stray from its reference and still match it.
struct SnapshotTolerance {
  /// The largest difference allowed in any one channel of a pixel, out of 255.
  let channel: UInt8

  /// How many pixels may differ by more than `channel` before the images stop matching.
  let differingPixels: Int
}

/// Compares an image with its reference, pixel by pixel.
struct SnapshotComparison {
  /// The number of pixels with a channel that differs by more than the tolerance.
  let differingPixels: Int

  /// The reference, faded, with every differing pixel painted solid red.
  let diff: Bitmap

  /// Whether the sizes differ, in which case every pixel counts as differing.
  let sizesDiffer: Bool

  init(expected: Bitmap, actual: Bitmap, channelTolerance: UInt8) {
    guard expected.width == actual.width, expected.height == actual.height else {
      sizesDiffer = true
      differingPixels = max(expected.width * expected.height, actual.width * actual.height)
      diff = actual
      return
    }
    sizesDiffer = false
    var diff = expected
    var count = 0
    for start in stride(from: 0, to: expected.pixels.count, by: 4) {
      let differs = (0..<4).contains { channel in
        let a = expected.pixels[start + channel]
        let b = actual.pixels[start + channel]
        return (a > b ? a - b : b - a) > channelTolerance
      }
      if differs {
        count += 1
        diff.pixels.replaceSubrange(start..<start + 4, with: [255, 0, 0, 255])
      } else {
        for channel in 0..<3 {
          diff.pixels[start + channel] = 128 + diff.pixels[start + channel] / 2
        }
        diff.pixels[start + 3] = 255
      }
    }
    differingPixels = count
    self.diff = diff
  }

  func matches(within tolerance: SnapshotTolerance) -> Bool {
    !sizesDiffer && differingPixels <= tolerance.differingPixels
  }
}
