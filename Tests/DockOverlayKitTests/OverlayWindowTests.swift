import AppKit
import DockOverlayKitTestSupport
import XCTest

@testable import DockOverlayKit

@MainActor
final class OverlayWindowTests: XCTestCase {
  // AppKit runs a window's fade on after the test that started it, and a window freed mid-fade
  // crashes a later test that runs the run loop. The app never frees its overlay windows.
  private static var keptAlive: [OverlayWindow] = []

  private let offscreenFrame = CGRect(x: 50_000, y: 50_000, width: 64, height: 80)

  private func overlay() -> OverlayWindow {
    let overlay = OverlayWindow(contentView: NSView())
    Self.keptAlive.append(overlay)
    addTeardownBlock { overlay.hide() }
    return overlay
  }

  func testItIgnoresTheMouse() {
    XCTAssertTrue(overlay().window.ignoresMouseEvents)
  }

  func testItCanNotBecomeKeyAndStaysOutOfTheWindowCycle() {
    let window = overlay().window

    XCTAssertFalse(window.canBecomeKey)
    XCTAssertFalse(window.canBecomeMain)
    XCTAssertTrue(window.collectionBehavior.contains(.ignoresCycle))
  }

  func testItJoinsEverySpaceAndStaysPutWhenSpacesChange() {
    let behavior = overlay().window.collectionBehavior

    XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
    XCTAssertTrue(behavior.contains(.stationary))
    XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
  }

  func testItSitsOneLevelAboveTheDock() {
    XCTAssertEqual(
      overlay().window.level.rawValue,
      Int(CGWindowLevelForKey(.dockWindow)) + 1
    )
  }

  func testHideOthersCanNotHideIt() {
    XCTAssertFalse(overlay().window.canHide)
  }

  func testItIsBorderlessClearAndShadowless() {
    let window = overlay().window

    XCTAssertEqual(window.styleMask, .borderless)
    XCTAssertFalse(window.isOpaque)
    XCTAssertEqual(window.backgroundColor, .clear)
    XCTAssertFalse(window.hasShadow)
  }

  // MARK: - Fades

  private let fadeDuration: TimeInterval = 0.2

  func testShowingFadesTheWindowInOverTheFade() {
    let overlay = overlay()
    let recorder = FadeRecorder(overlay)

    overlay.show(at: offscreenFrame)

    XCTAssertEqual(recorder.fades.map(\.alpha), [1])
    XCTAssertEqual(recorder.fades.map(\.duration), [fadeDuration])
    XCTAssertEqual(overlay.window.alphaValue, 1)
  }

  func testFadingOutFadesTheWindowToTransparentAndKeepsItOnScreen() {
    let overlay = overlay()
    let recorder = FadeRecorder(overlay)
    overlay.show(at: offscreenFrame)

    overlay.fadeOut(at: offscreenFrame)

    XCTAssertEqual(recorder.fades.map(\.alpha), [1, 0])
    XCTAssertEqual(recorder.fades.last?.duration, fadeDuration)
    XCTAssertTrue(overlay.window.isVisible)
  }

  func testHidingWithAFadeFadesFirstThenTakesTheWindowOffScreen() {
    let overlay = overlay()
    let recorder = FadeRecorder(overlay)
    overlay.show(at: offscreenFrame)

    overlay.hide(fading: true)

    XCTAssertEqual(recorder.fades.map(\.alpha), [1, 0])
    XCTAssertEqual(recorder.fades.last?.duration, fadeDuration)
    XCTAssertFalse(overlay.window.isVisible)
  }

  func testHidingWithoutAFadeStartsNone() {
    let overlay = overlay()
    let recorder = FadeRecorder(overlay)
    overlay.show(at: offscreenFrame)

    overlay.hide()

    XCTAssertEqual(recorder.fades.map(\.alpha), [1])
    XCTAssertFalse(overlay.window.isVisible)
  }

  func testShowingDuringAFadingHideKeepsTheWindowOnScreen() {
    let overlay = overlay()
    let recorder = FadeRecorder(overlay)
    overlay.show(at: offscreenFrame)
    recorder.completesAtOnce = false

    overlay.hide(fading: true)
    overlay.show(at: offscreenFrame)
    for completion in recorder.pending {
      completion()
    }

    XCTAssertEqual(overlay.visibility, .shown)
    XCTAssertTrue(overlay.window.isVisible)
  }

  // MARK: - The real fade, through AppKit

  private let realFadeDeadline: TimeInterval = 2

  private func skipWhileTheDisplaySleeps() throws {
    try XCTSkipIf(
      CGDisplayIsAsleep(CGMainDisplayID()) != 0,
      "AppKit animates windows only while a display is awake"
    )
  }

  private func secondsUntil(_ condition: () -> Bool) -> TimeInterval? {
    let start = Date()
    while !condition() {
      guard Date().timeIntervalSince(start) < realFadeDeadline else { return nil }
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return Date().timeIntervalSince(start)
  }

  func testTheRealFadeInAnimatesToFullOpacity() throws {
    try skipWhileTheDisplaySleeps()
    let overlay = overlay()

    overlay.show(at: offscreenFrame)

    XCTAssertLessThan(overlay.window.alphaValue, 0.99, "popped instead of fading")
    let seconds = try XCTUnwrap(secondsUntil { overlay.window.alphaValue >= 0.99 })
    XCTAssertGreaterThanOrEqual(seconds, fadeDuration / 2, "faded in too quickly to be seen")
  }

  func testTheRealFadeOutReachesTransparent() throws {
    try skipWhileTheDisplaySleeps()
    let overlay = overlay()
    overlay.show(at: offscreenFrame)
    XCTAssertNotNil(secondsUntil { overlay.window.alphaValue >= 0.99 })

    overlay.fadeOut(at: offscreenFrame)

    XCTAssertGreaterThan(overlay.window.alphaValue, 0.01, "popped instead of fading")
    XCTAssertNotNil(secondsUntil { overlay.window.alphaValue <= 0.01 }, "never faded out")
    XCTAssertTrue(overlay.window.isVisible)
  }

  func testTheRealFadingHideTakesTheWindowOffScreen() throws {
    try skipWhileTheDisplaySleeps()
    let overlay = overlay()
    overlay.show(at: offscreenFrame)
    XCTAssertNotNil(secondsUntil { overlay.window.alphaValue >= 0.99 })

    overlay.hide(fading: true)

    XCTAssertTrue(overlay.window.isVisible, "hidden at once instead of fading")
    XCTAssertNotNil(secondsUntil { !overlay.window.isVisible }, "never taken off screen")
  }

  // MARK: - Showing and hiding

  func testShowingPutsTheWindowOnScreenAtTheFrame() {
    let overlay = overlay()

    overlay.show(at: offscreenFrame)

    XCTAssertTrue(overlay.window.isVisible)
    XCTAssertEqual(overlay.frame, offscreenFrame)
    XCTAssertEqual(overlay.visibility, .shown)
  }

  func testFadingOutKeepsTheWindowOnScreenAtTheFrame() {
    let overlay = overlay()
    overlay.show(at: offscreenFrame)

    overlay.fadeOut(at: offscreenFrame.offsetBy(dx: 10, dy: 0))

    XCTAssertTrue(overlay.window.isVisible)
    XCTAssertEqual(overlay.frame, offscreenFrame.offsetBy(dx: 10, dy: 0))
    XCTAssertEqual(overlay.visibility, .fadedOut)
  }

  func testHidingTakesTheWindowOffScreen() {
    let overlay = overlay()
    overlay.show(at: offscreenFrame)

    overlay.hide()

    XCTAssertFalse(overlay.window.isVisible)
    XCTAssertEqual(overlay.visibility, .hidden)
  }

  // NSWindow.setFrame aborts the app on such a frame (ADR 0013).
  func testAnUnusableFrameHidesTheWindowInsteadOfPlacingIt() {
    let overlay = overlay()
    overlay.show(at: offscreenFrame)

    overlay.show(at: CGRect(x: CGFloat.infinity, y: 0, width: 64, height: 80))

    XCTAssertFalse(overlay.window.isVisible)
    XCTAssertEqual(overlay.visibility, .hidden)
    XCTAssertEqual(overlay.frame, offscreenFrame)
  }

  func testAUsableFrameReArmsTheUnusableFrameLog() {
    let overlay = overlay()
    let unusable = CGRect(x: CGFloat.infinity, y: 0, width: 64, height: 80)

    overlay.show(at: unusable)
    XCTAssertTrue(overlay.hasReportedUnusableFrame)
    overlay.show(at: offscreenFrame)
    XCTAssertFalse(overlay.hasReportedUnusableFrame)
    overlay.fadeOut(at: unusable)

    XCTAssertTrue(overlay.hasReportedUnusableFrame)
  }
}
