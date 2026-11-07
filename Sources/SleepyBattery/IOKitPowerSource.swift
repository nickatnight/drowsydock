import Foundation
import IOKit.ps
import SleepyBatteryCore

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

  var isLowPowerModeOn: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

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

  func startObserving(onChange: @escaping @MainActor () -> Void) -> Bool {
    self.onChange = onChange

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
