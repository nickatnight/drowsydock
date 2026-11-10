# ADR-0016: Test the app target, with offscreen snapshots of the real scenes

## Status

Accepted (job 004, slice 1). Supersedes the consequence of ADR 0002 that the executable's code has no unit tests, and the alternative that ADR 0012 rejected, a test target that imports the executable. The rest of both stands: the three targets, the pure core, and the coverage gate over the core and the kit's pure files.

## Context

`docs/manual-qa.md` had 107 rows, and every merge ended with the user working through them by hand. Most check things a program can see: a pose, the frame at a time in a transition, a window's properties, which line the menu shows. ADR 0002 left the executable untested because its code only runs inside AppKit, SpriteKit and IOKit.

A probe on macOS 27 with Swift 6.0.3 showed that:

- a test target can `@testable import DrowsyDock`, the executable target, with no change to its `@main` app;
- `SKRenderer` draws the real `MascotScene` into a Metal texture with no window, and three renders of the same scene gave identical bytes;
- a `CADisplayLink` from a view in a window placed off every display never fires in the test process, so nothing draws behind a test's back.

## Decision

- `Tests/DrowsyDockTests` imports the executable with `@testable import DrowsyDock`. No library target is split out.
- Snapshot tests draw the real scenes with `SKRenderer` into a Metal texture at 2 pixels per point, on the system's default Metal device, at a scene time the test sets in 1/60 s steps (`OffscreenRenderer`). They compare the result with PNGs under `Tests/DrowsyDockTests/Snapshots/`, with a per-channel tolerance and a maximum count of differing pixels that each test file states.
- The comparer is in-house (Core Graphics and ImageIO). `RECORD_SNAPSHOTS=1 swift test` rewrites the references and fails, so a recording never passes as a check. A mismatch writes the actual and diff images under `.build/snapshot-failures/`.
- The references were recorded on Apple silicon. On another architecture the snapshot tests skip with that message.
- Executable files stay exempt from the coverage gate, as ADR 0002 decided. They are still named in `docs/manual-qa.md`, which now maps each row to the test or live scenario that covers it.

## Alternatives considered

- **Move the scenes and the overlay into a library target.** The spec's fallback if `@testable import` of the executable failed. It didn't fail, so the layout stays as the user decided on 2026-11-09.
- **A third-party snapshot library.** CONSTRAINTS bans dependencies, and the comparer is about a hundred lines.
- **Render through `SceneHostView` on screen.** It would put windows on the user's display during every `swift test`, and the frame times would follow the display link, not the test.

## Consequences

- A change to a pose, a transition's timing, the veil's shape or the perch fails a snapshot. Recording new references is a deliberate step whose diff a reviewer sees as images.
- The snapshots pin pixels, so a deliberate visual change re-records them. Each test names the QA row it replaces.
- Timing in the snapshots comes from the scene time the test sets and from an injected clock for the pauses between gestures, never from sleeping.
