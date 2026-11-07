import DrowsyDockCore
import SpriteKit

/// The cat's ambient actions. Each runs under one action key, so `stopAmbient()` can cancel them
/// all and put the cat back into its pose.
extension CatRenderer {
  private static let ambientKey = "ambient"
  private static let floatingZName = "floatingZ"

  private enum Timing {
    static let blink = (close: 0.08, hold: 0.04, open: 0.12)
    static let slowBlink = (close: 0.4, hold: 0.25, open: 0.45)
    static let zSpawnInterval = 1.6
    static let zRise = 2.6
    static let breath = (inhale: 1.5, exhale: 1.7)
  }

  /// Plays `action` once, then calls `completion` on the main actor. A looping action starts its
  /// loop instead and never completes.
  func play(_ action: AmbientAction, completion: @escaping @MainActor () -> Void) {
    let duration: TimeInterval
    switch action {
    case .blink:
      duration = blink(Timing.blink)
    case .slowBlink:
      duration = blink(Timing.slowBlink)
    case .yawnAndNod:
      duration = yawnAndNod()
    case .floatingZs, .snore:
      loop(action)
      return
    }
    node.run(
      .sequence([
        .wait(forDuration: duration),
        .run({ MainActor.assumeIsolated(completion) }, queue: .main),
      ]),
      withKey: Self.ambientKey
    )
  }

  /// Starts `action` on a loop until `stopAmbient()`.
  func loop(_ action: AmbientAction) {
    switch action {
    case .floatingZs:
      floatZs()
    case .snore:
      snore()
    case .blink, .slowBlink, .yawnAndNod:
      play(action) {}
    }
  }

  /// Cancels every ambient action and puts the cat back into its pose.
  func stopAmbient() {
    for part in [node, torso, head, snoreBubble, openMouth] + lids + lashes {
      part.removeAction(forKey: Self.ambientKey)
    }
    for child in node.children where child.name == Self.floatingZName {
      child.removeFromParent()
    }
    apply(pose)
  }

  // MARK: - One-shots

  private func blink(_ timing: (close: Double, hold: Double, open: Double)) -> TimeInterval {
    let close = SKAction.moveTo(y: Self.lidEdge(at: 0), duration: timing.close)
    let open = SKAction.moveTo(y: Self.lidEdge(at: pose.eyelidOpenness), duration: timing.open)
    close.timingMode = .easeIn
    open.timingMode = .easeOut
    let total = timing.close + timing.hold + timing.open
    for lid in lids {
      lid.run(.sequence([close, .wait(forDuration: timing.hold), open]), withKey: Self.ambientKey)
    }
    for lash in lashes {
      lash.run(
        .sequence([
          .fadeIn(withDuration: timing.close / 2),
          .wait(forDuration: total - timing.close / 2 - timing.open / 2),
          .fadeAlpha(to: Self.lashAlpha(at: pose.eyelidOpenness), duration: timing.open / 2),
        ]),
        withKey: Self.ambientKey
      )
    }
    return total
  }

  // Leans back with the mouth wide and the eyes squeezed shut, then nods forward, jerks back up
  // and settles. About 3 s.
  private func yawnAndNod() -> TimeInterval {
    let tilt = Self.radians(pose.headTiltDegrees)
    let restingLids = Self.lidEdge(at: pose.eyelidOpenness)
    let neck = Metrics.neck

    let leanBack = SKAction.rotate(toAngle: tilt - Self.radians(9), duration: 0.5)
    let straighten = SKAction.rotate(toAngle: tilt, duration: 0.4)
    let nodDown = SKAction.group([
      .rotate(toAngle: tilt + Self.radians(10), duration: 0.6),
      .moveTo(y: neck.y - 2.5, duration: 0.6),
    ])
    let jerkUp = SKAction.group([
      .rotate(toAngle: tilt, duration: 0.22),
      .moveTo(y: neck.y, duration: 0.22),
    ])
    leanBack.timingMode = .easeOut
    nodDown.timingMode = .easeIn
    jerkUp.timingMode = .easeOut
    head.run(
      .sequence([leanBack, .wait(forDuration: 0.9), straighten, nodDown, jerkUp]),
      withKey: Self.ambientKey
    )

    let mouthOpen = SKAction.group([.fadeIn(withDuration: 0.3), .scale(to: 1, duration: 0.5)])
    let mouthClose = SKAction.group([
      .fadeOut(withDuration: 0.35),
      .scale(to: 0.3, duration: 0.4),
    ])
    openMouth.setScale(0.3)
    openMouth.run(
      .sequence([mouthOpen, .wait(forDuration: 0.9), mouthClose]),
      withKey: Self.ambientKey
    )

    for lid in lids {
      lid.run(
        .sequence([
          .moveTo(y: Self.lidEdge(at: 0), duration: 0.4),
          .wait(forDuration: 1.2),
          .moveTo(y: Self.lidEdge(at: pose.eyelidOpenness * 0.5), duration: 0.3),
          .wait(forDuration: 0.5),
          .moveTo(y: restingLids, duration: 0.2),
        ]),
        withKey: Self.ambientKey
      )
    }
    for lash in lashes {
      lash.run(
        .sequence([
          .fadeIn(withDuration: 0.1),
          .wait(forDuration: 2.5),
          .fadeAlpha(to: Self.lashAlpha(at: pose.eyelidOpenness), duration: 0.1),
        ]),
        withKey: Self.ambientKey
      )
    }
    return 2.9
  }

  // MARK: - Loops

  // "z"s rise from behind the head one after another, and the head bobs gently.
  private func floatZs() {
    hideStaticZs()
    let spawn = SKAction.run(
      { [weak self] in MainActor.assumeIsolated { self?.spawnFloatingZ(size: 6) } },
      queue: .main
    )
    node.run(
      .repeatForever(.sequence([spawn, .wait(forDuration: Timing.zSpawnInterval)])),
      withKey: Self.ambientKey
    )
    let down = SKAction.moveTo(y: Metrics.neck.y - 1.2, duration: Timing.zSpawnInterval)
    let up = SKAction.moveTo(y: Metrics.neck.y, duration: Timing.zSpawnInterval)
    down.timingMode = .easeInEaseOut
    up.timingMode = .easeInEaseOut
    head.run(.repeatForever(.sequence([down, up])), withKey: Self.ambientKey)
  }

  // The body rises on each breath in. On each breath out the snore bubble swells and a "z" rises.
  private func snore() {
    hideStaticZs()
    let breath = Timing.breath
    let inhale = SKAction.scaleY(to: 1.035, duration: breath.inhale)
    let exhale = SKAction.scaleY(to: 1, duration: breath.exhale)
    inhale.timingMode = .easeInEaseOut
    exhale.timingMode = .easeInEaseOut
    torso.run(.repeatForever(.sequence([inhale, exhale])), withKey: Self.ambientKey)

    let shrink = SKAction.scale(to: 0.45, duration: breath.inhale)
    let swell = SKAction.scale(to: 1.15, duration: breath.exhale)
    shrink.timingMode = .easeInEaseOut
    swell.timingMode = .easeInEaseOut
    snoreBubble.run(.repeatForever(.sequence([shrink, swell])), withKey: Self.ambientKey)

    let spawn = SKAction.run(
      { [weak self] in MainActor.assumeIsolated { self?.spawnFloatingZ(size: 7.5) } },
      queue: .main
    )
    node.run(
      .repeatForever(
        .sequence([.wait(forDuration: breath.inhale), spawn, .wait(forDuration: breath.exhale)])
      ),
      withKey: Self.ambientKey
    )
  }

  private func hideStaticZs() {
    for z in zs {
      z.alpha = 0
    }
  }

  private func spawnFloatingZ(size: CGFloat) {
    let z = Self.z(size: size)
    z.setScale(0.6)
    // The holder carries the mirroring, so the letter reads the right way round when the cat
    // faces right.
    let holder = SKNode()
    holder.name = Self.floatingZName
    holder.xScale = node.xScale
    holder.position = CGPoint(x: 14, y: 48)
    holder.alpha = 0
    holder.addChild(z)
    node.addChild(holder)
    let rise = Timing.zRise
    z.run(.scale(to: 1.15, duration: rise))
    holder.run(
      .sequence([
        .group([
          .moveBy(x: 8, y: 20, duration: rise),
          .sequence([
            .fadeIn(withDuration: 0.3),
            .wait(forDuration: rise - 1.1),
            .fadeOut(withDuration: 0.8),
          ]),
        ]),
        .removeFromParent(),
      ])
    )
  }
}
