# ADR-0017: Draw the looping states at 12 fps

## Status

Accepted (job 004, H16). Supersedes the 15 fps loop rate in ADR 0011. The rest of ADR 0011 stands: `SKRenderer` in a Metal layer, a display link at exactly `framesPerSecond`, 30 fps for one-shots and transitions.

## Context

At job 003's Gate 2 the user measured the real app hands off (QA 9.7): 3.16% at 15% and 3.23% at 5%, against the 3.0% budget for the looping states. The owner accepted the overage as exception E1 and asked job 004 to lower `MascotScene.loopFramesPerSecond`. ADR 0011 measured the loop's cost as about 0.15% per frame per second, so 13 fps looked enough.

13 fps changed nothing. In the CPU harness (the real `MascotScene` in a real `OverlayWindow`, on screen, a 60 s `top` run per build, built in release) on this Mac's 120 Hz built-in display, a request for 13 fps drew 15.0 frames a second and cost the same: 2.96% and 3.01% against 2.97% and 3.00% for 15 fps, alternating. A `CADisplayLink` delivers only rates that divide the display's refresh rate (120 / 8 = 15, 120 / 9 = 13.3), and it rounded 13 up to 15, above the range's maximum.

## Decision

- `MascotScene.loopFramesPerSecond` is 12, which divides 60 Hz and 120 Hz exactly.
- `SceneHostViewTests` pins the rate (`testTheLoopsDrawTwelveFramesASecond`) and requires every rate the scene asks for to divide 60 and 120 (`testEveryFrameRateDividesSixtyAndOneHundredTwentyHertz`), so a rate the display can't deliver fails a test instead of a CPU run.

## Alternatives considered

- **13 fps.** Delivered as 15 on a 120 Hz display; measured above.
- **A frame-rate range with a lower minimum** (for example 10 to 13), letting the system pick 12. The rate drawn would depend on the display, and the test could only pin the request.
- **Core Animation keyframes of pre-rendered loop frames** (ADR 0011's reserve). A second drawing path for each loop; not needed for this margin.

## Consequences

- Harness, alternating 60 s runs on battery, load average 1.2 to 2.3: 12 fps 2.51% and 2.55% (12.0 frames a second), 15 fps 2.99% and 2.88%. That is 0.14% per frame per second, as ADR 0011 measured. Applied to the user's 3.16% and 3.23%, 12 fps should land near 2.7% to 2.8%.
- The breathing and the drifting "z"s get 12 frames a second instead of 15. ADR 0011 found 10 fps visibly stepped.
- Exception E1 stays until the user's live QA 9.7 run (`scripts/qa-live.sh --only cpu`) passes.
