import Foundation
import LiveQAKit
import XCTest

final class PreferencesChangeTests: XCTestCase {
  func testEachDifferingKeyIsNamedOnceBySortedKey() {
    let live: [String: Any] = [
      "orientation": "left", "tilesize": 48, "qa-live-selftest": true, "autohide": false,
    ]
    let backup: [String: Any] = [
      "orientation": "bottom", "tilesize": 48, "magnification": true, "autohide": false,
    ]

    XCTAssertEqual(
      PreferencesChange.summary(live: live, backup: backup),
      ["added: magnification", "changed: orientation", "removed: qa-live-selftest"]
    )
  }

  func testNestedValuesCompareByContent() {
    let apps: [String: Any] = ["persistent-apps": [["tile-type": "file-tile"]]]

    XCTAssertEqual(PreferencesChange.summary(live: apps, backup: apps), [])
    XCTAssertEqual(
      PreferencesChange.summary(live: apps, backup: ["persistent-apps": [[String: Any]]()]),
      ["changed: persistent-apps"]
    )
  }

  func testOnlyADictionaryFileIsRead() throws {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("PreferencesChangeTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let dictionary = folder.appendingPathComponent("dock.plist")
    let string = folder.appendingPathComponent("garbage.plist")
    try PropertyListSerialization.data(fromPropertyList: ["tilesize": 48], format: .xml, options: 0)
      .write(to: dictionary)
    try Data("garbage".utf8).write(to: string)

    XCTAssertEqual(PreferencesChange.dictionary(at: dictionary)?["tilesize"] as? Int, 48)
    XCTAssertNil(PreferencesChange.dictionary(at: string))
  }

  // qa-live.sh passes `<(defaults export com.apple.dock -)`, which names a pipe in /dev/fd.
  func testADictionaryIsReadThroughAPipe() throws {
    let pipe = Pipe()
    try pipe.fileHandleForWriting.write(
      contentsOf: PropertyListSerialization.data(
        fromPropertyList: ["tilesize": 48],
        format: .xml,
        options: 0
      )
    )
    try pipe.fileHandleForWriting.close()
    let path = "/dev/fd/\(pipe.fileHandleForReading.fileDescriptor)"

    XCTAssertEqual(
      PreferencesChange.dictionary(at: URL(fileURLWithPath: path))?["tilesize"] as? Int,
      48
    )
  }
}
