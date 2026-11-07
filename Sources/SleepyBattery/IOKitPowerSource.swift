import Foundation
import IOKit.ps
import SleepyBatteryCore

/// Reads the internal battery and Low Power Mode, and reports changes to either without polling.
@MainActor
final class IOKitPowerSource {
  /// Removes the IOKit and Low Power Mode registrations when released.
  ///
  /// It is not main-actor isolated, so its `deinit` may read these non-Sendable handles. The
  /// isolated `IOKitPowerSource` cannot, because its `deinit` is nonisolated in Swift 6.0.
  private final class Registrations {
    var runLoopSource: CFRunLoopSource?
    var lowPowerObserver: (any NSObjectProtocol)?

    deinit {
      if let runLoopSource {
        CFRunLoopSourceInvalidate(runLoopSource)
      }
      if let lowPowerObserver {
        NotificationCenter.default.removeObserver(lowPowerObserver)
      }
    }
  }

  private var onChange: (@MainActor () -> Void)?
  private let registrations = Registrations()

  /// Whether Low Power Mode is on.
  var isLowPowerModeOn: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

  /// Returns the internal battery's reading, or `nil` when the Mac has none.
  func readBattery() -> BatteryReading? {
    guard
      let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue()
    else { return nil }

    let descriptions = (list as [CFTypeRef]).compactMap { source in
      IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
    }
    return PowerSourceParser.reading(from: descriptions)
  }

  /// Calls `onChange` on the main actor whenever a power source or Low Power Mode changes.
  ///
  /// Returns `false` if IOKit could not create the notification source.
  func startObserving(onChange: @escaping @MainActor () -> Void) -> Bool {
    self.onChange = onChange

    // The context is unretained: releasing `registrations` invalidates the source along with
    // `self`.
    let context = Unmanaged.passUnretained(self).toOpaque()
    guard
      let source = IOPSNotificationCreateRunLoopSource(
        { context in
          guard let context else { return }
          let powerSource = Unmanaged<IOKitPowerSource>.fromOpaque(context).takeUnretainedValue()
          // The source is added to the main run loop below, so IOKit calls back on the main
          // thread.
          MainActor.assumeIsolated { powerSource.onChange?() }
        },
        context
      )?.takeRetainedValue()
    else { return false }
    // Common modes keep notifications flowing while the menu is open (event-tracking mode).
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    registrations.runLoopSource = source

    registrations.lowPowerObserver = NotificationCenter.default.addObserver(
      forName: .NSProcessInfoPowerStateDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.onChange?() }
    }
    return true
  }
}
