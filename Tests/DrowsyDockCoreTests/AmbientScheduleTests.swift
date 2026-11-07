import DrowsyDockCore
import XCTest

/// SplitMix64: a small generator whose sequence depends only on its seed.
private struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  // SplitMix64 relies on wrapping arithmetic, like a hash function.
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

final class AmbientScheduleTests: XCTestCase {
  private func delays(
    for state: DrowsinessState,
    count: Int = 2000,
    seed: UInt64 = 7
  ) -> [Double] {
    var generator = SeededGenerator(seed: seed)
    return (0..<count).compactMap { _ in
      guard case .oneShot(_, let delay) = AmbientSchedule.next(for: state, using: &generator)
      else { return nil }
      return Double(delay.components.seconds) + Double(delay.components.attoseconds) / 1e18
    }
  }

  private func behaviour(for state: DrowsinessState) -> AmbientBehaviour {
    var generator = SeededGenerator(seed: 1)
    return AmbientSchedule.next(for: state, using: &generator)
  }

  // MARK: - Awake

  func testAnAwakeCatBlinks() {
    guard case .oneShot(.blink, _) = behaviour(for: .awake) else {
      return XCTFail("\(behaviour(for: .awake))")
    }
  }

  func testAnAwakeCatBlinksEvery8To20Seconds() {
    let awake = delays(for: .awake)

    XCTAssertEqual(awake.count, 2000)
    XCTAssertGreaterThanOrEqual(awake.min() ?? 0, 8)
    XCTAssertLessThanOrEqual(awake.max() ?? .infinity, 20)
  }

  func testAwakeBlinkDelaysSpreadOverTheWholeRange() {
    let awake = delays(for: .awake)

    XCTAssertLessThan(awake.min() ?? .infinity, 8.5)
    XCTAssertGreaterThan(awake.max() ?? 0, 19.5)
    XCTAssertGreaterThan(Set(awake.map { Int($0) }).count, 10)
  }

  // MARK: - Drowsy

  func testADrowsyCatBlinksSlowly() {
    guard case .oneShot(.slowBlink, _) = behaviour(for: .drowsy) else {
      return XCTFail("\(behaviour(for: .drowsy))")
    }
  }

  func testADrowsyCatBlinksSlowlyEvery10To20Seconds() {
    let drowsy = delays(for: .drowsy)

    XCTAssertEqual(drowsy.count, 2000)
    XCTAssertGreaterThanOrEqual(drowsy.min() ?? 0, 10)
    XCTAssertLessThanOrEqual(drowsy.max() ?? .infinity, 20)
  }

  func testDrowsyBlinkDelaysSpreadOverTheWholeRange() {
    let drowsy = delays(for: .drowsy)

    XCTAssertLessThan(drowsy.min() ?? .infinity, 10.5)
    XCTAssertGreaterThan(drowsy.max() ?? 0, 19.5)
  }

  // MARK: - Yawning

  func testAYawningCatYawnsAndNods() {
    guard case .oneShot(.yawnAndNod, _) = behaviour(for: .yawning) else {
      return XCTFail("\(behaviour(for: .yawning))")
    }
  }

  func testAYawningCatYawnsAboutEvery45Seconds() {
    let yawning = delays(for: .yawning)
    let mean = yawning.reduce(0, +) / Double(yawning.count)

    XCTAssertEqual(mean, 45, accuracy: 1)
    XCTAssertGreaterThanOrEqual(yawning.min() ?? 0, 40)
    XCTAssertLessThanOrEqual(yawning.max() ?? .infinity, 50)
  }

  // MARK: - Looping states

  func testANoddingOffCatLoopsFloatingZs() {
    XCTAssertEqual(behaviour(for: .noddingOff), .loop(.floatingZs))
  }

  func testAnAsleepCatLoopsASnore() {
    XCTAssertEqual(behaviour(for: .asleep), .loop(.snore))
  }

  // MARK: - Determinism

  func testTheSameSeedGivesTheSameDelays() {
    XCTAssertEqual(
      delays(for: .awake, count: 50, seed: 42), delays(for: .awake, count: 50, seed: 42))
  }

  func testDifferentSeedsGiveDifferentDelays() {
    XCTAssertNotEqual(
      delays(for: .awake, count: 50, seed: 1), delays(for: .awake, count: 50, seed: 2))
  }
}
