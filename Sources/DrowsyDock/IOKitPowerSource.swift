import DrowsyDockCore
import Foundation
import IOKit.ps

enum IOKitPowerSource {
  static var isLowPowerModeOn: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

  static func readBattery() -> BatteryReading? {
    guard
      let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue()
    else { return nil }

    let descriptions = (list as [CFTypeRef]).compactMap { source in
      IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
    }
    return PowerSourceParser.reading(from: descriptions)
  }

  /// `Subscription` is not main-actor isolated, so its `deinit` may read these non-Sendable
  /// handles. A main-actor class could not, because its `deinit` is nonisolated in Swift 6.0.
  final class Subscription {
    enum SubscriptionError: Error {
      case runLoopSourceUnavailable
    }

    private final class Callback: Sendable {
      let onChange: @MainActor @Sendable () -> Void

      init(_ onChange: @escaping @MainActor @Sendable () -> Void) {
        self.onChange = onChange
      }
    }

    private let callbackContext: Unmanaged<Callback>
    private let runLoopSource: CFRunLoopSource
    private let lowPowerObserver: any NSObjectProtocol

    init(onChange: @escaping @MainActor @Sendable () -> Void) throws {
      let handler = Callback(onChange)
      let callbackContext = Unmanaged.passRetained(handler)
      guard
        let source = IOPSNotificationCreateRunLoopSource(
          { context in
            guard let context else { return }
            let handler = Unmanaged<Callback>.fromOpaque(context).takeUnretainedValue()
            // The source is added to the main run loop below, so IOKit calls back on the main
            // thread.
            MainActor.assumeIsolated { handler.onChange() }
          },
          callbackContext.toOpaque()
        )?.takeRetainedValue()
      else {
        callbackContext.release()
        throw SubscriptionError.runLoopSourceUnavailable
      }
      // Common modes keep notifications flowing while the menu is open (event-tracking mode).
      CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

      self.callbackContext = callbackContext
      self.runLoopSource = source
      self.lowPowerObserver = NotificationCenter.default.addObserver(
        forName: .NSProcessInfoPowerStateDidChange,
        object: nil,
        queue: .main
      ) { _ in
        MainActor.assumeIsolated { handler.onChange() }
      }
    }

    deinit {
      CFRunLoopSourceInvalidate(runLoopSource)
      NotificationCenter.default.removeObserver(lowPowerObserver)
      // IOKit may be running the callback on the main thread right now, so free its context on
      // the main queue, after that callback returns. This holds because `init` adds the source
      // only to the main run loop, so IOKit never calls back on another thread.
      let callbackContext = callbackContext
      DispatchQueue.main.async { callbackContext.release() }
    }
  }
}
