# ADR-0002: Three targets, with the logic in a pure core

## Status

Accepted (Gate 1, 2026-11-06)

## Context

The app's decisions are which state matches a battery reading, when to wake, and (in later slices) which animation to play and where the Dock is. All of these depend on IOKit, the Accessibility API, AppKit and SpriteKit. The builder can't plug in a charger, grant Accessibility or watch the screen. So any logic that only runs inside those frameworks can't be tested. Later Dock apps are also meant to reuse the Dock-tracking code.

## Decision

The package has three targets:

- **`SleepyBatteryCore`** (library) holds value types and pure rules, such as `DrowsinessTracker`, `Thresholds`, `PowerSourceParser`, `BatterySession` and `StatusLine`. It must not import AppKit, ApplicationServices, Cocoa, IOKit, ServiceManagement, SpriteKit or SwiftUI.
- **`DockOverlayKit`** (library) holds Dock geometry, the overlay window and the Accessibility permission. It has no battery or mascot knowledge, so it can move to its own package later without a refactor.
- **`SleepyBattery`** (executable) holds thin adapters: the SwiftUI menu, the IOKit subscription, and the wiring.

`scripts/check.sh` enforces the split:

- `fast` fails if the core imports one of the frameworks above.
- `task` requires at least 80% coverage of changed lines in the core and in DockOverlayKit files that import none of them.
- Every file that the coverage gate exempts must be named in `docs/manual-qa.md`.

## Alternatives considered

- **One executable target.** This is simpler, but the logic would sit next to IOKit and SwiftUI and could only be tested inside a running app.
- **A separate package for `DockOverlayKit` now.** This was rejected as premature. The spec plans to extract it later, which a separate target in this package already makes possible.

## Consequences

- External data is parsed once, at the edge, into core types. `PowerSourceParser` takes `[[String: Any]]` and repeats the `kIOPS…Key` strings from `IOPSKeys.h`, because the core can't import IOKit.
- Logic that would otherwise sit in the app moves into the core so it can be tested. Examples are simulator routing (`BatterySession`) and the menu text (`StatusLine`).
- The executable's code has no unit tests. `docs/manual-qa.md` covers it instead.
- `DockOverlayKit` holds only an empty file until plan slice 4, because SwiftPM rejects an empty target.
