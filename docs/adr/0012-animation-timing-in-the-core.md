# ADR-0012: Keep the phase lengths that fix each animation's length in the core

## Status

Accepted (job 003, round-1 review). ADR 0014 moves the wake-up's beats into the core as well.

## Context

`AnimationDirector` decides when a transition ends. It schedules the completion at `MascotAnimation.duration`, which lives in `DrowsyDockCore`. `CatRenderer` builds the SpriteKit timelines that must fill that time.

In the polish pass, each transition's last phase was derived from the core duration: duration minus the renderer's own fixed phases. That removed hand-typed totals, but left an invariant that crossed modules and that no test could reach. If someone shortened a core duration below the renderer's fixed phases, the core tests would stay green, and SpriteKit would get a negative duration. The renderer lives in the executable target, which the tests don't import and the coverage gate exempts.

## Decision

- `MascotTimeline`, in `DrowsyDockCore`, holds the phase lengths that fix each transition's total:
  - the blink and slow blink
  - the yawn-and-nod's five phases
  - the nod-off's droop and jerk
  - the wake-up's snap open
- `MascotTimeline.flexiblePhase(of:)` returns the one phase per transition that takes whatever `MascotAnimation.duration` leaves:
  - the whole crossfade
  - the settle before the yawn and nod
  - the settle after the nod-off's jerk
  - the hold before the wake-up's final blink
- `MascotTimelineTests` pins that every flexible phase is above zero and that each transition's phases add up to its duration.
- `CatRenderer` reads these values. It keeps its own constants only for beats that sit inside a phase without changing its length: the wake-up's stretch and sparkles, the ear and bubble fades, the loops' pacing.

## Alternatives considered

- **An `assert` at each derived phase in the renderer.** No test runs the renderer, so the assert would fire only in a debug build of the app, on screen.
- **A test target that imports the executable.** SwiftPM allows it on macOS, but it would pull AppKit and SpriteKit into the unit tests, and the renderer is coverage-exempt by design (ADR 0002).
- **Keep every renderer number in the core.** Beats inside a phase don't change any total, so moving them would add API without protecting an invariant.

## Consequences

- Changing a transition's duration, or a phase that fixes it, fails a core test if the timeline no longer fits.
- The renderer's timing has two homes: `MascotTimeline` for anything that sets a length, and private constants in `CatRenderer+Animations.swift` (`Timing`, `WakeUpBeats`) for beats inside a phase. A new phase that changes a total belongs in `MascotTimeline`.
- Offscreen renders before and after the move were pixel-identical, because no value changed.
