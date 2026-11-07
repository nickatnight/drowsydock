# ADR-0010: End `waking` on a 3 s clock, not when the wake-up animation ends

## Status

Accepted (job 003, plan slice 10). Supersedes the line in ADR 0003 that said plan slice 10 would call `finishWaking()` when the animation ends.

## Context

ADR 0003 left `waking` to be ended by an explicit event: for now a one-shot 3 s task in `BatteryMonitor`, and from slice 10 the end of the wake-up animation.

The animation doesn't always run. Without the Accessibility grant the overlay is hidden. While the Dock is auto-hidden or magnified the cat is hidden or faded, and `MascotScene` switches at once instead of animating. Quiet hours (slice 13) play no animations at all. A hidden `SKView` doesn't advance its actions either. If the animation ended `waking`, the menu could read `Waking` indefinitely whenever nobody can see the cat.

## Decision

- `BatteryMonitor` keeps ending `waking` after `DrowsinessTracker.wakingDuration` (3 s), whatever the overlay does. The constant moved into the core so the tests can see it.
- `MascotAnimation.wakeUp` lasts 2.8 s. A test pins `wakeUp.duration ≤ wakingDuration` (and ≤ 3 s, the spec's limit).
- When `waking` ends, the mood changes from `.waking` to awake. `AnimationDirector` treats that as a cut, because the wake-up already ends in the awake pose. If the clock fires first, the change waits for the animation and then cuts.

## Alternatives considered

- **End `waking` from the animation's completion, with a timeout as a fallback.** That gives two paths to the same event, and the timeout is the one that always works.
- **Drop `waking` from the tracker and treat it as purely visual.** The menu shows `Waking`, and the crowd-effect rule re-arms on AC, so the phase is domain state, not just an animation.

## Consequences

- The tracker's phase never depends on the renderer.
- The wake-up may end up to 0.2 s before the menu changes to `Awake`. The pose doesn't change at that moment, so nothing visible happens.
