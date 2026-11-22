# Constraints

The project's quality bar. `scripts/check.sh` enforces most of it. Never weaken this file to make a change pass.

Last reviewed: 2026-11-16. Earlier measurements and the reasons behind each change are in git history.

## Floor (always enforced)

- **No new suppressions** (`// swift-format-ignore`, `@preconcurrency` imports, `nonisolated(unsafe)`, `@unchecked Sendable`) unless a one-line comment explains why the code is safe. The comment must be a plain `//` line directly above, or a `//` comment at the end of the same line. For `// swift-format-ignore`, only the line above counts. A `///` doc comment or a `// MARK:` line doesn't count as an explanation.
- **No stubs**: no `fatalError("TODO")`, `fatalError("not implemented")` or empty `catch {}`, and no `try!` outside tests.
- **No skipped or deleted tests** without a reason in the commit message.
- **No secrets** in source: certificates, `.p12` files, notarytool credentials or Apple IDs.
- **No third-party dependencies** (`dependencies:` in `Package.swift` stays empty) unless the owner agrees first.

## Enforced

| Check | Rule | When it runs |
|---|---|---|
| Compile | Zero errors and zero warnings, Swift 6 language mode | every edit, CI |
| Format | Zero `swift format lint --strict` findings | every edit, CI |
| Secrets | Zero `gitleaks detect` findings | every edit, CI |
| Tests | All pass | before commit, CI (without snapshots) |
| Coverage | At least 80% of changed lines covered in the gated targets (below) | before commit, CI |
| Bundle | The app builds; the signature verifies with the hardened runtime and carries **no entitlements** (ADR 0007); `Info.plist` lints | before commit, CI |
| Idle CPU | 60 s average: ≤ 1.0% in `awake`, ≤ 3.0% in `noddingOff`/`asleep` | manual QA (`scripts/qa-live.sh --only cpu`) |

"Every edit" means `scripts/check.sh fast`. "Before commit" and CI mean `scripts/check.sh task`. The exact commands are in `scripts/check.sh`.

**Why 80% coverage:** it forces a test for every rule without forcing tests for trivial initializers.
**Why 1% CPU:** a novelty app should never show up in Activity Monitor. Looping states get 3× for the animation.

### Coverage gate

- **Gated**: the files in `gated_targets` in `scripts/check.sh` (today `DrowsyDockCore`, `DockOverlayKit` and `LiveQAKit`) that import no AppKit, SpriteKit, IOKit, AX, SwiftUI or ServiceManagement.
- **Exempt**: thin adapters over those frameworks. Each needs an entry in `docs/manual-qa.md` instead.
- When you add a pure library target, add it to `gated_targets` in the same change.

## Measured, not yet enforced

| Metric | Current baseline (`cea7bcd`, 448 tests) | Rule |
|---|---|---|
| Coverage, `DrowsyDockCore` | Lines 393/393, regions 197/198, functions 63/63. The one missed region (`StatusLine`'s `.noBattery` label) can't be reached. | must not fall |
| Coverage, `LiveQAKit` | Lines 395/399, functions 82/86 | must not fall |
| Coverage, `MirroredLogger` | Lines 26/27, functions 8/9 | must not fall |
| Release binary size | 1,482,336 bytes, universal (arm64 728,672, x86_64 730,320). The binary keeps its symbol table; stripping it in `bundle.sh` would shrink it if size ever matters. | ≤ 20% growth without a stated reason |
| Mascot CPU, test harness | `asleep` loop at 12 fps: 2.51–2.55% (on battery). `awake`: about 0.2%. Leaves out the menu-bar app and the Dock window; the Idle CPU row is the real check. | must not grow |

## Not applicable

- **Lighthouse, axe**: native app, no URL.
- **osv-scanner**: zero dependencies. Add it if a dependency is ever approved.
- **Semgrep**: no user input or network surface in v1.

## Exceptions

| ID | Rule | Where | Why | Expires |
|---|---|---|---|---|
| E1 | Idle CPU ≤ 3.0% in `noddingOff`/`asleep` | `MascotScene.loopFramesPerSecond` | At job 003 the loop measured 3.16–3.23% at 15 fps, and the owner accepted the overage. Job 004 lowered it to 12 fps (ADR 0017). Remove this row once `scripts/qa-live.sh --only cpu` passes on the owner's Mac. | 2027-02-07 |
