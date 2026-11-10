# ADR-0003: Model the mascot's state as a tracker with four phases

## Status

Accepted (Gate 1 rules, 2026-11-06; the model was built in job 001 and reviewed in rounds 1 and 2). ADR 0010 supersedes the plan for ending `waking` from the animation: it stays on a 3 s clock.

## Context

The spec sets these rules:

- While discharging, the state only gets sleepier, so 1% jitter must never flip it back up.
- Plugging in plays `waking` once and then stays `awake` on AC power, at any percentage.
- A threshold change in Settings re-derives the state.
- A Mac with no battery shows nothing.
- The Debug simulator must drive the same logic as the real battery.

Separate flags such as `isCharging` and `wasDischarging` would have to stay in sync by hand.

## Decision

`DrowsinessTracker` is a value type in `DrowsyDockCore`. Its `Phase` enum has four cases:

```
noBattery
discharging(DrowsinessState)   // the sleepiest state reached this cycle
waking                         // AC was just connected
onExternalPower                // awake for as long as AC is connected
```

- `update(_:)` is one exhaustive `switch` over (phase, on AC?):
  - On battery while discharging, the phase keeps the sleepier of the current state and the derived one.
  - On AC while discharging, it enters `waking`. That applies to `.charging` and `.pluggedIn` alike.
  - In any other phase, it derives the state afresh.
- Only `finishWaking()` leaves `waking`. For now the app calls it after a one-shot 3 s task, and plan slice 10 will call it when the animation ends.
- `setThresholds(_:)` re-derives only a `discharging` phase.
- Launching on AC starts in `onExternalPower`, without `waking`.
- `BatterySession` routes real or simulated readings into the tracker. A simulator switch is a jump, so it rebuilds the tracker: 80% after 5% shows `awake`. A switch onto AC goes through `update(_:)`, so it still wakes the mascot.

## Alternatives considered

- **A hysteresis band** (re-derive upward once the reading is a few points past the threshold). The spec chose strict monotonicity instead. An exhaustive 101 × 101 test pins this.
- **`waking` as a `DrowsinessState` case.** That would break the `awake` to `asleep` ordering that `Comparable` and `max` rely on.
- **A clock inside the tracker to end `waking`.** That would put time into the core. An explicit event keeps the tracker deterministic.

## Consequences

- The tracker stores `phase` and `reading` separately, with the invariant "reading is `nil` exactly when phase is `.noBattery`". This leaves one unreachable branch in `StatusLine`. Folding the reading into the phase is deferred to plan slice 15 (round-1 N2).
- Returning to Real from the simulator re-derives the state. It doesn't restore the real battery's monotonic history. This happens only through the Debug menu. Keeping a separate real tracker is deferred to slice 15, which adds wake resync (round-1 O1).
- Later slices react to phase changes: animations (slice 10), the crowd effect (slice 11) and wake resync (slice 15).
