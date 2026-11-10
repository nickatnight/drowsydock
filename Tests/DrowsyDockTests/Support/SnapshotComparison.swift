import Foundation

struct SnapshotTolerance {
  // The same code on the same GPU draws identical pixels, so this only absorbs driver rounding.
  // A changed pose or timing moves hundreds of pixels.
  static let sameRenderer = SnapshotTolerance(channel: 2, differingPixels: 4)

  let channel: UInt8

  let differingPixels: Int
}

struct SnapshotComparison {
  let differingPixels: Int

  let diff: Bitmap

  let sizesDiffer: Bool

  init(expected: Bitmap, actual: Bitmap, channelTolerance: UInt8) {
    guard expected.width == actual.width, expected.height == actual.height else {
      sizesDiffer = true
      differingPixels = max(expected.width * expected.height, actual.width * actual.height)
      diff = actual
      return
    }
    sizesDiffer = false
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
