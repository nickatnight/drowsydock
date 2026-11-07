import DrowsyDockCore
import SpriteKit

extension CatRenderer {
  private static let animationKey = "animation"
  private static let floatingZName = "floatingZ"
  private static let sparkleName = "sparkle"

  private typealias BlinkTiming = (close: Double, hold: Double, open: Double)

  private enum Timing {
    static let blink: BlinkTiming = (close: 0.08, hold: 0.04, open: 0.12)
    static let slowBlink: BlinkTiming = (close: 0.4, hold: 0.25, open: 0.45)
    static let zSpawnInterval = 1.6
    static let zRise = 2.6
    static let breath = (inhale: 1.5, exhale: 1.7)
    static let lashFade = 0.1
  }

  // The phases of the yawn and nod, in order. The mouth and the eyelids follow the head.
  private enum YawnAndNod {
    static let leanBack = 0.5
    static let holdYawn = 0.9
    static let straighten = 0.4
    static let nodDown = 0.6
    static let jerkUp = 0.22
    static let length = leanBack + holdYawn + straighten + nodDown + jerkUp
  }

  // The nod-off's last phase, the settle, takes whatever `MascotAnimation.nodOff` leaves.
  private enum NodOff {
    static let droop = 1.3
    static let jerk = 0.15
    static let jerkOpenness = 0.35
  }

  // The wake-up holds the open eyes until a final blink that ends with `MascotAnimation.wakeUp`.
  private enum WakeUp {
    static let snapOpen = 0.08
    static let earsUp = 0.12
    static let pop = 0.15
    static let headStraighten = 0.18
    static let stretchDelay = 0.28
    static let stretch = 0.35
    static let firstSparkle = 0.5
    static let sparkleInterval = 0.25
  }

  /// Plays `gesture` once, then calls `completion` on the main actor.
  func play(_ gesture: AmbientGesture, completion: @escaping @MainActor () -> Void) {
    let duration: TimeInterval
    switch gesture {
    case .blink:
      duration = blink(Timing.blink)
    case .slowBlink:
      duration = blink(Timing.slowBlink)
    case .yawnAndNod:
      duration = yawnAndNod()
    }
    node.run(
      .sequence([
        .wait(forDuration: duration),
        .run({ MainActor.assumeIsolated(completion) }, queue: .main),
      ]),
      withKey: Self.animationKey
    )
  }

  func loop(_ loop: AmbientLoop) {
    switch loop {
    case .floatingZs:
      floatZs()
    case .snore:
      snore()
    }
  }

  /// Plays `animation`, ending in `target`, then calls `completion` on the main actor.
  func play(
    _ animation: MascotAnimation,
    to target: MascotPose,
    completion: @escaping @MainActor () -> Void
  ) {
    pose = target
    let duration = animation.duration.inSeconds
    switch animation {
    case .crossfade:
      blend(to: target, over: duration)
    case .yawn:
      yawn(into: target)
    case .nodOff:
      nodOff(into: target)
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

  private func yawn(into target: MascotPose) {
    let settle = MascotAnimation.yawn.duration.inSeconds - YawnAndNod.length
    blend(to: target, over: settle)
    torso.run(
      .sequence([
        .wait(forDuration: settle),
        .run({ [weak self] in MainActor.assumeIsolated { _ = self?.yawnAndNod() } }, queue: .main),
      ]),
      withKey: Self.animationKey
    )
  }

  private func nodOff(into target: MascotPose) {
    let settleTime = MascotAnimation.nodOff.duration.inSeconds - NodOff.droop - NodOff.jerk
    let tilt = Self.radians(target.headTiltDegrees)
    let neck = Metrics.neck
    let droop = SKAction.group([
      .rotate(toAngle: tilt + Self.radians(14), duration: NodOff.droop),
      .moveTo(y: neck.y - 2, duration: NodOff.droop),
    ])
    let jerk = SKAction.group([
      .rotate(toAngle: tilt - Self.radians(3), duration: NodOff.jerk),
      .moveTo(y: neck.y + 0.6, duration: NodOff.jerk),
    ])
    let settle = SKAction.group([
      .rotate(toAngle: tilt, duration: settleTime),
      .moveTo(y: neck.y, duration: settleTime),
    ])
    droop.timingMode = .easeIn
    jerk.timingMode = .easeOut
    settle.timingMode = .easeInEaseOut
    head.run(.sequence([droop, jerk, settle]), withKey: Self.animationKey)

    let jerkOpenness = max(target.eyelidOpenness, NodOff.jerkOpenness)
    run(
      .sequence([
        .moveTo(y: Self.lidEdge(at: 0), duration: NodOff.droop),
        .moveTo(y: Self.lidEdge(at: jerkOpenness), duration: NodOff.jerk),
        Self.eased(.moveTo(y: Self.lidEdge(at: target.eyelidOpenness), duration: settleTime)),
      ]),
      on: lids
    )
    run(.fadeIn(withDuration: Timing.lashFade), on: lashes)
    let droopEars = CGFloat(target.earDroop) * Metrics.maxEarDroop
    ears[0].run(.rotate(toAngle: droopEars, duration: NodOff.droop), withKey: Self.animationKey)
    ears[1].run(.rotate(toAngle: -droopEars, duration: NodOff.droop), withKey: Self.animationKey)
    for (index, z) in zs.enumerated() {
      z.run(
        .sequence([
          .wait(forDuration: NodOff.droop + NodOff.jerk),
          .fadeAlpha(to: index < target.zCount ? 1 : 0, duration: settleTime),
        ]),
        withKey: Self.animationKey
      )
    }
    snoreBubble.run(
      .fadeAlpha(to: target.showsSnoreBubble ? 1 : 0, duration: NodOff.droop),
      withKey: Self.animationKey
    )
  }

  private func wakeUp(into target: MascotPose) {
    let finalBlink = blinkActions(Timing.blink, endingAt: target.eyelidOpenness)
    let holdOpen = MascotAnimation.wakeUp.duration.inSeconds - WakeUp.snapOpen - finalBlink.length
    run(
      .sequence([
        .moveTo(y: Self.lidEdge(at: target.eyelidOpenness), duration: WakeUp.snapOpen),
        .wait(forDuration: holdOpen),
        finalBlink.lid,
      ]),
      on: lids
    )
    run(
      .sequence([
        .fadeAlpha(to: Self.lashAlpha(at: target.eyelidOpenness), duration: WakeUp.snapOpen),
        .wait(forDuration: holdOpen),
        finalBlink.lash,
      ]),
      on: lashes
    )
    ears[0].run(.rotate(toAngle: 0, duration: WakeUp.earsUp), withKey: Self.animationKey)
    ears[1].run(.rotate(toAngle: 0, duration: WakeUp.earsUp), withKey: Self.animationKey)
    head.run(
      .sequence([
        Self.eased(
          .rotate(
            toAngle: Self.radians(target.headTiltDegrees),
            duration: WakeUp.headStraighten
          )
        ),
        .wait(forDuration: WakeUp.stretchDelay - WakeUp.headStraighten),
        .moveBy(x: 0, y: 2.5, duration: WakeUp.stretch),
        .moveBy(x: 0, y: -2.5, duration: WakeUp.stretch),
      ]),
      withKey: Self.animationKey
    )
    run(.fadeOut(withDuration: WakeUp.pop), on: zs)
    snoreBubble.run(
      .group([.scale(to: 1.7, duration: WakeUp.pop), .fadeOut(withDuration: WakeUp.pop)]),
      withKey: Self.animationKey
    )
    let stretch = SKAction.group([
      .scaleX(to: 0.94, duration: WakeUp.stretch),
      .scaleY(to: 1.12, duration: WakeUp.stretch),
    ])
    let relax = SKAction.group([
      .scaleX(to: 1, duration: WakeUp.stretch),
      .scaleY(to: 1, duration: WakeUp.stretch),
    ])
    stretch.timingMode = .easeOut
    relax.timingMode = .easeIn
    torso.run(
      .sequence([.wait(forDuration: WakeUp.stretchDelay), stretch, relax]),
      withKey: Self.animationKey
    )
    for (index, spot) in [
      CGPoint(x: -19, y: 52), CGPoint(x: 20, y: 60), CGPoint(x: 23, y: 40),
    ].enumerated() {
      spawnSparkle(at: spot, after: WakeUp.firstSparkle + Double(index) * WakeUp.sparkleInterval)
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

  // MARK: - One-shots

  private func blink(_ timing: BlinkTiming) -> TimeInterval {
    let blink = blinkActions(timing, endingAt: pose.eyelidOpenness)
    run(blink.lid, on: lids)
    run(blink.lash, on: lashes)
    return blink.length
  }

  // A blink from wherever the lids are, back to `openness`. The lash line shows while the eye is
  // shut.
  private func blinkActions(
    _ timing: BlinkTiming,
    endingAt openness: Double
  ) -> (lid: SKAction, lash: SKAction, length: TimeInterval) {
    let close = SKAction.moveTo(y: Self.lidEdge(at: 0), duration: timing.close)
    let open = SKAction.moveTo(y: Self.lidEdge(at: openness), duration: timing.open)
    close.timingMode = .easeIn
    open.timingMode = .easeOut
    let length = timing.close + timing.hold + timing.open
    let lash = SKAction.sequence([
      .fadeIn(withDuration: timing.close / 2),
      .wait(forDuration: length - timing.close / 2 - timing.open / 2),
      .fadeAlpha(to: Self.lashAlpha(at: openness), duration: timing.open / 2),
    ])
    return (.sequence([close, .wait(forDuration: timing.hold), open]), lash, length)
  }

  private func yawnAndNod() -> TimeInterval {
    let phases = YawnAndNod.self
    let tilt = Self.radians(pose.headTiltDegrees)
    let neck = Metrics.neck

    let leanBack = SKAction.rotate(toAngle: tilt - Self.radians(9), duration: phases.leanBack)
    let straighten = SKAction.rotate(toAngle: tilt, duration: phases.straighten)
    let nodDown = SKAction.group([
      .rotate(toAngle: tilt + Self.radians(10), duration: phases.nodDown),
      .moveTo(y: neck.y - 2.5, duration: phases.nodDown),
    ])
    let jerkUp = SKAction.group([
      .rotate(toAngle: tilt, duration: phases.jerkUp),
      .moveTo(y: neck.y, duration: phases.jerkUp),
    ])
    leanBack.timingMode = .easeOut
    nodDown.timingMode = .easeIn
    jerkUp.timingMode = .easeOut
    head.run(
      .sequence([leanBack, .wait(forDuration: phases.holdYawn), straighten, nodDown, jerkUp]),
      withKey: Self.animationKey
    )

    let mouthOpen = SKAction.group([
      .fadeIn(withDuration: phases.leanBack),
      .scale(to: 1, duration: phases.leanBack),
    ])
    let mouthClose = SKAction.group([
      .fadeOut(withDuration: phases.straighten),
      .scale(to: 0.3, duration: phases.straighten),
    ])
    openMouth.setScale(0.3)
    openMouth.run(
      .sequence([mouthOpen, .wait(forDuration: phases.holdYawn), mouthClose]),
      withKey: Self.animationKey
    )

    run(
      .sequence([
        .moveTo(y: Self.lidEdge(at: 0), duration: phases.leanBack),
        .wait(forDuration: phases.holdYawn),
        .moveTo(y: Self.lidEdge(at: pose.eyelidOpenness * 0.5), duration: phases.straighten),
        .wait(forDuration: phases.nodDown),
        .moveTo(y: Self.lidEdge(at: pose.eyelidOpenness), duration: phases.jerkUp),
      ]),
      on: lids
    )
    run(
      .sequence([
        .fadeIn(withDuration: Timing.lashFade),
        .wait(forDuration: phases.length - 2 * Timing.lashFade),
        .fadeAlpha(to: Self.lashAlpha(at: pose.eyelidOpenness), duration: Timing.lashFade),
      ]),
      on: lashes
    )
    return phases.length
  }

  // MARK: - Loops

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
