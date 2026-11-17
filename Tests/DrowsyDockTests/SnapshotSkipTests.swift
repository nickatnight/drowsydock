import XCTest

final class SnapshotSkipTests: XCTestCase {
  func testTheVariableSetToOneSkipsTheSnapshots() {
    XCTAssertTrue(Snapshot.skipsSnapshots(in: ["DROWSYDOCK_SKIP_SNAPSHOTS": "1"]))
  }

  func testAnUnsetVariableRunsTheSnapshots() {
    XCTAssertFalse(Snapshot.skipsSnapshots(in: [:]))
  }

  func testTheVariableSetToZeroRunsTheSnapshots() {
    XCTAssertFalse(Snapshot.skipsSnapshots(in: ["DROWSYDOCK_SKIP_SNAPSHOTS": "0"]))
  }

  func testAnEmptyVariableRunsTheSnapshots() {
    XCTAssertFalse(Snapshot.skipsSnapshots(in: ["DROWSYDOCK_SKIP_SNAPSHOTS": ""]))
  }

  #if arch(arm64)
    func testAnUnsetVariableLetsTheSnapshotsRun() {
      XCTAssertNoThrow(try Snapshot.skipUnlessComparable(in: [:]))
    }

    func testTheVariableSetToZeroLetsTheSnapshotsRun() {
      XCTAssertNoThrow(
        try Snapshot.skipUnlessComparable(in: ["DROWSYDOCK_SKIP_SNAPSHOTS": "0"]))
    }

    func testAnEmptyVariableLetsTheSnapshotsRun() {
      XCTAssertNoThrow(try Snapshot.skipUnlessComparable(in: ["DROWSYDOCK_SKIP_SNAPSHOTS": ""]))
    }

    func testTheVariableSetToTrueLetsTheSnapshotsRun() {
      XCTAssertNoThrow(
        try Snapshot.skipUnlessComparable(in: ["DROWSYDOCK_SKIP_SNAPSHOTS": "true"]))
    }
  #endif

  func testTheSkipNamesTheVariableAndTheMacTheReferencesWereRecordedOn() throws {
    let recordedOn = try String(contentsOf: Snapshot.environmentFile, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    XCTAssertThrowsError(
      try Snapshot.skipUnlessComparable(in: ["DROWSYDOCK_SKIP_SNAPSHOTS": "1"])
    ) { error in
      let message = (error as? XCTSkip)?.message ?? ""
      XCTAssertTrue(message.contains("DROWSYDOCK_SKIP_SNAPSHOTS=1"), message)
      XCTAssertTrue(message.contains(recordedOn), message)
    }
  }
}
