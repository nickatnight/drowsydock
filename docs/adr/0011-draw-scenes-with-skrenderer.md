# ADR-0011: Draw the scenes with `SKRenderer` in a Metal layer, and loop at 15 fps

## Status

Accepted (job 003, final verification). Supersedes the `SKView` and 30 fps loop parts of ADR 0009. The rest of ADR 0009 stands: paused rendering between actions, one-shots scheduled by `AmbientSchedule`, and rasterized static parts. ADR 0015 moves the pause into the host: it pauses itself after a frame its scene doesn't need. ADR 0017 lowers the loop rate to 12 fps.

## Context

ADR 0009's measurements ran while the display was asleep. With the display awake they changed:

- **Offscreen** (`SKRenderer` drives the real `MascotScene`, and a windowless `SKView` presents it so the pause flag works): the asleep loop rose from 2.0% to 3.1% to 3.2% at 30 fps. Slice 9's code gave the same 3.15% to 3.25%, so the code hadn't regressed. The profile showed the windowless `SKView`'s own `CVDisplayLink` thread (`_cvDisplayLinkCallback` in SpriteKit, main-queue pushes, vsync timing locks). It runs only while the view is unpaused and the display is awake.
- **On screen** (the real `MascotScene` in a real `OverlayWindow`, cat only): with `SKView`, the asleep loop cost 4.27% at 20 fps, 3.44% at 15, 2.96% at 12 and 2.63% at 10. That is about 1.0% fixed plus 0.165% per frame per second. The fixed part is `SKView`'s display link, which fires at the display's refresh rate (up to 120 Hz) whatever `preferredFramesPerSecond` says.
- **With `SceneHostView`**, the replacement below, on screen: 4.47% at 30 fps, 3.10% at 20, 2.23% at 15. The fixed part is gone, and the rest scales with frame rate. The profile shows SpriteKit's per-frame render submission (`flushRenderOps`, `begin_render_pass`) and node traversal, about 0.9 ms of main-thread time per frame.

The budget for the looping states is 3.0%.

## Decision

- `SceneHostView`, an `NSView` backed by a `CAMetalLayer`, draws a scene with `SKRenderer`. A `CADisplayLink` from `NSView.displayLink(target:selector:)` asks for exactly `framesPerSecond` (`preferredFrameRateRange`). While `isPaused`, the link is paused and nothing runs. Both scenes use it in place of `SKView`, and set `host.isPaused` and `host.framesPerSecond`.
- Loops run at 15 fps. One-shots and transitions run at 30 fps, because a 0.25 s blink needs the frames.
- If the Mac has no Metal device, the overlay window gets an empty view and logs an error. Every Mac that runs macOS 14 has one.

## Alternatives considered

- **Keep `SKView` and loop at 10 fps.** 2.63% on screen leaves 0.37% of margin, and the breathing and the drifting "z"s visibly step.
- **Play loops as Core Animation keyframes of pre-rendered frames.** The render server would run them at almost no cost to the app. It needs a frame-baking step and a second drawing path for each loop. Kept in reserve if the budget ever tightens.
- **Turn off culling (`shouldCullNonVisibleNodes`).** It measured the same (3.10% against 3.11% at 20 fps), so it isn't set.
- **Rasterize the snore bubble too.** It measured 0.1% worse, because a rasterized node that scales is redrawn.

## Consequences

- Measured on screen with `SceneHostView`, one 60 s run per state with `top` once a second (57 to 61 samples): awake 0.16%, drowsy 0.27%, yawning 0.19%, nodding off 1.94%, asleep 1.94%. Between runs the loop varied from 1.94% to 2.34%. A `sample` of the awake cat between blinks shows no drawing; the main thread waits in `mach_msg`.
- These runs hosted the cat window alone. The Dock window is paused while the veil is static, so it adds nothing. The menu-bar app's idle cost was 0.05% in job 002. QA 9.6 and 9.7 measure the real app with the grant.
- An `SKScene.view` is now always `nil`. Scene code that needs its view goes through `host`.
