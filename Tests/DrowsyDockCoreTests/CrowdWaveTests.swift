import DrowsyDockCore
import XCTest

final class CrowdWaveTests: XCTestCase {
  func testTheWholeWaveTakesAtMostFourSecondsForAnyDock() {
    for count in [1, 2, 5, 12, 21, 40, 100, 500] {
      XCTAssertLessThanOrEqual(CrowdWave(iconCount: count).totalDuration, .seconds(4), "\(count)")
    }
  }

  func testTheFirstIconStartsAtOnce() {
    XCTAssertEqual(CrowdWave(iconCount: 12).startTime(ofIconAt: 0), .zero)
  }

  func testEachIconStartsAfterTheOneBefore() {
    for count in [2, 12, 100] {
      let wave = CrowdWave(iconCount: count)
      let starts = (0..<count).map(wave.startTime(ofIconAt:))
      XCTAssertEqual(starts, starts.sorted(), "\(count)")
      XCTAssertEqual(Set(starts).count, count, "\(count)")
    }
  }

  func testATypicalDockRipplesAtAnEvenPace() {
    let wave = CrowdWave(iconCount: 12)

    XCTAssertEqual(wave.startTime(ofIconAt: 1), .milliseconds(150))
    XCTAssertEqual(wave.startTime(ofIconAt: 11), .milliseconds(1650))
    XCTAssertEqual(wave.totalDuration, .milliseconds(2650))
  }

  func testAVeryFullDockRipplesFasterToFitInFourSeconds() {
    let wave = CrowdWave(iconCount: 41)

    XCTAssertEqual(wave.startTime(ofIconAt: 40) + CrowdWave.iconEffectDuration, .seconds(4))
  }

  func testTheLastIconFinishesWhenTheWaveEnds() {
    for count in [1, 12, 41] {
      let wave = CrowdWave(iconCount: count)
      XCTAssertEqual(
        wave.startTime(ofIconAt: count - 1) + CrowdWave.iconEffectDuration,
        wave.totalDuration,
        "\(count)"
      )
    }
  }

  func testAnEmptyDockHasNoWave() {
    XCTAssertEqual(CrowdWave(iconCount: 0).totalDuration, .zero)
  }

  func testTheDimIsBriefAndFitsInEachIconsEffect() {
    XCTAssertEqual(CrowdWave.dimDuration, .milliseconds(300))
    XCTAssertLessThanOrEqual(CrowdWave.dimDuration, CrowdWave.iconEffectDuration)
  }
}
