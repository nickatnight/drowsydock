import Darwin
import DockOverlayKit
import DrowsyDockCore
import Foundation

/// Appends every log line to `~/Library/Logs/DrowsyDock/qa.log` when DrowsyDock is launched with
/// `--qa-log`, so `scripts/qa-live.sh` can read the lines without the administrator account that
/// `log stream` needs (ADR 0020).
///
/// The folder is made private to the user (0700) and the file too (0600). A symbolic link at
/// either path, a hard link at the file's, or a path of another type or owner is refused, not
/// followed. The file starts over before a line would take it past `sizeLimit` bytes.
@MainActor
final class QALogFile {
  enum Error: Swift.Error, CustomStringConvertible {
    /// `open` or `mkdir` failed, with this `errno`. A symbolic link fails with `ELOOP`.
    case openFailed(path: String, errno: Int32)
    /// The path isn't a folder or a file of this user's, or the file has another name too.
    case notPrivate(path: String)

    var description: String {
      switch self {
      case .openFailed(let path, let errno):
        "can't open \(path): \(String(cString: strerror(errno)))"
      case .notPrivate(let path):
        "\(path) isn't this user's own folder or file, or has another link"
      }
    }
  }

  static let argument = "--qa-log"
  static let folder = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: "Library/Logs/DrowsyDock")
  static let fileName = "qa.log"
  // About 1,000 `Overlay:` lines for a Dock of 20 icons; each lists every icon's frame.
  static let sizeLimit = 1_048_576

  private static let logger = MirroredLogger(
    subsystem: "com.drowsydock.DrowsyDock",
    category: "qa-log"
  )

  private let descriptor: Int32
  private let sizeLimit: Int
  private let line = QALogLine(timeZone: .current)

  /// Mirrors every log line into the file when `arguments` hold `--qa-log`, and returns the file.
  /// Returns `nil`, creating nothing, without the argument or when the path is refused.
  @discardableResult
  static func startIfRequested(
    by arguments: [String],
    in folder: URL = folder,
    sizeLimit: Int = sizeLimit
  ) -> QALogFile? {
    guard arguments.dropFirst().contains(argument) else { return nil }
    let file: QALogFile
    do {
      file = try QALogFile(folder: folder, sizeLimit: sizeLimit)
    } catch {
      logger.error("No QA log: \(error)")
      return nil
    }
    MirroredLogger.mirror = { level, category, message in
      file.append(level: level.rawValue, category: category, message: message)
    }
    return file
  }

  private init(folder: URL, sizeLimit: Int) throws(Error) {
    let folderPath = folder.path
    if mkdir(folderPath, 0o700) != 0, errno != EEXIST {
      throw .openFailed(path: folderPath, errno: errno)
    }
    let folderDescriptor = open(folderPath, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard folderDescriptor >= 0 else { throw .openFailed(path: folderPath, errno: errno) }
    defer { close(folderDescriptor) }
    try Self.makePrivate(folderDescriptor, type: S_IFDIR, mode: 0o700, path: folderPath)

    let filePath = folder.appending(path: Self.fileName).path
    // O_NONBLOCK keeps a FIFO planted at the path from blocking the launch; the type check refuses
    // it.
    let descriptor = openat(
      folderDescriptor,
      Self.fileName,
      O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC,
      0o600
    )
    guard descriptor >= 0 else { throw .openFailed(path: filePath, errno: errno) }
    do {
      try Self.makePrivate(descriptor, type: S_IFREG, mode: 0o600, path: filePath)
    } catch {
      close(descriptor)
      throw error
    }
    self.descriptor = descriptor
    self.sizeLimit = sizeLimit
  }

  deinit {
    close(descriptor)
  }

  // Checks what `descriptor` opened, not the path, so a swap after the open can't redirect a write.
  private static func makePrivate(
    _ descriptor: Int32,
    type: mode_t,
    mode: mode_t,
    path: String
  ) throws(Error) {
    var status = stat()
    guard fstat(descriptor, &status) == 0 else { throw .openFailed(path: path, errno: errno) }
    guard status.st_mode & S_IFMT == type, status.st_uid == getuid(),
      type == S_IFDIR || status.st_nlink == 1
    else { throw .notPrivate(path: path) }
    if status.st_mode & 0o7777 != mode, fchmod(descriptor, mode) != 0 {
      throw .openFailed(path: path, errno: errno)
    }
  }

  private func append(level: String, category: String, message: String) {
    let bytes = Array(text(level: level, category: category, message: message).utf8)
    var status = stat()
    if fstat(descriptor, &status) == 0, Int(status.st_size) + bytes.count > sizeLimit {
      ftruncate(descriptor, 0)
      write(
        Array(
          text(
            level: "notice",
            category: "qa-log",
            message: "\(Self.fileName) reached its limit of \(sizeLimit) bytes and started over"
          ).utf8
        )
      )
    }
    write(bytes)
  }

  private func text(level: String, category: String, message: String) -> String {
    line.text(
      at: Date(),
      processIdentifier: getpid(),
      level: level,
      category: category,
      message: message
    ) + "\n"
  }

  // A line that can't be written is dropped: reporting it would log, and so write, again.
  private func write(_ bytes: [UInt8]) {
    _ = bytes.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
  }
}
