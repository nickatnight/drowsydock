import CoreGraphics

/// What the overlay shows.
public enum OverlayPresentation: Equatable, Sendable {
  /// Nothing is drawn.
  case hidden

  /// The overlay is drawn at the perch.
  case shown(DockPerch)
}

/// The Dock tracker's decisions, kept free of AppKit and Accessibility calls so they can be
/// tested. `DockTracker` feeds it events and applies `presentation`.
public struct DockTrackerState: Equatable, Sendable {
  /// What the tracker knows about the Dock.
  public enum Phase: Equatable, Sendable {
    /// The app lacks the Accessibility grant, so it can't read the Dock.
    case untrusted

    /// The app has the grant but no usable read yet, or the last read failed.
    case unavailable

    /// The Dock is auto-hidden and off screen.
    case offScreen

    /// The Dock is on screen at this geometry.
    case resting(DockGeometry)
  }

  /// The size of the sprite drawn on the Dock.
  public let spriteSize: CGSize

  /// What the tracker knows about the Dock.
  public private(set) var phase = Phase.untrusted

  /// Starts untrusted, with the overlay hidden.
  public init(spriteSize: CGSize) {
    self.spriteSize = spriteSize
  }

  /// What the overlay shows in the current phase.
  public var presentation: OverlayPresentation {
    switch phase {
    case .untrusted, .unavailable, .offScreen:
      return .hidden
    case .resting(let geometry):
      return .shown(geometry.perch(for: spriteSize))
    }
  }

  /// Records a check of the Accessibility grant. After a new grant the tracker needs a fresh read.
  public mutating func accessibilityChanged(isGranted: Bool) {
    if !isGranted {
      phase = .untrusted
    } else if phase == .untrusted {
      phase = .unavailable
    }
  }

  /// Records a read of the Dock's geometry, or `nil` when the read failed.
  public mutating func dockRead(_ geometry: DockGeometry?) {
    guard phase != .untrusted else { return }
    guard let geometry else {
      phase = .unavailable
      return
    }
    phase = geometry.isHidden ? .offScreen : .resting(geometry)
  }
}
