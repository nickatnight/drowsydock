# ADR-0008: Draw the cat and the Dock veil in two overlay windows, with a concrete renderer

## Status

Accepted (job 003, plan slice 8). ADR 0011 replaces `SKView` with `SceneHostView`; the paused-rendering rule below stands.

## Context

Slice 8 replaces job 002's debug outline with the cat. The cat lives at the perch, about 64 × 80 points. The asleep pose also dims the whole Dock with a veil, and slice 11's crowd effect draws over every icon. So something has to cover the Dock, not just the perch.

The idle budget is ≤ 1.0% CPU while awake and ≤ 3.0% in the looping states. SpriteKit redraws its whole view every frame while the view runs. A Dock-sized view at 30 fps would redraw about 40 times the pixels of the perch window.

The umbrella plan names a `MascotRenderer` protocol so a second mascot can replace the cat. Decision O2 (job 001) allows a protocol over an adapter only once a second implementation exists. The only candidate is plan slice 16's ambient mode, which hides the cat and keeps the "z"s and the veil. That is the same renderer with the cat hidden, not a second renderer.

## Decision

- **Two `OverlayWindow`s.** `MascotOverlay` keeps a small window at the perch with `MascotScene` (the cat), and a Dock-sized window with `DockCanvasScene` (the veil, later the crowd effect). The Dock window covers the Dock frame plus 48 points, clipped to the display, and is ordered out whenever it has nothing to draw.
- **Paused views.** After each change a scene renders two frames and sets its `SKView.isPaused`. A still cat costs no CPU.
- **`OverlayPresentation` carries the geometry**: `.shown(perch, on: geometry)` and `.fadedOut(perch, on: geometry)`. `OverlayWindow` takes frames (`show(at:)`, `fadeOut(at:)`, `hide()`), so one window class serves both windows. DockOverlayKit still knows nothing about cats or batteries.
- **No `MascotRenderer` protocol.** `CatRenderer` is a concrete class. If a second mascot is ever added, extract the protocol then, from two real implementations.
- **Poses are data.** `MascotPose(for:)` in `DrowsyDockCore` maps each state to eyelid openness, head tilt, ear droop, the static "z" count, the snore bubble and the veil opacity, with tests. `CatRenderer` only draws them.
- **The perch stays below the menu bar** (`DisplayLayout.Display.visibleFrame`), and the overlay fades while the pointer is over the perch or the icon under it, where the Dock shows that icon's label (job 002 G8).

## Alternatives considered

- **One Dock-sized window for everything.** Simpler, but every animation frame of the cat would redraw the whole Dock area.
- **A `MascotRenderer` protocol now.** It would add indirection for a second implementation that doesn't exist (O2).
- **Clamp the whole perch to `visibleFrame`.** A side Dock lies outside `visibleFrame` by definition, so that would push the cat off the Dock. Only the top edge (the menu bar) is clamped.

## Consequences

- `MascotOverlay` maps one presentation to two windows. The magnification fade and the label fade apply to both, so at 5% the veil lifts briefly while the pointer is over the Trash.
- The veil's corner radius only approximates the Dock's background shape. QA 8.5 checks it.
- Rendering can't be checked without a screen. Offscreen renders (`SKView.texture(from:)`) show the poses, and manual QA section 8 covers the rest.
