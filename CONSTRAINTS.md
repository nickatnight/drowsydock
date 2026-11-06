# Constraints

Last reviewed: 2026-11-06 (draft, emgee job 001-sleepy-battery, from the skill defaults)

## Floor (always enforced)

- No new suppressions: `// swift-format-ignore`, `@preconcurrency` imports, `nonisolated(unsafe)` or `@unchecked Sendable` unless a one-line comment explains why the type is safe.
- No unimplemented stubs: `fatalError("TODO")` or `fatalError("not implemented")`, an empty `catch {}`, or `try!` outside tests.
- No skipped or deleted tests without a reason in the commit message.
- No secrets in source: no certificates, `.p12` files, notarytool credentials or Apple IDs.
- No third-party dependencies (empty `dependencies:` in `Package.swift`) without asking first.
- This file is not weakened to make a change pass.

## Enforced with numbers

| Dimension | Rule | Checked by | Runs at |
|---|---|---|---|
| Compile | Zero errors and zero warnings, Swift 6 language mode | `swift build -Xswiftc -warnings-as-errors` | every edit (`check.sh fast`) |
| Format | Zero findings | `swift format lint --strict --recursive Sources Tests` | every edit |
| Secrets | No findings | `gitleaks detect --redact --no-banner` | every edit |
| Tests | All pass | `swift test` | task end (`check.sh task`) |
| Coverage | Changed lines in `Sources/SleepyBatteryCore/**` and the pure files of `Sources/DockOverlayKit/**` ≥ 80% covered. Why 80%: it forces a test for every rule without forcing tests for trivial initialisers. | `swift test --enable-code-coverage` → `xcrun llvm-cov export -format=lcov` intersected with `git diff` | task end |
| Bundle | The app assembles, the signature verifies and the plist is valid | `scripts/bundle.sh && codesign --verify --strict build/SleepyBattery.app && plutil -lint Resources/Info.plist` | task end |
| Idle CPU (external) | Average ≤ 1.0% in `awake`, ≤ 3.0% in `noddingOff`/`asleep`, over 60 s. Why: a novelty app must never show up in Activity Monitor. 1% is below the noise of a typical menu-bar utility. Looping states get 3× that for a 30 fps loop. | `top -l 61 -s 1 -stats cpu -pid $(pgrep -x SleepyBattery) \| awk 'NR>1 && /^[0-9.]+$/ {s+=$1; n++} END {print s/n}'` | manual QA (needs the Accessibility grant) |

Exempt from coverage: thin adapters over IOKit, AX, AppKit, SpriteKit and ServiceManagement. Each of these must have an entry in `docs/manual-qa.md` instead.

## Measured, not yet enforced

| Metric | Today | Direction |
|---|---|---|
| Project coverage of `SleepyBatteryCore` | n/a (no code yet). Record after slice 3. | must not fall |
| Release binary size | n/a. Record after slice 1. | must not grow by more than 20% without a reason |

## Not applicable

- Lighthouse and axe: this is a native app with no URL.
- osv-scanner: the project has zero dependencies. Add it if a dependency is ever approved.
- Semgrep: not installed. There is no user input or network surface in v1.

## Exceptions

| ID | Rule | Path | Reason | Owner | Expires |
|---|---|---|---|---|---|
| (none) | | | | | |
