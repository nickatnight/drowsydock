import DockOverlayKit
import DrowsyDockCore
import LiveQAKit
import XCTest

@testable import DrowsyDock

@MainActor
final class QALogFileTests: XCTestCase {
  private var folder: URL!
  private var file: URL { folder.appending(path: "qa.log") }

  override func setUp() async throws {
    let logs = FileManager.default.temporaryDirectory
      .appending(path: "QALogFileTests-\(UUID().uuidString)/Logs")
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    folder = logs.appending(path: "DrowsyDock")
    addTeardownBlock { [logs] in
      try? FileManager.default.removeItem(at: logs.deletingLastPathComponent())
    }
  }

  private func start(_ arguments: [String], sizeLimit: Int = QALogFile.sizeLimit) -> QALogFile? {
    addTeardownBlock { MirroredLogger.mirror = nil }
    return QALogFile.startIfRequested(by: arguments, in: folder, sizeLimit: sizeLimit)
  }

  private func lines() throws -> [String] {
    try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map(String.init)
  }

  private func message(_ line: String) throws -> String {
    let match = try XCTUnwrap(
      line.wholeMatch(of: #/\S+ DrowsyDock\[\d+\] \w+ [\w-]+: (.*)/#),
      "not a QA log line: \(line)"
    )
    return String(match.output.1)
  }

  private func permissions(of url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try XCTUnwrap(attributes[.posixPermissions] as? Int)
  }

  private let battery = MirroredLogger(subsystem: "com.drowsydock.tests", category: "battery")

  // MARK: - The argument

  func testWithoutTheArgumentNoFolderOrFileIsCreatedAndNothingIsMirrored() {
    let started = start(["/Applications/DrowsyDock.app/Contents/MacOS/DrowsyDock"])
    battery.notice("Started: 46% · Discharging · Drowsy (real)")

    XCTAssertNil(started)
    XCTAssertNil(MirroredLogger.mirror)
    XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
  }

  func testWithTheArgumentEachLineIsAppendedWithThisProcessesID() throws {
    XCTAssertNotNil(start(["DrowsyDock", "--qa-log"]))

    battery.notice("Started: 46% · Discharging · Drowsy (real)")
    battery.debug("Power source notification")

    let lines = try lines()
    XCTAssertEqual(lines.count, 2)
    XCTAssertTrue(
      lines[0].hasSuffix(
        " DrowsyDock[\(getpid())] notice battery: Started: 46% · Discharging · Drowsy (real)"
      ),
      lines[0]
    )
    XCTAssertTrue(
      lines[1].hasSuffix(" DrowsyDock[\(getpid())] debug battery: Power source notification")
    )
  }

  // The latency checks read nothing but this time, through the same parser.
  func testEachLineCarriesTheTimeItWasWrittenAsTheScriptReadsIt() throws {
    XCTAssertNotNil(start(["DrowsyDock", "--qa-log"]))

    let before = Date().timeIntervalSince1970
    battery.notice("Changed: 80% · Discharging · Awake (simulated 80%)")
    let after = Date().timeIntervalSince1970

    let written = try XCTUnwrap(OverlayLog.time(of: try XCTUnwrap(lines().first)))
    XCTAssertGreaterThanOrEqual(written, before - 0.001)
    XCTAssertLessThanOrEqual(written, after + 0.001)
  }

  func testALaterLaunchAppendsToTheLinesOfAnEarlierOne() throws {
    XCTAssertNotNil(start(["DrowsyDock", "--qa-log"]))
    battery.notice("first launch")
    XCTAssertNotNil(start(["DrowsyDock", "--qa-log"]))
    battery.notice("second launch")

    XCTAssertEqual(
      try lines().map(message),
      ["first launch", "second launch"]
    )
  }

  // MARK: - The path

  func testTheScriptReadsTheFileTheAppWritesWhateverHOMESays() throws {
    let liveFunctions = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appending(path: "../../scripts/qa/live-functions.sh")
    let script = Process()
    script.executableURL = URL(fileURLWithPath: "/bin/bash")
    script.arguments = ["-c", "source \"$0\" && qa_log_path", liveFunctions.path]
    script.environment = [
      "PATH": "/usr/bin:/bin",
      "HOME": folder.path,
      "CFFIXED_USER_HOME": folder.path,
    ]
    let output = Pipe()
    script.standardOutput = output
    try script.run()
    script.waitUntilExit()
    let scriptsPath = String(
      decoding: output.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    )

    let appsFile = try XCTUnwrap(QALogFile.folder).appending(path: QALogFile.fileName)
    XCTAssertEqual(scriptsPath, appsFile.path + "\n")
    XCTAssertTrue(appsFile.path.hasSuffix("/Library/Logs/DrowsyDock/qa.log"), appsFile.path)
  }

  // MARK: - Permissions

  func testTheFolderIsTheUsersAloneAndTheFileTooEvenIfTheyWereWiderBefore() throws {
    XCTAssertNotNil(start(["DrowsyDock", "--qa-log"]))
    XCTAssertEqual(try permissions(of: folder), 0o700)
    XCTAssertEqual(try permissions(of: file), 0o600)

    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
    XCTAssertNotNil(start(["DrowsyDock", "--qa-log"]))

    XCTAssertEqual(try permissions(of: folder), 0o700)
    XCTAssertEqual(try permissions(of: file), 0o600)
  }

  // MARK: - Links

  func testASymbolicLinkAtTheFilesPathIsRefusedAndItsTargetIsUntouched() throws {
    let target = folder.deletingLastPathComponent().appending(path: "elsewhere.txt")
    try "kept\n".write(to: target, atomically: false, encoding: .utf8)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)

    XCTAssertNil(start(["DrowsyDock", "--qa-log"]))
    battery.notice("Started: 46% · Discharging · Drowsy (real)")

    XCTAssertNil(MirroredLogger.mirror)
    XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "kept\n")
  }

  func testASymbolicLinkAtTheFoldersPathIsRefusedAndNothingIsWrittenThroughIt() throws {
    let target = folder.deletingLastPathComponent().appending(path: "elsewhere")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
    try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: target)

    XCTAssertNil(start(["DrowsyDock", "--qa-log"]))

    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), [])
  }

  func testAHardLinkAtTheFilesPathIsRefusedAndTheOtherNameIsUntouched() throws {
    let other = folder.deletingLastPathComponent().appending(path: "other.txt")
    try "kept\n".write(to: other, atomically: false, encoding: .utf8)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    try FileManager.default.linkItem(at: other, to: file)

    XCTAssertNil(start(["DrowsyDock", "--qa-log"]))
    battery.notice("Started: 46% · Discharging · Drowsy (real)")

    XCTAssertEqual(try String(contentsOf: other, encoding: .utf8), "kept\n")
  }

  // MARK: - Size

  func testTheFileStartsOverBeforeALineWouldTakeItPastItsLimit() throws {
    let limit = 600
    XCTAssertNotNil(start(["DrowsyDock", "--qa-log"], sizeLimit: limit))

    for count in 1...40 {
      battery.notice("Changed: line \(count)")
      let size = try XCTUnwrap(
        FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int
      )
      XCTAssertLessThanOrEqual(size, limit, "after line \(count)")
    }

    let lines = try lines()
    XCTAssertTrue(
      lines[0].hasSuffix("qa-log: qa.log reached its limit of 600 bytes and started over")
    )
    XCTAssertTrue(try XCTUnwrap(lines.last).hasSuffix("battery: Changed: line 40"))
  }

  // MARK: - Launch order

  func testTheCoordinatorTheAppLaunchesWritesItsFirstLinesToTheFile() throws {
    addTeardownBlock { MirroredLogger.mirror = nil }

    let coordinator = AppCoordinator(arguments: ["DrowsyDock", "--qa-log"], qaLogFolder: folder)
    addTeardownBlock { coordinator.overlay.show(nil) }
    KeepAlive.keep(coordinator)

    let firstTwo = try lines().prefix(2).map(message)
    XCTAssertEqual(
      firstTwo.map { $0.components(separatedBy: ": ").first },
      ["Started", "Accessibility granted"]
    )
    XCTAssertTrue(firstTwo.first?.hasSuffix(" (real)") ?? false, "\(firstTwo)")
  }

  // MARK: - Both sinks

  func testEveryLineTheAppLogsReachesTheUnifiedLogAndTheFileAlike() throws {
    var unified: [String] = []
    let realUnifiedLog = MirroredLogger.unifiedLog
    MirroredLogger.unifiedLog = { _, _, message in unified.append(message) }
    addTeardownBlock { MirroredLogger.unifiedLog = realUnifiedLog }
    XCTAssertNotNil(start(["DrowsyDock", "--qa-log"]))

    let power = FakePowerSource(BatteryReading(clampingPercentage: 46, powerState: .discharging))
    let tracker = FakeDockTracker()
    let coordinator = AppCoordinator(
      battery: BatteryMonitor(source: power, clock: TestClock()),
      overlay: MascotOverlay(catScene: MascotScene(clock: TestClock())),
      readsAccessibilityGrant: { true },
      makeDockTracker: { onPresentationChange in
        tracker.onPresentationChange = onPresentationChange
        return tracker
      }
    )
    addTeardownBlock { coordinator.overlay.show(nil) }
    KeepAlive.keep(coordinator)
    coordinator.startDockTracking()
    tracker.present(.hidden)
    coordinator.battery.simulate(.discharging(percentage: 15))
    coordinator.battery.simulate(.discharging(percentage: 5))

    let expected = [
      "Started: 46% · Discharging · Drowsy (real)",
      "Accessibility granted: true",
      "Changed: 15% · Discharging · Nodding off (simulated 15%)",
      "Changed: 5% · Discharging · Asleep (simulated 5%)",
      "The whole Dock would nod off, but the overlay isn't showing",
    ]
    XCTAssertEqual(unified, expected)
    XCTAssertEqual(try lines().map(message), expected)
  }
}
