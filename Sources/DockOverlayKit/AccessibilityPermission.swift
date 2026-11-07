import AppKit
import ApplicationServices

/// The Accessibility permission, which reading the Dock's geometry needs.
@MainActor
public enum AccessibilityPermission {
  // `kAXTrustedCheckOptionPrompt` is a mutable C global, which Swift 6 rejects under strict
  // concurrency. This is its value.
  private static let promptOption = "AXTrustedCheckOptionPrompt"

  private static let settingsURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
  )

  /// Whether this process may read other apps' interface elements. Checking never prompts.
  public static var isGranted: Bool {
    AXIsProcessTrustedWithOptions([promptOption: false] as CFDictionary)
  }

  /// Asks macOS to list this app in the Accessibility pane, then opens that pane.
  ///
  /// The request also shows the system's own alert. Without it, the app is missing from the
  /// pane's list, and the user would have to add it with the + button.
  public static func requestAndOpenSettings() {
    _ = AXIsProcessTrustedWithOptions([promptOption: true] as CFDictionary)
    guard let settingsURL else { return }
    NSWorkspace.shared.open(settingsURL)
  }
}
