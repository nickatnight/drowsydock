# ADR-0013: Fit the veil and the perch to the Dock's drawn background, not to its Accessibility list frame

## Status

Accepted (job 003, rework 1). Corrects the veil frame in ADR 0008, whose consequence said the corner radius only approximated the Dock's shape.

## Context

At Gate 2 the user reported that the veil (the "shadow" Dock at 5%) didn't line up with the real Dock. Their screenshot, at 2×, was taken on macOS 27.0.1 with a bottom Dock (tile size 59, magnification on).

- **The veil was 5 points too high.** Inside the Dock, the veil's top edge is a step in brightness at pixel row 140, where the window behind the Dock darkens from 142 to 111. The Dock's own outline starts at row 150. The veil's bottom edge is at row 298 and the outline's at about 307. That is a shift of about 5 points, with the same height.
- **Horizontally it was right.** The list frame's ends (x 373 and 1139) land on the outline's ends to within a pixel, using the Finder icon's centre to map points to pixels.
- **The list frame is the cause.** A read-only Accessibility read on the same Mac returns the list at (373, y, 766, 79) and every item 5 points lower at (x, y + 5, 63, 79). The user's app had read the list at AX y 893: its canvas window was the list frame plus 48 points. Its items would have been at 898 to 977, which in the screenshot is rows 150 to 308, the outline. The same 5-point offset holds while the Dock is hidden in a full-screen Space (list at y 982, items at 987).
- **Ruled out:**
  - The AX-to-AppKit conversion: the veil was the right size, and the right width at the right x. The only error was the 5-point offset between list and items.
  - The canvas window: its frame (325, 0, 862, 137) is the list frame plus 48 points, clipped to the display, as `MascotOverlay` intends.
  - Backing scale: the veil was exactly 158 pixels tall, twice the list's 79 points.
  - The corner radius: 0.28 of the thickness is 22.1 points. Tracing the outline's right end row by row, its inset from the straight edge fits a circle of 44 pixels (22 points) to within 2 pixels on every row from 2 to 35 pixels in from the top and bottom edges.

No Accessibility element reports the drawn background itself. The Dock application's only child is the list, and the list has no window element.

## Decision

- `DockGeometry.backgroundFrame` is the list frame slid across the Dock's thickness, toward the screen edge, until it holds every item: down for a bottom Dock, left for a left Dock, right for a right Dock. Where the list already holds its items, it is the list frame unchanged.
- `DockGeometry.backgroundCornerRadius` is 0.28 of the background's thickness, moved from `DockCanvasScene` into the tested kit.
- `MascotOverlay` draws the veil on `backgroundFrame` with that radius, and places the canvas window around it.
- `DockGeometry.perch(for:)` puts the cat on `backgroundFrame`'s top edge. In the screenshot the cat's paws ended on the list frame's top edge, 10 pixels above the Dock's outline.

## Alternatives considered

- **Use the items' extent across the Dock instead of sliding the list.** On macOS 27 it gives the same frame. On a macOS where the items sit inside the list, as older test fixtures assume, it would shrink the veil to the items. Sliding leaves that case alone.
- **Hard-code a 5-point inset.** It would encode one OS version's number, and be wrong wherever the list already matches.
- **Read the Dock's window from the window server.** The Dock draws into one full-screen window on macOS 27, so its bounds say nothing about the background.

## Consequences

- Fitted against the user's screenshot (`veilfit` harness, inline in the job's build.md): the new veil's rounded end lies within 1.18 pixels of the real outline (mean 0.41 over 69 rows), and no outline row lies outside it. The old veil was off by up to 22.9 pixels (mean 7.1), and 7 outline rows lay outside it.
- Measured only for a bottom Dock at one tile size on macOS 27.0.1. The rule assumes a side Dock behaves the same across its width; QA 8.9 asks for the offset if it doesn't. The radius ratio rests on one thickness.
