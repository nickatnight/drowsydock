import Foundation

/// What restoring a defaults domain from a backup would change, key by key, for the confirmation
/// `scripts/qa-live.sh --restore` asks for.
public enum PreferencesChange {
  /// Returns one line per top-level key that differs between `live` and `backup`, sorted by key:
  /// "changed: key", "added: key" (only in the backup, so the restore adds it) or "removed: key"
  /// (only in the live domain, so the restore removes it).
  public static func summary(live: [String: Any], backup: [String: Any]) -> [String] {
    let keys = Set(live.keys).union(backup.keys).sorted()
    // Every key is in one dictionary or both, so a key missing from one is added or removed.
    return keys.compactMap { key in
      guard let saved = backup[key] else { return "removed: \(key)" }
      guard let now = live[key] else { return "added: \(key)" }
      return (now as AnyObject).isEqual(saved) ? nil : "changed: \(key)"
    }
  }

  /// Reads a property list file whose root is a dictionary, or returns `nil`.
  public static func dictionary(at url: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
  }
}
