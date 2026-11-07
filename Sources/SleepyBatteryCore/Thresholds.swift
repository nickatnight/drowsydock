/// The battery percentages at which the mascot enters each sleepier state while discharging.
///
/// Each value is the lowest percentage that still counts as the state above it. With the
/// defaults, 50% is `awake` and 49% is `drowsy`.
public struct Thresholds: Sendable, Equatable {
  /// The lowest percentage that is still `awake`.
  public let drowsy: Int

  /// The lowest percentage that is still `drowsy`.
  public let yawning: Int

  /// The lowest percentage that is still `yawning`.
  public let noddingOff: Int

  /// The lowest percentage that is still `noddingOff`. Anything below is `asleep`.
  public let asleep: Int

  /// The spec's defaults: 50, 30, 20 and 10.
  public static let `default` = Thresholds(
    validatedDrowsy: 50,
    yawning: 30,
    noddingOff: 20,
    asleep: 10
  )

  /// Creates thresholds, or returns `nil` unless the values are strictly descending and each lies
  /// in 1...99.
  public init?(drowsy: Int, yawning: Int, noddingOff: Int, asleep: Int) {
    guard
      (1...99).contains(asleep),
      (1...99).contains(drowsy),
      drowsy > yawning,
      yawning > noddingOff,
      noddingOff > asleep
    else { return nil }
    self.init(validatedDrowsy: drowsy, yawning: yawning, noddingOff: noddingOff, asleep: asleep)
  }

  private init(validatedDrowsy drowsy: Int, yawning: Int, noddingOff: Int, asleep: Int) {
    self.drowsy = drowsy
    self.yawning = yawning
    self.noddingOff = noddingOff
    self.asleep = asleep
  }
}
