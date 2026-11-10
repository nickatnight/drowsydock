import AppKit
import ApplicationServices
import DockOverlayKit
import LiveQAKit

// The Swift helper for scripts/qa-live.sh. It reads the Dock over Accessibility (read only), moves
// the pointer, and checks screenshots. The script runs it; nothing in the app bundle includes it.
//
//   qa-helper permissions               prints "accessibility=…" and "screen-recording=…"
//   qa-helper dock                      prints the Dock's geometry as key=value lines
//   qa-helper pointer                   prints the pointer's position, in AppKit points
//   qa-helper move-pointer X Y          moves the pointer to AppKit point (X, Y)
//   qa-helper align KEY=VALUE…          compares screenshots with the Dock's frames (QA 8.5, 8.15)

@main
@MainActor
enum QAHelper {
  // Must match MascotOverlay.spriteSize and its canvas margin in the app.
  static let spriteSize = CGSize(width: 64, height: 80)
  static let canvasMargin: CGFloat = 48

  static func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("qa-helper: \(message)\n".utf8))
    exit(2)
  }

  static func describe(_ rect: CGRect) -> String {
    [rect.minX, rect.minY, rect.width, rect.height].map { "\($0)" }.joined(separator: ",")
  }

  static func rect(_ text: String) -> CGRect {
    let parts = text.split(separator: ",").compactMap { Double($0) }
    guard parts.count == 4 else { fail("expected x,y,width,height, got \(text)") }
    return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
  }

  static func primaryHeight() -> CGFloat {
    NSScreen.screens.first?.frame.height ?? 0
  }

  static func printDock() {
    let geometry: DockGeometry
    do {
      geometry = try DockReader.read()
    } catch {
      fail("Dock geometry unavailable: \(error)")
    }
    let perch = geometry.perch(for: spriteSize)
    let canvas = geometry.backgroundFrame.insetBy(dx: -canvasMargin, dy: -canvasMargin)
      .intersection(geometry.screenFrame)
    let scale = NSScreen.screens.first { $0.frame == geometry.screenFrame }?.backingScaleFactor ?? 2
    let orientation: String
    switch geometry.orientation {
    case .bottom: orientation = "bottom"
    case .left: orientation = "left"
    case .right: orientation = "right"
    }
    print("orientation=\(orientation)")
    print("hidden=\(geometry.isHidden)")
    print("icons=\(geometry.iconFrames.count)")
    print("list=\(describe(geometry.frame))")
    print("background=\(describe(geometry.backgroundFrame))")
    print("perch=\(describe(perch.frame))")
    print("facing=\(perch.facing == .left ? "left" : "right")")
    print("capture=\(describe(canvas.union(perch.frame).integral))")
    print("screen=\(describe(geometry.screenFrame))")
    print("scale=\(scale)")
    print("primary-height=\(primaryHeight())")
    if let first = geometry.iconFramesAlongDock.first, let last = geometry.iconFramesAlongDock.last
    {
      print("first-icon=\(describe(first))")
      print("last-icon=\(describe(last))")
    }
  }

  // AppKit points have their origin at the bottom-left of the primary display; Core Graphics events
  // count y down from its top.
  static func movePointer(toX x: Double, y: Double) {
    let point = CGPoint(x: x, y: primaryHeight() - y)
    guard
      let event = CGEvent(
        mouseEventSource: nil,
        mouseType: .mouseMoved,
        mouseCursorPosition: point,
        mouseButton: .left
      )
    else { fail("couldn't create a pointer event") }
    event.post(tap: .cghidEventTap)
  }

  static func align(_ arguments: [String]) {
    var values: [String: String] = [:]
    for argument in arguments {
      let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
      guard parts.count == 2 else { fail("expected KEY=VALUE, got \(argument)") }
      values[parts[0]] = parts[1]
    }
    func value(_ key: String) -> String {
      guard let value = values[key] else { fail("missing \(key)=") }
      return value
    }
    guard let edge = DockAlignment.Edge(rawValue: value("orientation")) else {
      fail("orientation must be bottom, left or right")
    }
    guard let scale = Double(value("scale")) else { fail("scale must be a number") }
    let alignment = DockAlignment(
      area: CaptureArea(frame: rect(value("capture")), scale: scale),
      edge: edge,
      background: rect(value("background")),
      perch: rect(value("perch"))
    )
    let images: [LumaImage]
    do {
      images = try ["bare", "awake", "asleep"].map {
        try LumaImage(contentsOf: URL(fileURLWithPath: value($0)))
      }
    } catch {
      fail("couldn't read a screenshot: \(error)")
    }
    let checks = alignment.checks(bare: images[0], awake: images[1], asleep: images[2])
    for check in checks {
      print(check.report)
    }
    exit(checks.allSatisfy(\.passes) ? 0 : 1)
  }

  static func main() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    switch arguments.first {
    case "permissions":
      print("accessibility=\(AXIsProcessTrusted())")
      print("screen-recording=\(CGPreflightScreenCaptureAccess())")
    case "dock":
      printDock()
    case "pointer":
      let location = NSEvent.mouseLocation
      print("\(location.x),\(location.y)")
    case "move-pointer":
      guard arguments.count == 3, let x = Double(arguments[1]), let y = Double(arguments[2]) else {
        fail("usage: qa-helper move-pointer X Y")
      }
      movePointer(toX: x, y: y)
    case "align":
      align(Array(arguments.dropFirst()))
    default:
      fail("usage: qa-helper permissions|dock|pointer|move-pointer X Y|align KEY=VALUE…")
    }
  }
}
