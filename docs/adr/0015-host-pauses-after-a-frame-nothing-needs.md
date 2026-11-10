# ADR-0015: `SceneHostView` pauses itself after a frame its scene doesn't need

## Status

Accepted (job 003, polish after rework 1). Supersedes the part of ADR 0011 in which both scenes set `host.isPaused`. The rest of ADR 0011 stands: `SKRenderer` in a Metal layer, a display link at exactly `framesPerSecond`, 15 fps loops and 30 fps one-shots.

## Context

`MascotScene` and `DockCanvasScene` paused their `SceneHostView` from `update(_:)`. `SKRenderer` calls `update(_:)` from inside `SceneHostView.drawFrame`, before the render. So each scene stopped the display link while the host was still drawing, and relied on the host finishing that frame anyway. The rule that one frame shows each change (ADR 0008, polish pass) held only because of that order. The polish review asked for the host to ask the scene after the frame instead.

## Decision

- `SceneHostView` takes a `HostedScene`: an `SKScene` that answers `needsAnotherFrame`.
- After `drawFrame` commits a frame, the host pauses itself unless the scene `needsAnotherFrame`.
- `MascotScene` needs another frame while a gesture plays, a loop runs or a transition animates. `DockCanvasScene` needs one while the crowd wave plays.
- Scenes still set `host.isPaused = false` to draw a change, and `host.framesPerSecond`. Neither overrides `update(_:)`.

## Alternatives considered

- **Keep the pause in `update(_:)` with a comment.** It works, but the frame order it depends on lives in another type, and no test can see it.
- **Pause from SpriteKit completion blocks.** Completions arrive on the main queue after the frame that ended the action, so when the host stops would depend on main-queue timing that it doesn't control. Not tried.

## Consequences

- The same frames are drawn as before. On screen with the real `MascotOverlay`, an awake cat drew 11 frames in 25 s (11 before), the crossfade and crowd wave 50 and 78 (47 and 76 before), and the asleep loop alone 105 in 7 s at 15 fps (104 before), with the canvas paused. All 15 offscreen renders were identical, and the awake cat's CPU in the harness was 0.20% over 59 samples.
- A new scene drawn by `SceneHostView` must say when it moves. A scene that answers `false` while an action runs freezes after one frame; one that answers `true` forever never pauses.
