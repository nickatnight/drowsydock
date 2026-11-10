import AppKit
import ApplicationServices
import DockOverlayKit
import LiveQAKit

@main
@MainActor
enum QAHelper {
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

  static func size(_ text: String) -> CGSize {
    let parts = text.split(separator: ",").compactMap { Double($0) }
    guard parts.count == 2 else { fail("expected width,height, got \(text)") }
    return CGSize(width: parts[0], height: parts[1])
  }

  static func primaryHeight() -> CGFloat {
    NSScreen.screens.first?.frame.height ?? 0
  }

  // With `sprite`, the size the app draws the cat at (from its log), it also prints where
  // DockGeometry perches that sprite and the area to capture around the Dock and the perch.
  static func printDock(sprite: CGSize?) {
    let geometry: DockGeometry
    do {
      geometry = try DockReader.read()
    } catch {
      fail("Dock geometry unavailable: \(error)")
    }
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
    print("facing=\(geometry.perch(for: .zero).facing == .left ? "left" : "right")")
    if let sprite {
      let perch = geometry.perch(for: sprite).frame
      let area = CaptureArea.around(
        background: geometry.backgroundFrame,
        perch: perch,
        on: geometry.screenFrame,
        scale: scale
      )
      print("perch=\(describe(perch))")
      print("capture=\(describe(area.frame))")
      print("capture-region=\(area.screencaptureRegion(primaryHeight: primaryHeight()))")
    }
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
      let sprite = arguments.dropFirst().first { $0.hasPrefix("sprite=") }
        .map { size(String($0.dropFirst("sprite=".count))) }
      printDock(sprite: sprite)
    case "logged-perch":
      guard arguments.count == 2, let perch = OverlayLog.perchFrame(in: arguments[1]) else {
        fail("no DockPerch frame in the log line")
      }
      print(describe(perch))
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
      fail(
        "usage: qa-helper permissions|dock [sprite=W,H]|logged-perch LINE|pointer"
          + "|move-pointer X Y|align KEY=VALUE…"
      )
    }
  }
}
