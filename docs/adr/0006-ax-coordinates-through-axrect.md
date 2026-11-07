# ADR-0006: Keep Accessibility coordinates in their own type, `AXRect`

## Status

Accepted (job 002, plan slice 5)

## Context

The Accessibility API reports frames with the origin at the top-left of the primary display and y growing downward. AppKit windows use the bottom-left of the primary display, with y growing upward. Both are `CGRect`, so the compiler can't stop one from being passed where the other is expected. Mixing them up puts the overlay on the wrong edge, and on a multi-display setup it lands on the wrong display.

## Decision

- `AXRect` wraps a `CGRect` that the Accessibility API reported. `DockReader` returns only `AXRect` values.
- `DisplayLayout(primary:others:)` holds the AppKit display frames, with the primary display first, as `NSScreen.screens` lists them. `appKitRect(_:)` is the only way from `AXRect` to `CGRect`: `y = primary.maxY - ax.maxY`.
- `DockGeometry.init(listFrame:iconFrames:layout:)` takes `AXRect` values, and stores and returns AppKit frames only.
- The Dock's display is the one nearest the centre of its frame, so an auto-hidden, off-screen Dock still maps to a display. `isHidden` means the frame isn't inside that display, allowing 1 point for rounding.

## Alternatives considered

- **Convert inside `DockReader`.** That would hide the conversion inside an adapter that isn't covered by tests, and the conversion couldn't be tested without the grant.
- **Use `NSScreen.visibleFrame` to detect auto-hide.** Rejected: a visible Dock sits outside `visibleFrame` by definition, so this can't tell visible from hidden.

## Consequences

- Unit tests pin the conversion on a single display, a display stacked above and a negative-origin display. The overlay harness confirmed it against the window server: converting the bounds of a real window gave its AppKit frame.
- The perch is clamped to the display's full frame, so on a tall side Dock it can sit under the menu bar. Clamping to `visibleFrame` needs `DisplayLayout` to carry it, and is follow-up G8 for the mascot slice.
- A hidden Dock on a display stacked above another may land on the lower display and count as visible. QA 5.4a checks this on hardware.
