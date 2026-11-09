# ADR-0014: Keep the wake-up's beats in the core, where a test can see that they fit

## Status

Accepted (job 003, polish after rework 1). Supersedes the part of ADR 0012 that kept the wake-up's beats (`WakeUpBeats`) in `CatRenderer`.

## Context

ADR 0012 moved into `MascotTimeline` every phase that fixes an animation's length, and left in the renderer the beats that sit inside a phase without changing its length. The wake-up's stretch and sparkles are such beats. They must still end before the wake-up's final blink starts: snap open (0.08 s) plus the hold that `flexiblePhase(of: .wakeUp)` sizes (2.48 s), so 2.56 s. Otherwise a sparkle would still twinkle as the cat settles, or be cut off when the scene pauses. Nothing tied the renderer's constants to that hold, and no test could reach them.

## Decision

- `MascotTimeline.WakeUp` holds the beats: ears up, the pop, the head straightening, the stretch's delay and length, and the sparkles' start, spacing, count and phases (appear, hold, fade).
- `MascotTimelineTests` pins that every beat ends no later than the final blink's start, and that the head straightens before the stretch starts.
- `CatRenderer` reads them. Its own timing constants are now the loops' pacing (`zSpawnInterval`, `zRise`, `breath`) and two short fades inside other phases (`lashFade` in the nod-off, `staticZFade` as a loop starts).

## Alternatives considered

- **Derive the beats from the hold, as fractions.** It ties them to the hold but makes the choreography harder to read and tune, and a fraction above 1 would still need a test.
- **Leave them in the renderer with a comment.** That is what the polish review rejected: a comment can't fail.

## Consequences

- Lengthening a beat, or shortening the wake-up, so that the beats no longer fit fails a core test. A mutant with sparkles 1 s apart fails it.
- Offscreen renders before and after the move were pixel-identical: no value changed.
