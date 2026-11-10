import Foundation
import os

final class TestClock: Clock {
  struct Instant: InstantProtocol {
    let offset: Duration

    func advanced(by duration: Duration) -> Instant {
      Instant(offset: offset + duration)
    }

    func duration(to other: Instant) -> Duration {
      other.offset - offset
    }

    static func < (lhs: Instant, rhs: Instant) -> Bool {
      lhs.offset < rhs.offset
    }
  }

  private struct Sleeper {
    let deadline: Instant
    let continuation: CheckedContinuation<Void, any Error>
  }

  private struct State {
    var now = Instant(offset: .zero)
    var sleepers: [Int: Sleeper] = [:]
    var nextID = 0
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  var now: Instant { state.withLock { $0.now } }

  var minimumResolution: Duration { .zero }

  var sleeperCount: Int { state.withLock { $0.sleepers.count } }

  var timeToNextDeadline: Duration? {
    state.withLock { state in
      state.sleepers.values.map(\.deadline).min().map { state.now.duration(to: $0) }
    }
  }

  func sleep(until deadline: Instant, tolerance: Duration?) async throws {
    let id = state.withLock { state in
      state.nextID += 1
      return state.nextID
    }
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        enum Outcome {
          case wait
          case resume
          case cancel
        }
        let outcome = state.withLock { state -> Outcome in
          if Task.isCancelled { return .cancel }
          if deadline <= state.now { return .resume }
          state.sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
          return .wait
        }
        switch outcome {
        case .wait: break
        case .resume: continuation.resume()
        case .cancel: continuation.resume(throwing: CancellationError())
        }
      }
    } onCancel: {
      let sleeper = state.withLock { $0.sleepers.removeValue(forKey: id) }
      sleeper?.continuation.resume(throwing: CancellationError())
    }
  }

  func advance(by duration: Duration) {
    let due = state.withLock { state -> [Sleeper] in
      state.now = state.now.advanced(by: duration)
      let now = state.now
      let due = state.sleepers.filter { $0.value.deadline <= now }
      for id in due.keys {
        state.sleepers.removeValue(forKey: id)
      }
      return Array(due.values)
    }
    for sleeper in due {
      sleeper.continuation.resume()
    }
  }
}
