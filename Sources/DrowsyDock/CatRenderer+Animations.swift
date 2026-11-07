import DrowsyDockCore
import SpriteKit

/// The cat's animations: ambient actions while it rests, and the one-shots that carry it from one
/// mood to the next. Every action runs under one key, so `stopAnimations()` can cancel them all
/// and put the cat back into its pose. Only one animation runs at a time.
extension CatRenderer {
  private static let animationKey = "animation"
  private static let floatingZName = "floatingZ"
  private static let sparkleName = "sparkle"

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
      withKey: Self.animationKey
    )
  }

  /// Starts `action` on a loop until `stopAnimations()`.
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

  /// Plays `animation`, ending in `target`, then calls `completion` on the main actor. The cat
  /// rests in `target` from the start, so stopping the animation early lands there too.
  func play(
    _ animation: MascotAnimation,
    to target: MascotPose,
    completion: @escaping @MainActor () -> Void
  ) {
    let from = pose
    pose = target
    let duration = Self.seconds(animation.duration)
    switch animation {
    case .crossfade:
      blend(to: target, over: duration)
    case .yawn:
      yawn(into: target)
    case .nodOff:
      nodOff(into: target, from: from)
    case .wakeUp:
      wakeUp(into: target)
    }
    node.run(
      .sequence([
        .wait(forDuration: duration),
        .run({ MainActor.assumeIsolated(completion) }, queue: .main),
      ]),
      withKey: Self.animationKey
    )
  }

  /// Cancels every animation and puts the cat back into its pose.
  func stopAnimations() {
    var parts: [SKNode] = [node, torso, head, snoreBubble, openMouth]
    parts += ears
    parts += lids
    parts += lashes
    parts += zs
    for part in parts {
      part.removeAction(forKey: Self.animationKey)
    }
    for child in node.children
    where child.name == Self.floatingZName || child.name == Self.sparkleName {
      child.removeFromParent()
    }
    apply(pose)
  }

  // MARK: - Transitions

  // Moves every posed part to `target` together.
  private func blend(to target: MascotPose, over duration: TimeInterval) {
    run(
      Self.eased(.moveTo(y: Self.lidEdge(at: target.eyelidOpenness), duration: duration)), on: lids)
    run(.fadeAlpha(to: Self.lashAlpha(at: target.eyelidOpenness), duration: duration), on: lashes)
    head.run(
      Self.eased(.rotate(toAngle: Self.radians(target.headTiltDegrees), duration: duration)),
      withKey: Self.animationKey
    )
    let droop = CGFloat(target.earDroop) * Metrics.maxEarDroop
    ears[0].run(Self.eased(.rotate(toAngle: droop, duration: duration)), withKey: Self.animationKey)
    ears[1].run(
      Self.eased(.rotate(toAngle: -droop, duration: duration)), withKey: Self.animationKey)
    for (index, z) in zs.enumerated() {
      z.run(
        .fadeAlpha(to: index < target.zCount ? 1 : 0, duration: duration),
        withKey: Self.animationKey
      )
    }
    snoreBubble.run(
      .fadeAlpha(to: target.showsSnoreBubble ? 1 : 0, duration: duration),
      withKey: Self.animationKey
    )
  }

  // Settles into the yawning pose, then yawns and nods.
  private func yawn(into target: MascotPose) {
    let settle = 0.5
    blend(to: target, over: settle)
    torso.run(
      .sequence([
        .wait(forDuration: settle),
        .run({ [weak self] in MainActor.assumeIsolated { _ = self?.yawnAndNod() } }, queue: .main),
      ]),
      withKey: Self.animationKey
    )
  }

  // The head droops forward as the eyes fall shut, jerks back up, and settles in the new pose.
  private func nodOff(into target: MascotPose, from: MascotPose) {
    let tilt = Self.radians(target.headTiltDegrees)
    let neck = Metrics.neck
    let droop = SKAction.group([
      .rotate(toAngle: tilt + Self.radians(14), duration: 1.3),
      .moveTo(y: neck.y - 2, duration: 1.3),
    ])
    let jerk = SKAction.group([
      .rotate(toAngle: tilt - Self.radians(3), duration: 0.15),
      .moveTo(y: neck.y + 0.6, duration: 0.15),
    ])
    let settle = SKAction.group([
      .rotate(toAngle: tilt, duration: 0.6),
      .moveTo(y: neck.y, duration: 0.6),
    ])
    droop.timingMode = .easeIn
    jerk.timingMode = .easeOut
    settle.timingMode = .easeInEaseOut
    head.run(.sequence([droop, jerk, settle]), withKey: Self.animationKey)

    run(
      .sequence([
        .moveTo(y: Self.lidEdge(at: 0), duration: 1.0),
        .wait(forDuration: 0.3),
        .moveTo(y: Self.lidEdge(at: max(target.eyelidOpenness, 0.35)), duration: 0.12),
        Self.eased(.moveTo(y: Self.lidEdge(at: target.eyelidOpenness), duration: 0.6)),
      ]),
      on: lids
    )
    run(.fadeIn(withDuration: 0.2), on: lashes)
    let droopEars = CGFloat(target.earDroop) * Metrics.maxEarDroop
    ears[0].run(.rotate(toAngle: droopEars, duration: 1.3), withKey: Self.animationKey)
    ears[1].run(.rotate(toAngle: -droopEars, duration: 1.3), withKey: Self.animationKey)
    for (index, z) in zs.enumerated() {
      z.run(
        .sequence([
          .wait(forDuration: 1.6),
          .fadeAlpha(to: index < target.zCount ? 1 : 0, duration: 0.5),
        ]),
        withKey: Self.animationKey
      )
    }
    snoreBubble.run(
      .fadeAlpha(to: target.showsSnoreBubble ? 1 : 0, duration: 0.4),
      withKey: Self.animationKey
    )
  }

  // The eyes snap open and the snore bubble pops, the cat stretches tall, sparkles twinkle around
  // its head, and it ends with a happy blink.
  private func wakeUp(into target: MascotPose) {
    let open = Self.lidEdge(at: target.eyelidOpenness)
    run(
      .sequence([
        .moveTo(y: open, duration: 0.08),
        .wait(forDuration: 2.1),
        .moveTo(y: Self.lidEdge(at: 0), duration: 0.08),
        .wait(forDuration: 0.05),
        .moveTo(y: open, duration: 0.12),
      ]),
      on: lids
    )
    run(
      .sequence([
        .fadeAlpha(to: Self.lashAlpha(at: target.eyelidOpenness), duration: 0.06),
        .wait(forDuration: 2.1),
        .fadeIn(withDuration: 0.04),
        .wait(forDuration: 0.15),
        .fadeAlpha(to: Self.lashAlpha(at: target.eyelidOpenness), duration: 0.06),
      ]),
      on: lashes
    )
    ears[0].run(.rotate(toAngle: 0, duration: 0.12), withKey: Self.animationKey)
    ears[1].run(.rotate(toAngle: 0, duration: 0.12), withKey: Self.animationKey)
    head.run(
      .sequence([
        Self.eased(.rotate(toAngle: Self.radians(target.headTiltDegrees), duration: 0.18)),
        .wait(forDuration: 0.1),
        .moveBy(x: 0, y: 2.5, duration: 0.35),
        .moveBy(x: 0, y: -2.5, duration: 0.35),
      ]),
      withKey: Self.animationKey
    )
    run(.fadeOut(withDuration: 0.15), on: zs)
    snoreBubble.run(
      .group([.scale(to: 1.7, duration: 0.15), .fadeOut(withDuration: 0.15)]),
      withKey: Self.animationKey
    )
    let stretch = SKAction.group([
      .scaleX(to: 0.94, duration: 0.35),
      .scaleY(to: 1.12, duration: 0.35),
    ])
    let relax = SKAction.group([.scaleX(to: 1, duration: 0.35), .scaleY(to: 1, duration: 0.35)])
    stretch.timingMode = .easeOut
    relax.timingMode = .easeIn
    torso.run(
      .sequence([.wait(forDuration: 0.28), stretch, relax]),
      withKey: Self.animationKey
    )
    for (index, spot) in [
      CGPoint(x: -19, y: 52), CGPoint(x: 20, y: 60), CGPoint(x: 23, y: 40),
    ].enumerated() {
      spawnSparkle(at: spot, after: 0.5 + Double(index) * 0.25)
    }
  }

  private func spawnSparkle(at spot: CGPoint, after delay: TimeInterval) {
    let sparkle = Self.sparkle()
    sparkle.name = Self.sparkleName
    sparkle.position = spot
    sparkle.setScale(0)
    node.addChild(sparkle)
    let appear = SKAction.group([
      .scale(to: 1, duration: 0.25),
      .rotate(byAngle: .pi / 2, duration: 0.25),
    ])
    appear.timingMode = .easeOut
    sparkle.run(
      .sequence([
        .wait(forDuration: delay),
        appear,
        .wait(forDuration: 0.3),
        .group([.fadeOut(withDuration: 0.5), .scale(to: 0.6, duration: 0.5)]),
        .removeFromParent(),
      ])
    )
  }

  private func run(_ action: SKAction, on parts: [SKNode]) {
    for part in parts {
      part.run(action, withKey: Self.animationKey)
    }
  }

  private static func eased(_ action: SKAction) -> SKAction {
    action.timingMode = .easeInEaseOut
    return action
  }

  private static func seconds(_ duration: Duration) -> TimeInterval {
    let (seconds, attoseconds) = duration.components
    return Double(seconds) + Double(attoseconds) / 1e18
  }

  // MARK: - One-shots

  private func blink(_ timing: (close: Double, hold: Double, open: Double)) -> TimeInterval {
    let close = SKAction.moveTo(y: Self.lidEdge(at: 0), duration: timing.close)
    let open = SKAction.moveTo(y: Self.lidEdge(at: pose.eyelidOpenness), duration: timing.open)
    close.timingMode = .easeIn
    open.timingMode = .easeOut
    let total = timing.close + timing.hold + timing.open
    for lid in lids {
      lid.run(
        .sequence([close, .wait(forDuration: timing.hold), open]), withKey: Self.animationKey)
    }
    for lash in lashes {
      lash.run(
        .sequence([
          .fadeIn(withDuration: timing.close / 2),
          .wait(forDuration: total - timing.close / 2 - timing.open / 2),
          .fadeAlpha(to: Self.lashAlpha(at: pose.eyelidOpenness), duration: timing.open / 2),
        ]),
        withKey: Self.animationKey
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
      withKey: Self.animationKey
    )

    let mouthOpen = SKAction.group([.fadeIn(withDuration: 0.3), .scale(to: 1, duration: 0.5)])
    let mouthClose = SKAction.group([
      .fadeOut(withDuration: 0.35),
      .scale(to: 0.3, duration: 0.4),
    ])
    openMouth.setScale(0.3)
    openMouth.run(
      .sequence([mouthOpen, .wait(forDuration: 0.9), mouthClose]),
      withKey: Self.animationKey
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
        withKey: Self.animationKey
      )
    }
    for lash in lashes {
      lash.run(
        .sequence([
          .fadeIn(withDuration: 0.1),
          .wait(forDuration: 2.5),
          .fadeAlpha(to: Self.lashAlpha(at: pose.eyelidOpenness), duration: 0.1),
        ]),
        withKey: Self.animationKey
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
      withKey: Self.animationKey
    )
    let down = SKAction.moveTo(y: Metrics.neck.y - 1.2, duration: Timing.zSpawnInterval)
    let up = SKAction.moveTo(y: Metrics.neck.y, duration: Timing.zSpawnInterval)
    down.timingMode = .easeInEaseOut
    up.timingMode = .easeInEaseOut
    head.run(.repeatForever(.sequence([down, up])), withKey: Self.animationKey)
  }

  // The body rises on each breath in. On each breath out the snore bubble swells and a "z" rises.
  private func snore() {
    hideStaticZs()
    let breath = Timing.breath
    let inhale = SKAction.scaleY(to: 1.035, duration: breath.inhale)
    let exhale = SKAction.scaleY(to: 1, duration: breath.exhale)
    inhale.timingMode = .easeInEaseOut
    exhale.timingMode = .easeInEaseOut
    torso.run(.repeatForever(.sequence([inhale, exhale])), withKey: Self.animationKey)

    let shrink = SKAction.scale(to: 0.45, duration: breath.inhale)
    let swell = SKAction.scale(to: 1.15, duration: breath.exhale)
    shrink.timingMode = .easeInEaseOut
    swell.timingMode = .easeInEaseOut
    snoreBubble.run(.repeatForever(.sequence([shrink, swell])), withKey: Self.animationKey)

    let spawn = SKAction.run(
      { [weak self] in MainActor.assumeIsolated { self?.spawnFloatingZ(size: 7.5) } },
      queue: .main
    )
    node.run(
      .repeatForever(
        .sequence([.wait(forDuration: breath.inhale), spawn, .wait(forDuration: breath.exhale)])
      ),
      withKey: Self.animationKey
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
