import Foundation

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
    // Most comparisons are of identical images; memcmp settles those at once, where the loop below
    // takes seconds on a large strip in a debug build.
    let isIdentical = expected.pixels.withUnsafeBytes { expected in
      actual.pixels.withUnsafeBytes { actual in
        memcmp(expected.baseAddress, actual.baseAddress, expected.count) == 0
      }
    }
    guard !isIdentical else {
      differingPixels = 0
      diff = expected
      return
    }
    var diff = expected
    var count = 0
    actual.pixels.withUnsafeBufferPointer { actual in
      diff.pixels.withUnsafeMutableBufferPointer { diff in
        for start in stride(from: 0, to: diff.count, by: 4) {
          var differs = false
          for channel in start..<start + 4 {
            let a = diff[channel]
            let b = actual[channel]
            if (a > b ? a - b : b - a) > channelTolerance {
              differs = true
            }
          }
          if differs {
            count += 1
            (diff[start], diff[start + 1], diff[start + 2], diff[start + 3]) = (255, 0, 0, 255)
          } else {
            for channel in start..<start + 3 {
              diff[channel] = 128 + diff[channel] / 2
            }
            diff[start + 3] = 255
          }
        }
      }
    }
    differingPixels = count
    self.diff = diff
  }

  func matches(within tolerance: SnapshotTolerance) -> Bool {
    !sizesDiffer && differingPixels <= tolerance.differingPixels
  }
}
