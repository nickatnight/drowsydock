/// The timing of the "whole Dock nods off" wave: when each icon's "z" puff and dim start.
///
/// The wave runs along the Dock one icon after another. It keeps an even pace on a typical Dock
/// and speeds up on a crowded one, so the whole wave always fits in `maximumDuration`.
public struct CrowdWave: Equatable, Sendable {
  /// The spec's limit for the whole effect.
  public static let maximumDuration = Duration.seconds(4)

  /// How long one icon's effect lasts: the "z" puff rising and fading.
  public static let iconEffectDuration = Duration.seconds(1)

  /// How long an icon stays dimmed, at the start of its effect.
  public static let dimDuration = Duration.milliseconds(300)

  private static let preferredStagger = Duration.milliseconds(150)

  /// The number of icons the wave runs over.
  public let iconCount: Int

  /// Creates the wave for a Dock with `iconCount` icons.
  public init(iconCount: Int) {
    self.iconCount = iconCount
  }

  /// When the icon at `index` (counted along the Dock) starts, after the wave starts.
  public func startTime(ofIconAt index: Int) -> Duration {
    stagger * index
  }

  /// How long the whole wave lasts, until the last icon's effect ends.
  public var totalDuration: Duration {
    guard iconCount > 0 else { return .zero }
    return startTime(ofIconAt: iconCount - 1) + Self.iconEffectDuration
  }

  private var stagger: Duration {
    guard iconCount > 1 else { return .zero }
    let room = (Self.maximumDuration - Self.iconEffectDuration) / (iconCount - 1)
    return min(Self.preferredStagger, room)
  }
}
