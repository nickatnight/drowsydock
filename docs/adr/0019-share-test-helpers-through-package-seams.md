# ADR-0019: Share test helpers through a `package` seam and a test-support library

## Status

Accepted (job 004, polish after rework 1; recorded after round-4 code review O6). Extends ADR 0016, which stands: a test target reaches its own module's internals with `@testable import`.

## Context

`OverlayWindow` fades through a seam, `fader`, so tests can record each fade and end it at once: AppKit runs window animations only while a display is awake. Both `DockOverlayKitTests` and `DrowsyDockTests` need a recorder for that seam. Until the polish step, each had its own copy, and only a comment kept the two in step.

To share one copy, the recorder has to live in a module that both test targets import. SwiftPM only lets a test target depend on a regular target, so the shared code goes in a library target. That target then needs the seam, which was internal.

`@testable import DockOverlayKit` in a regular target compiles in debug builds. But `swift build -c release` of the whole package fails: "module 'DockOverlayKit' was not compiled for testing". A scratch-clone probe on 2026-11-10 confirmed this.

## Decision

- **A seam that tests in another target need is `package`, not internal.** `OverlayWindow.Fader` and `OverlayWindow.fader` are `package`. Modules in this package can see them, and nothing outside it can. Only the seam is widened; everything else keeps its access level.
- **Shared test helpers live in a library target under `Tests/`, named `<Module>TestSupport`.** `DockOverlayKitTestSupport` holds `FadeRecorder`, and both overlay test targets depend on it.
- **No product may depend on a `*TestSupport` target.** `scripts/bundle.sh` builds only the `DrowsyDock` product, so the app never links one.
- Test targets keep using `@testable import` for their own module's internals (ADR 0016).

## Alternatives considered

- **`@testable import` in the support target.** It breaks a whole-package release build, as above.
- **Keep one copy per test target.** That is what the code had before. The two copies were already drifting: the app's copy had gained members that only the kit's tests used.
- **A `public` seam.** It would make the fade seam part of DockOverlayKit's API for future Dock apps, for the sake of tests.
- **Put the recorder in DockOverlayKit itself.** That would ship test code in the library and in the app.

## Consequences

- `DrowsyDock` and `qa-helper` could set `fader`; nothing in `Sources` or `scripts/qa/Sources` does. The round-4 reviews found no `FadeRecorder` symbol in the release app and no conformance to `Fader` other than the private `AnimatedFader`.
- `swift build -c release` of the whole package compiles the support target, and it builds.
- The rule that no product depends on `*TestSupport` is kept by review, not by `scripts/check.sh`.
- The two `SplitMix64` copies, in `DrowsyDockCoreTests` and `DrowsyDockTests`, stay separate. Sharing 15 lines between a core test target and an app test target isn't worth a target.
