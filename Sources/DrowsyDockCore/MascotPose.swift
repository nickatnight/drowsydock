/// How the cat holds itself while nothing is animating: one pose per drowsiness state.
///
/// The renderer draws these values; animations move between them.
public struct MascotPose: Equatable, Sendable {
  /// How far the eyes are open, from 0 (shut) to 1 (wide open).
  public let eyelidOpenness: Double

  /// How far the head leans toward the way the cat faces, in degrees.
  public let headTiltDegrees: Double

  /// How far the ears fold sideways, from 0 (pricked up) to 1 (fully drooped).
  public let earDroop: Double

  /// How many static "z"s float beside the head.
  public let zCount: Int

  /// Whether a snore bubble sits at the nose.
  public let showsSnoreBubble: Bool

  /// How dark the veil over the Dock is, from 0 (none) to 1 (opaque).
  public let veilOpacity: Double

  /// Creates the pose for `state`.
  public init(for state: DrowsinessState) {
    switch state {
    case .awake:
      self.init(eyelids: 1, tilt: 0, earDroop: 0)
    case .drowsy:
      self.init(eyelids: 0.55, tilt: 4, earDroop: 0.2)
    case .yawning:
      self.init(eyelids: 0.28, tilt: 9, earDroop: 0.45)
    case .noddingOff:
      self.init(eyelids: 0.12, tilt: 14, earDroop: 0.7, zCount: 1)
    case .asleep:
      // Dark enough to read as "lights out", light enough that every icon stays recognisable.
      self.init(
        eyelids: 0,
        tilt: 20,
        earDroop: 1,
        zCount: 2,
        showsSnoreBubble: true,
        veilOpacity: 0.28
      )
    }
  }

  private init(
    eyelids: Double,
    tilt: Double,
    earDroop: Double,
    zCount: Int = 0,
    showsSnoreBubble: Bool = false,
    veilOpacity: Double = 0
  ) {
    eyelidOpenness = eyelids
    headTiltDegrees = tilt
    self.earDroop = earDroop
    self.zCount = zCount
    self.showsSnoreBubble = showsSnoreBubble
    self.veilOpacity = veilOpacity
  }
}
