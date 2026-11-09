import CoreGraphics

/// What the overlay shows.
public enum OverlayPresentation: Equatable, Sendable {
  /// Nothing is drawn.
  case hidden

  /// The overlay is drawn at the perch on the Dock at this resting geometry.
  case shown(DockPerch, on: DockGeometry)

  /// The overlay stays at the perch but is faded out, because the pointer is magnifying the Dock
  /// or is over the perch, where the Dock shows an icon's label.
  case fadedOut(DockPerch, on: DockGeometry)
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

    /// The Dock is on screen at this geometry, and the pointer is away from it.
    case resting(DockGeometry)

    /// The pointer is near the Dock resting at this geometry. Frame checks run, because the Dock
    /// posts no notification when it magnifies.
    case hovering(DockGeometry, isMagnified: Bool)

    /// The pointer has just left the Dock resting at this geometry. The next read, taken once
    /// the Dock has had time to shrink back, gives the new resting geometry.
    case settling(DockGeometry, isMagnified: Bool)
  }

  /// The size of the sprite drawn on the Dock.
  public let spriteSize: CGSize

  /// What the tracker knows about the Dock.
  public private(set) var phase = Phase.untrusted

  private var pointer: CGPoint?

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
      return .shown(geometry.perch(for: spriteSize), on: geometry)
    case .hovering(let geometry, let isMagnified):
      let perch = geometry.perch(for: spriteSize)
      let uncoversLabel = pointer.map(geometry.perchRegion(for: spriteSize).contains) ?? false
      return isMagnified || uncoversLabel
        ? .fadedOut(perch, on: geometry) : .shown(perch, on: geometry)
    case .settling(let geometry, let isMagnified):
      let perch = geometry.perch(for: spriteSize)
      return isMagnified ? .fadedOut(perch, on: geometry) : .shown(perch, on: geometry)
    }
  }

  /// Whether the caller should check the Dock's frames once a second. Only while the pointer is
  /// near the Dock, so no timer runs while the app is idle.
  public var runsFrameChecks: Bool {
    if case .hovering = phase { return true }
    return false
  }

  /// Whether the caller should read the Dock once it has settled after the pointer left.
  public var awaitsSettledRead: Bool {
    if case .settling = phase { return true }
    return false
  }

  /// Whether the caller should read the Dock as soon as an event says it may have changed.
  ///
  /// While the pointer is near the Dock or has just left it, the Dock may be magnified or
  /// shrinking back, so an immediate read could store the wrong geometry, and reading on every
  /// notification could become a read per animation frame. The frame checks and the settled read
  /// cover those phases. Without the grant, nothing is read.
  public var readsAtOnceOnDockChange: Bool {
    switch phase {
    case .unavailable, .offScreen, .resting:
      return true
    case .untrusted, .hovering, .settling:
      return false
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
  ///
  /// While the pointer is near the Dock, the read may catch it magnified, so it counts as a frame
  /// check instead.
  public mutating func dockRead(_ geometry: DockGeometry?) {
    switch phase {
    case .untrusted:
      return
    case .hovering:
      frameChecked(geometry)
    case .unavailable, .offScreen, .resting, .settling:
      guard let geometry else {
        phase = .unavailable
        return
      }
      phase = geometry.isHidden ? .offScreen : .resting(geometry)
    }
  }

  /// Records where the pointer is, in AppKit global coordinates.
  public mutating func pointerMoved(to point: CGPoint) {
    pointer = point
    switch phase {
    case .resting(let geometry) where geometry.hoverRegion.contains(point):
      phase = .hovering(geometry, isMagnified: false)
    case .hovering(let geometry, let isMagnified) where !geometry.hoverRegion.contains(point):
      phase = .settling(geometry, isMagnified: isMagnified)
    case .settling(let geometry, let isMagnified) where geometry.hoverRegion.contains(point):
      phase = .hovering(geometry, isMagnified: isMagnified)
    default:
      return
    }
  }

  /// Records a frame check, or `nil` when it failed. Only checks taken while the pointer is near
  /// the Dock count.
  ///
  /// A magnified Dock keeps the resting geometry, so the perch doesn't move. Any other change,
  /// such as a smaller Dock, becomes the new resting geometry.
  public mutating func frameChecked(_ current: DockGeometry?) {
    guard case .hovering(let resting, _) = phase, let current else { return }
    if current.isHidden {
      phase = .offScreen
    } else if DockGeometry.isMagnified(current: current, resting: resting) {
      phase = .hovering(resting, isMagnified: true)
    } else {
      phase = .hovering(current, isMagnified: false)
    }
  }
}
