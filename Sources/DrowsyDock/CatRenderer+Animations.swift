import DrowsyDockCore
import SpriteKit

extension CatRenderer {
  private static let animationKey = "animation"
  private static let followUpKey = "followUp"
  private static let loopEaseOutKey = "loopEaseOut"
  static let floatingZName = "floatingZ"
  private static let sparkleName = "sparkle"

  private enum Timing {
    static let zSpawnInterval = 1.6
    static let zRise = 2.6
    static let breath = (inhale: 1.5, exhale: 1.7)
    static let lashFade = 0.1
    static let staticZFade = 0.4
  }

  private static let nodOffJerkOpenness = 0.35

  /// Plays `gesture` once, then calls `completion` on the main actor.
  func play(_ gesture: AmbientGesture, completion: @escaping @MainActor () -> Void) {
    let duration: TimeInterval
    switch gesture {
    case .blink:
      duration = blink(MascotTimeline.blink)
    case .slowBlink:
      duration = blink(MascotTimeline.slowBlink)
    case .yawnAndNod:
      duration = yawnAndNod()
    }
    node.run(.completion(after: duration, completion), withKey: Self.animationKey)
  }

  func loop(_ loop: AmbientLoop) {
    isLooping = true
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
    let duration = animation.duration / .seconds(1)
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
    node.run(.completion(after: duration, completion), withKey: Self.animationKey)
  }

  /// Stops every animation and puts the cat in its pose. When `next` is about to play and a loop
  /// was running, the loop's parts don't jump: the "z"s in flight fade, and the body, bubble and
  /// head ease back over `MascotTimeline.loopEaseOut`, except a part that `next` moves at once.
  func stopAnimations(before next: MascotAnimation?) {
    let loopState = (torso: torso.yScale, bubble: snoreBubble.yScale, headY: head.position.y)
    let easesLoopOut = next != nil && isLooping
    animationGeneration += 1
    var parts: [SKNode] = [node, torso, head, snoreBubble, openMouth]
    parts += ears
    parts += lids
    parts += lashes
    parts += zs
    for part in parts {
      part.removeAction(forKey: Self.animationKey)
      part.removeAction(forKey: Self.followUpKey)
      part.removeAction(forKey: Self.loopEaseOutKey)
    }
    for child in node.children
    where child.name == Self.floatingZName || child.name == Self.sparkleName {
      if easesLoopOut, child.name == Self.floatingZName {
        child.removeAllActions()
        child.run(
          .sequence([.fadeOut(withDuration: MascotTimeline.loopEaseOut), .removeFromParent()]))
      } else {
        child.removeFromParent()
      }
    }
    // The wake-up fades the "z"s and the bubble out from what is on screen.
    let keepsZsAndBubble = next == .wakeUp
    apply(pose, keepingZsAndBubble: keepsZsAndBubble)
    if isLooping {
      isLooping = false
      if !keepsZsAndBubble {
        for z in zs {
          z.alpha = 0
        }
      }
    }
    if easesLoopOut, let next {
      easeBack(from: loopState, before: next)
    }
  }

  // Puts the loop's parts back where the loop left them, then eases them into the pose. The
  // wake-up pops the bubble and the nod-off droops the head from the first frame, so those parts
  // are theirs. Nothing else moves the body, the bubble's size or the head's height before the
  // ease-out ends (MascotTimelineTests).
  private func easeBack(
    from loop: (torso: CGFloat, bubble: CGFloat, headY: CGFloat),
    before next: MascotAnimation
  ) {
    torso.yScale = loop.torso
    snoreBubble.setScale(loop.bubble)
    head.position.y = loop.headY
    let duration = MascotTimeline.loopEaseOut
    torso.run(Self.eased(.scaleY(to: 1, duration: duration)), withKey: Self.loopEaseOutKey)
    if next != .wakeUp {
      snoreBubble.run(Self.eased(.scale(to: 1, duration: duration)), withKey: Self.loopEaseOutKey)
    }
    if next != .nodOff {
      head.run(
        Self.eased(.moveTo(y: Metrics.neck.y, duration: duration)),
        withKey: Self.loopEaseOutKey
      )
    }
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
    rotateEars(toDroop: target.earDroop, over: duration, timingMode: .easeInEaseOut)
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
    let settle = MascotTimeline.flexiblePhase(of: .yawn)
    blend(to: target, over: settle)
    yawnAndNod(after: settle)
  }

  private func nodOff(into target: MascotPose) {
    let phases = MascotTimeline.NodOff.self
    let settleTime = MascotTimeline.flexiblePhase(of: .nodOff)
    let tilt = Self.radians(target.headTiltDegrees)
    let neck = Metrics.neck
    let droop = SKAction.group([
      .rotate(toAngle: tilt + Self.radians(14), duration: phases.droop),
      .moveTo(y: neck.y - 2, duration: phases.droop),
    ])
    let jerk = SKAction.group([
      .rotate(toAngle: tilt - Self.radians(3), duration: phases.jerk),
      .moveTo(y: neck.y + 0.6, duration: phases.jerk),
    ])
    let settle = SKAction.group([
      .rotate(toAngle: tilt, duration: settleTime),
      .moveTo(y: neck.y, duration: settleTime),
    ])
    droop.timingMode = .easeIn
    jerk.timingMode = .easeOut
    settle.timingMode = .easeInEaseOut
    head.run(.sequence([droop, jerk, settle]), withKey: Self.animationKey)

    let jerkOpenness = max(target.eyelidOpenness, Self.nodOffJerkOpenness)
    run(
      .sequence([
        .moveTo(y: Self.lidEdge(at: 0), duration: phases.droop),
        .moveTo(y: Self.lidEdge(at: jerkOpenness), duration: phases.jerk),
        Self.eased(.moveTo(y: Self.lidEdge(at: target.eyelidOpenness), duration: settleTime)),
      ]),
      on: lids
    )
    run(.fadeIn(withDuration: Timing.lashFade), on: lashes)
    rotateEars(toDroop: target.earDroop, over: phases.droop)
    for (index, z) in zs.enumerated() {
      z.run(
        .sequence([
          .wait(forDuration: phases.droop + phases.jerk),
          .fadeAlpha(to: index < target.zCount ? 1 : 0, duration: settleTime),
        ]),
        withKey: Self.animationKey
      )
    }
    snoreBubble.run(
      .fadeAlpha(to: target.showsSnoreBubble ? 1 : 0, duration: phases.droop),
      withKey: Self.animationKey
    )
  }

  private func wakeUp(into target: MascotPose) {
    let finalBlink = blinkActions(MascotTimeline.blink, endingAt: target.eyelidOpenness)
    let holdOpen = MascotTimeline.flexiblePhase(of: .wakeUp)
    let beats = MascotTimeline.WakeUp.self
    let snapOpen = beats.snapOpen
    run(
      .sequence([
        .moveTo(y: Self.lidEdge(at: target.eyelidOpenness), duration: snapOpen),
        .wait(forDuration: holdOpen),
        finalBlink.lid,
      ]),
      on: lids
    )
    run(
      .sequence([
        .fadeAlpha(to: Self.lashAlpha(at: target.eyelidOpenness), duration: snapOpen),
        .wait(forDuration: holdOpen),
        finalBlink.lash,
      ]),
      on: lashes
    )
    rotateEars(toDroop: 0, over: beats.earsUp)
    head.run(
      .sequence([
        Self.eased(
          .rotate(
            toAngle: Self.radians(target.headTiltDegrees),
            duration: beats.headStraighten
          )
        ),
        .wait(forDuration: beats.stretchDelay - beats.headStraighten),
        .moveBy(x: 0, y: 2.5, duration: beats.stretch),
        .moveBy(x: 0, y: -2.5, duration: beats.stretch),
      ]),
      withKey: Self.animationKey
    )
    run(.fadeOut(withDuration: beats.pop), on: zs)
    snoreBubble.run(
      .group([.scale(to: 1.7, duration: beats.pop), .fadeOut(withDuration: beats.pop)]),
      withKey: Self.animationKey
    )
    let stretch = SKAction.group([
      .scaleX(to: 0.94, duration: beats.stretch),
      .scaleY(to: 1.12, duration: beats.stretch),
    ])
    let relax = SKAction.group([
      .scaleX(to: 1, duration: beats.stretch),
      .scaleY(to: 1, duration: beats.stretch),
    ])
    stretch.timingMode = .easeOut
    relax.timingMode = .easeIn
    torso.run(
      .sequence([.wait(forDuration: beats.stretchDelay), stretch, relax]),
      withKey: Self.animationKey
    )
    let spots = [CGPoint(x: -19, y: 52), CGPoint(x: 20, y: 60), CGPoint(x: 23, y: 40)]
    // MascotTimelineTests times `sparkleCount` sparkles; each needs a spot here.
    assert(spots.count == beats.sparkleCount, "one spot per sparkle that MascotTimeline times")
    for (index, spot) in spots.enumerated() {
      spawnSparkle(at: spot, after: beats.firstSparkle + Double(index) * beats.sparkleInterval)
    }
  }

  private func spawnSparkle(at spot: CGPoint, after delay: TimeInterval) {
    let sparkle = Self.sparkle()
    sparkle.name = Self.sparkleName
    sparkle.position = spot
    sparkle.setScale(0)
    node.addChild(sparkle)
    let phases = MascotTimeline.WakeUp.Sparkle.self
    let appear = SKAction.group([
      .scale(to: 1, duration: phases.appear),
      .rotate(byAngle: .pi / 2, duration: phases.appear),
    ])
    appear.timingMode = .easeOut
    sparkle.run(
      .sequence([
        .wait(forDuration: delay),
        appear,
        .wait(forDuration: phases.hold),
        .group([.fadeOut(withDuration: phases.fade), .scale(to: 0.6, duration: phases.fade)]),
        .removeFromParent(),
      ])
    )
  }

  private func rotateEars(
    toDroop droop: Double,
    over duration: TimeInterval,
    timingMode: SKActionTimingMode = .linear
  ) {
    let angle = CGFloat(droop) * Metrics.maxEarDroop
    for (ear, side) in zip(ears, [1, -1] as [CGFloat]) {
      let rotate = SKAction.rotate(toAngle: angle * side, duration: duration)
      rotate.timingMode = timingMode
      ear.run(rotate, withKey: Self.animationKey)
    }
  }

  private func run(_ action: SKAction, on parts: [SKNode], key: String = animationKey) {
    for part in parts {
      part.run(action, withKey: key)
    }
  }

  private static func eased(_ action: SKAction) -> SKAction {
    action.timingMode = .easeInEaseOut
    return action
  }

  // MARK: - One-shots

  private func blink(_ timing: MascotTimeline.Blink) -> TimeInterval {
    let blink = blinkActions(timing, endingAt: pose.eyelidOpenness)
    run(blink.lid, on: lids)
    run(blink.lash, on: lashes)
    return blink.length
  }

  private func blinkActions(
    _ timing: MascotTimeline.Blink,
    endingAt openness: Double
  ) -> (lid: SKAction, lash: SKAction, length: TimeInterval) {
    let close = SKAction.moveTo(y: Self.lidEdge(at: 0), duration: timing.close)
    let open = SKAction.moveTo(y: Self.lidEdge(at: openness), duration: timing.open)
    close.timingMode = .easeIn
    open.timingMode = .easeOut
    let length = timing.length
    let lash = SKAction.sequence([
      .fadeIn(withDuration: timing.close / 2),
      .wait(forDuration: length - timing.close / 2 - timing.open / 2),
      .fadeAlpha(to: Self.lashAlpha(at: openness), duration: timing.open / 2),
    ])
    return (.sequence([close, .wait(forDuration: timing.hold), open]), lash, length)
  }

  @discardableResult
  private func yawnAndNod(after delay: TimeInterval = 0) -> TimeInterval {
    let lead = SKAction.wait(forDuration: delay)
    let phases = MascotTimeline.YawnAndNod.self
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
      .sequence([lead, leanBack, .wait(forDuration: phases.holdYawn), straighten, nodDown, jerkUp]),
      withKey: Self.followUpKey
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
      .sequence([lead, mouthOpen, .wait(forDuration: phases.holdYawn), mouthClose]),
      withKey: Self.followUpKey
    )

    run(
      .sequence([
        lead,
        .moveTo(y: Self.lidEdge(at: 0), duration: phases.leanBack),
        .wait(forDuration: phases.holdYawn),
        .moveTo(y: Self.lidEdge(at: pose.eyelidOpenness * 0.5), duration: phases.straighten),
        .wait(forDuration: phases.nodDown),
        .moveTo(y: Self.lidEdge(at: pose.eyelidOpenness), duration: phases.jerkUp),
      ]),
      on: lids,
      key: Self.followUpKey
    )
    run(
      .sequence([
        lead,
        .fadeIn(withDuration: Timing.lashFade),
        .wait(forDuration: phases.length - 2 * Timing.lashFade),
        .fadeAlpha(to: Self.lashAlpha(at: pose.eyelidOpenness), duration: Timing.lashFade),
      ]),
      on: lashes,
      key: Self.followUpKey
    )
    return phases.length
  }

  // MARK: - Loops

  private func floatZs() {
    fadeOutStaticZs()
    let spawn = spawnFloatingZ(size: 6)
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
    fadeOutStaticZs()
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

    let spawn = spawnFloatingZ(size: 7.5)
    node.run(
      .repeatForever(
        .sequence([.wait(forDuration: breath.inhale), spawn, .wait(forDuration: breath.exhale)])
      ),
      withKey: Self.animationKey
    )
  }

  private func fadeOutStaticZs() {
    run(.fadeOut(withDuration: Timing.staticZFade), on: zs)
  }

  // An action that adds one floating "z". SpriteKit may run it after the loop stopped, so it
  // checks that the loop that scheduled it is still the current one.
  private func spawnFloatingZ(size: CGFloat) -> SKAction {
    let generation = animationGeneration
    return .onMainActor { [weak self] in
      guard let self, self.animationGeneration == generation else { return }
      addFloatingZ(size: size)
    }
  }

  private func addFloatingZ(size: CGFloat) {
    let z = Self.z(size: size)
    z.setScale(0.6)
    // scale(to:) on the z would overwrite a negative xScale, so the mirroring sits on a parent.
    let mirror = SKNode()
    mirror.name = Self.floatingZName
    mirror.xScale = node.xScale
    mirror.position = CGPoint(x: 14, y: 48)
    mirror.alpha = 0
    mirror.addChild(z)
    node.addChild(mirror)
    let rise = Timing.zRise
    z.run(.scale(to: 1.15, duration: rise))
    mirror.run(
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
