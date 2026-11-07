/// The battery percentages below which a discharging battery makes the mascot sleepier.
public struct Thresholds: Sendable, Equatable {
  /// Below this percentage the mascot is at least `drowsy`.
  public let drowsyBelow: Int

  /// Below this percentage the mascot is at least `yawning`.
  public let yawningBelow: Int

  /// Below this percentage the mascot is at least `noddingOff`.
  public let noddingOffBelow: Int

  /// Below this percentage the mascot is `asleep`.
  public let asleepBelow: Int

  /// The spec's defaults: 50, 30, 20 and 10.
  public static let `default` = Thresholds(
    validatedDrowsyBelow: 50,
    yawningBelow: 30,
    noddingOffBelow: 20,
    asleepBelow: 10
  )

  /// Creates thresholds, or returns `nil` unless the values are strictly descending and each lies
  /// in 1...99.
  public init?(drowsyBelow: Int, yawningBelow: Int, noddingOffBelow: Int, asleepBelow: Int) {
    guard
      (1...99).contains(asleepBelow),
      (1...99).contains(drowsyBelow),
      drowsyBelow > yawningBelow,
      yawningBelow > noddingOffBelow,
      noddingOffBelow > asleepBelow
    else { return nil }
    self.init(
      validatedDrowsyBelow: drowsyBelow,
      yawningBelow: yawningBelow,
      noddingOffBelow: noddingOffBelow,
      asleepBelow: asleepBelow
    )
  }

  private init(
    validatedDrowsyBelow drowsyBelow: Int,
    yawningBelow: Int,
    noddingOffBelow: Int,
    asleepBelow: Int
  ) {
    self.drowsyBelow = drowsyBelow
    self.yawningBelow = yawningBelow
    self.noddingOffBelow = noddingOffBelow
    self.asleepBelow = asleepBelow
  }
}
