import AppKit
import XCTest

@testable import DockOverlayKit

// QA 6.2 to 6.4 and 6.7: the window's properties, on the real OverlayWindow. Frames sit 50,000
// points from every display, so nothing shows on screen.
@MainActor
final class OverlayWindowTests: XCTestCase {
  // AppKit runs a window's fade on after the test that started it, and a window freed mid-fade
  // crashes a later test that runs the run loop. The app never frees its overlay windows.
  private static var keptAlive: [OverlayWindow] = []

  private let frame = CGRect(x: 50_000, y: 50_000, width: 64, height: 80)

  private func overlay() -> OverlayWindow {
    let overlay = OverlayWindow(contentView: NSView())
    Self.keptAlive.append(overlay)
    addTeardownBlock { overlay.hide() }
    return overlay
  }

  // QA 6.2 and 6.3: clicks and drops go through to whatever is under the cat.
  func testItIgnoresTheMouse() {
    XCTAssertTrue(overlay().window.ignoresMouseEvents)
  }

  // QA 6.3: it never takes focus and stays out of Cmd-Tab and window cycling.
  func testItCanNotBecomeKeyAndStaysOutOfTheWindowCycle() {
    let window = overlay().window

    XCTAssertFalse(window.canBecomeKey)
    XCTAssertFalse(window.canBecomeMain)
    XCTAssertTrue(window.collectionBehavior.contains(.ignoresCycle))
  }

  // QA 6.4 and 6.5: it shows on every Space, beside full-screen apps too, and doesn't slide with
  // the Space animation.
  func testItJoinsEverySpaceAndStaysPutWhenSpacesChange() {
    let behavior = overlay().window.collectionBehavior

    XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
    XCTAssertTrue(behavior.contains(.stationary))
    XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
  }

  // QA 6.1: the cat draws over the Dock, just above it and below everything else.
  func testItSitsOneLevelAboveTheDock() {
    XCTAssertEqual(
      overlay().window.level.rawValue,
      Int(CGWindowLevelForKey(.dockWindow)) + 1
    )
  }

  // QA 6.7: Hide Others in another app leaves it on the Dock.
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

    overlay.show(at: frame)

    XCTAssertTrue(overlay.window.isVisible)
    XCTAssertEqual(overlay.frame, frame)
    XCTAssertEqual(overlay.visibility, .shown)
  }

  func testFadingOutKeepsTheWindowOnScreenAtTheFrame() {
    let overlay = overlay()
    overlay.show(at: frame)

    overlay.fadeOut(at: frame.offsetBy(dx: 10, dy: 0))

    XCTAssertTrue(overlay.window.isVisible)
    XCTAssertEqual(overlay.frame, frame.offsetBy(dx: 10, dy: 0))
    XCTAssertEqual(overlay.visibility, .fadedOut)
  }

  func testHidingTakesTheWindowOffScreen() {
    let overlay = overlay()
    overlay.show(at: frame)

    overlay.hide()

    XCTAssertFalse(overlay.window.isVisible)
    XCTAssertEqual(overlay.visibility, .hidden)
  }

  // NSWindow.setFrame aborts the app on such a frame (ADR 0013).
  func testAnUnusableFrameHidesTheWindowInsteadOfPlacingIt() {
    let overlay = overlay()
    overlay.show(at: frame)

    overlay.show(at: CGRect(x: CGFloat.infinity, y: 0, width: 64, height: 80))

    XCTAssertFalse(overlay.window.isVisible)
    XCTAssertEqual(overlay.visibility, .hidden)
    XCTAssertEqual(overlay.frame, frame)
  }
}
