import AppKit
import ApplicationServices

/// Reads the Dock's geometry from the Dock process over the Accessibility API.
@MainActor
public enum DockReader {
  /// Why a read failed.
  public enum Failure: Error, Equatable {
    /// No process with the Dock's bundle identifier is running.
    case dockNotRunning

    /// `NSScreen.screens` is empty.
    case noDisplays

    /// The Dock has no element with the list role.
    case noIconList

    /// An Accessibility call returned an error, or a value of the wrong type. A code of -25211
    /// (`kAXErrorAPIDisabled`) means the app lacks the Accessibility grant.
    case accessibility(attribute: String, code: Int32)
  }

  static let dockBundleIdentifier = "com.apple.dock"
  private static let separatorSubrole = "AXSeparatorDockItem"

  /// Reads the frames of the Dock's icon list and items, and the display layout.
  public static func read() throws(Failure) -> DockGeometry {
    let screens = NSScreen.screens
    guard let primary = screens.first else { throw .noDisplays }
    let layout = DisplayLayout(primary: primary.frame, others: screens.dropFirst().map(\.frame))

    let list = try iconList().element
    let items = try elements(kAXChildrenAttribute, of: list)
    let icons = items.filter { (try? string(kAXSubroleAttribute, of: $0)) != separatorSubrole }
    return DockGeometry(
      listFrame: try frame(of: list),
      iconFrames: try icons.map { item throws(Failure) in try frame(of: item) },
      layout: layout
    )
  }

  /// Returns the Dock's process identifier and its icon-list element.
  static func iconList() throws(Failure) -> (processIdentifier: pid_t, element: AXUIElement) {
    guard
      let dock = NSRunningApplication.runningApplications(
        withBundleIdentifier: dockBundleIdentifier
      ).first
    else { throw .dockNotRunning }
    let application = AXUIElementCreateApplication(dock.processIdentifier)
    let children = try elements(kAXChildrenAttribute, of: application)
    let list = children.first { (try? string(kAXRoleAttribute, of: $0)) == kAXListRole }
    guard let list else { throw .noIconList }
    return (dock.processIdentifier, list)
  }

  private static func frame(of element: AXUIElement) throws(Failure) -> AXRect {
    var origin = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(try axValue(kAXPositionAttribute, of: element), .cgPoint, &origin) else {
      throw .accessibility(attribute: kAXPositionAttribute, code: AXError.illegalArgument.rawValue)
    }
    guard AXValueGetValue(try axValue(kAXSizeAttribute, of: element), .cgSize, &size) else {
      throw .accessibility(attribute: kAXSizeAttribute, code: AXError.illegalArgument.rawValue)
    }
    return AXRect(CGRect(origin: origin, size: size))
  }

  private static func axValue(_ attribute: String, of element: AXUIElement) throws(Failure)
    -> AXValue
  {
    let value = try copy(attribute, of: element)
    guard CFGetTypeID(value) == AXValueGetTypeID() else {
      throw .accessibility(attribute: attribute, code: AXError.illegalArgument.rawValue)
    }
    // The type ID check above makes this cast safe.
    return value as! AXValue
  }

  private static func elements(
    _ attribute: String,
    of element: AXUIElement
  ) throws(Failure) -> [AXUIElement] {
    guard let elements = try copy(attribute, of: element) as? [AXUIElement] else {
      throw .accessibility(attribute: attribute, code: AXError.illegalArgument.rawValue)
    }
    return elements
  }

  private static func string(_ attribute: String, of element: AXUIElement) throws(Failure) -> String
  {
    guard let string = try copy(attribute, of: element) as? String else {
      throw .accessibility(attribute: attribute, code: AXError.illegalArgument.rawValue)
    }
    return string
  }

  private static func copy(_ attribute: String, of element: AXUIElement) throws(Failure)
    -> CFTypeRef
  {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard error == .success, let value else {
      throw .accessibility(attribute: attribute, code: error.rawValue)
    }
    return value
  }
}
