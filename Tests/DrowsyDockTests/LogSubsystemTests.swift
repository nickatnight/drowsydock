import Foundation
import XCTest

@testable import DrowsyDock

final class LogSubsystemTests: XCTestCase {
  private static let infoPlist = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "../../Resources/Info.plist")

  func testTheSubsystemIsTheBundleIdentifierInInfoPlist() throws {
    let data = try Data(contentsOf: Self.infoPlist)
    let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
    let bundleIdentifier = (plist as? [String: Any])?["CFBundleIdentifier"] as? String

    XCTAssertEqual(LogSubsystem.app, bundleIdentifier)
  }
}
