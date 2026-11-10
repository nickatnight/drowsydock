import AppKit
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

  // Job 003 H11: each run of unusable frames logs once, and a usable frame re-arms the log.
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
