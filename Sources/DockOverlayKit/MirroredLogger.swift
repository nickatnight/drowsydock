import os

/// Writes each log line to the unified log and to `mirror`, from one call, so the two can't
/// differ.
///
/// Every line the app and this library log goes through a `MirroredLogger`. The app sets `mirror`
/// at launch only when asked for a QA log (ADR 0020); otherwise a line goes to the unified log
/// alone. Every message is public, as each `Logger` call here marked it before.
@MainActor
public struct MirroredLogger {
  /// A line's severity. Each level is the `Logger` method of the same name.
  public enum Level: String, Sendable {
    case debug
    case notice
    case error
  }

  /// A destination for a line besides the unified log.
  public typealias Mirror = @MainActor (_ level: Level, _ category: String, _ message: String) ->
    Void

  /// What sends a line to the unified log through its `Logger`.
  package typealias UnifiedLog = @MainActor (Logger, Level, String) -> Void

  /// Receives every line after the unified log does. `nil`, the default, mirrors nothing.
  public static var mirror: Mirror?

  // Only an administrator can read the unified log back, so tests replace this to see what
  // reaches it.
  package static var unifiedLog: UnifiedLog = { logger, level, message in
    switch level {
    case .debug: logger.debug("\(message, privacy: .public)")
    case .notice: logger.notice("\(message, privacy: .public)")
    case .error: logger.error("\(message, privacy: .public)")
    }
  }

  private let logger: Logger
  private let category: String

  /// Creates a logger whose lines carry `subsystem` and `category` in the unified log, and
  /// `category` in the mirror.
  public init(subsystem: String, category: String) {
    logger = Logger(subsystem: subsystem, category: category)
    self.category = category
  }

  /// Logs `message` at debug level, which the unified log keeps only while it is streamed.
  public func debug(_ message: String) {
    write(message, at: .debug)
  }

  /// Logs `message` at notice level.
  public func notice(_ message: String) {
    write(message, at: .notice)
  }

  /// Logs `message` at error level.
  public func error(_ message: String) {
    write(message, at: .error)
  }

  private func write(_ message: String, at level: Level) {
    Self.unifiedLog(logger, level, message)
    Self.mirror?(level, category, message)
  }
}
