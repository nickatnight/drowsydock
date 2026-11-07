# ADR-0004: Track the Dock with a phase model, events and a pointer-gated frame check

## Status

Accepted (job 002, plan slices 6 and 7; reviewed in rounds 1 to 3)

## Context

The overlay has to follow the Dock through moves, resizes, display changes and auto-hide, and has to fade out while the Dock is magnified. The spec also sets an idle budget: no timers while the app is idle.

The Dock gives little to listen to. A harness run on macOS 27 showed that its icon list accepts only the `AXCreated` and `AXUIElementDestroyed` notifications, not `AXMoved` or `AXResized`. Nothing at all is posted when the Dock magnifies. `NSWorkspace` posts no launch notification for the Dock either, because the Dock is an `LSUIElement` app.

The decisions (hide without the grant, hide an off-screen Dock, fade while magnified, when frame checks run) have to be testable without the grant or a screen.

## Decision

`DockTrackerState` is a value type in `DockOverlayKit` that imports only CoreGraphics. Its `Phase` enum:

```
untrusted                            // no Accessibility grant
unavailable                          // granted, but no usable read yet
offScreen                            // auto-hidden
resting(geometry)                    // shown; pointer away
hovering(resting, isMagnified)       // pointer within 128 pt; frame checks run
settling(resting, isMagnified)       // pointer just left; waiting for one settled read
```

- `presentation` maps a phase to `.hidden`, `.shown(perch)` or `.fadedOut(perch)`. A magnified Dock keeps the resting perch and fades the overlay out.
- `runsFrameChecks` is true only in `hovering`, and `awaitsSettledRead` only in `settling`.
- `DockGeometry.isMagnified` counts only growth of more than 1 point, on the same display and edge. A change of orientation or display is a new resting geometry.

`DockTracker` (the adapter) feeds the state these events and applies its outputs:

- Reads on: AX notifications from the Dock list, `NSApplication.didChangeScreenParametersNotification`, `com.apple.dock.prefchanged`, Space changes, and the Dock reappearing in `NSWorkspace.runningApplications` (KVO). Each event reads at once, unless frame checks run or a settled read is pending, and again 0.5 s later.
- Pointer position from a global mouse-moved monitor, which is event-driven.
- A 1 Hz `Timer` that exists only while `runsFrameChecks` is true.
- A bounded retry (0.25, 0.5, 1, 2 and 4 s) after the Dock relaunches or its list is destroyed. The list observer is re-installed when the Dock's pid changes.

## Alternatives considered

- **Poll the Dock's frame on a timer.** This is simple and catches everything, but it breaks the idle budget.
- **Track magnification frame by frame.** The spec rejected this in Gate 1 (the magnification decision) for CPU reasons. The overlay fades out instead.
- **Booleans in the adapter** (`isHovering`, `isMagnified`, `isSettling`). Rejected: they would have to stay in sync by hand and couldn't be unit-tested without AppKit.

## Consequences

- No timer runs while the pointer is away from the Dock. Manual QA 7.6 (`sample`) and 7.9 (idle CPU) check this on a real Mac.
- A Dock enlarged by dragging its separator can't be told apart from magnification. The overlay stays faded until the pointer leaves (QA 7.2).
- With auto-hide on, the overlay stays hidden while the Dock is off screen. It may appear while the Dock is revealed, if an AX event arrives then.
- One decision still sits in the adapter: whether a Dock event reads at once (`!runsFrameChecks && !awaitsSettledRead`). Moving it into `DockTrackerState` as a tested property is follow-up G1 in the job's ship.md. Until then the `DockTracker` doc comment overstates "makes every decision". (Resolved in job 003: `DockTrackerState.readsAtOnceOnDockChange`.)
