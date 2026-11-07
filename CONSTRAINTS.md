# Constraints

Last reviewed: 2026-11-06 (draft, emgee job 001-foundation, from the skill defaults)

## Floor (always enforced)

- No new suppressions: `// swift-format-ignore`, `@preconcurrency` imports, `nonisolated(unsafe)` or `@unchecked Sendable` unless a one-line comment explains why the type is safe. The comment is a plain `//` line directly above, or a `//` comment after the code on the same line. For `// swift-format-ignore` only the line above counts. A `///` doc comment or a `// MARK:` line is not an explanation.
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
| Coverage | Changed lines in `Sources/DrowsyDockCore/**` and the pure files of `Sources/DockOverlayKit/**` ≥ 80% covered. Why 80%: it forces a test for every rule without forcing tests for trivial initialisers. | `swift test --enable-code-coverage` → `xcrun llvm-cov export -format=lcov` intersected with `git diff` | task end |
| Bundle | The app assembles, the signature verifies with the hardened runtime, and the plist is valid. No entitlement may re-enable DYLD variables or disable library validation. | `scripts/bundle.sh && codesign --verify --strict build/DrowsyDock.app && codesign -dv build/DrowsyDock.app` (flags include `runtime`) `&& plutil -lint Resources/Info.plist` | task end |
| Idle CPU (external) | Average ≤ 1.0% in `awake`, ≤ 3.0% in `noddingOff`/`asleep`, over 60 s. Why: a novelty app must never show up in Activity Monitor. 1% is below the noise of a typical menu-bar utility. Looping states get 3× that for a 30 fps loop. | `top -l 61 -s 1 -stats cpu -pid $(pgrep -x DrowsyDock) \| awk 'NR>1 && /^[0-9.]+[[:space:]]*$/ {s+=$1; n++} END {print s/n}'` | manual QA (needs the Accessibility grant) |

Exempt from coverage: thin adapters over IOKit, AX, AppKit, SpriteKit and ServiceManagement. Each of these must have an entry in `docs/manual-qa.md` instead.

`gated_targets` in `scripts/check.sh` lists the gated targets, today `Sources/DrowsyDockCore` and `Sources/DockOverlayKit`. The gate covers their files that import none of those frameworks, and treats every other file under `Sources` as exempt. So a job that adds a pure library target adds it to `gated_targets` and to the Coverage row above in the same change.

## Measured, not yet enforced

| Metric | Today | Direction |
|---|---|---|
| Project coverage of `DrowsyDockCore` | At the end of job 001 (`f08892b`): lines 194/194 (100%), regions 97/98 (98.98%), functions 29/29, from 67 tests (`xcrun llvm-cov report` over `Sources/DrowsyDockCore/*.swift` after `swift test --enable-code-coverage`). After slice 3 it was lines 183/183 from 57 tests. The round-1 review fixes brought it to lines 190/190 and regions 96/97 at `2443161`, and the parser refactor in polish pass 2 (`0b58d10`, the `roundedPercentage` helper) added the rest. The missed region is the `.noBattery` label in `StatusLine`. It can't be reached, because a `nil` reading returns "No battery detected" first. | must not fall |
| Release binary size | 112,176 bytes after slice 1 (universal arm64 + x86_64, `stat -f %z build/DrowsyDock.app/Contents/MacOS/DrowsyDock`). `lipo -detailed_info`: the arm64 slice is 63,024 bytes and the x86_64 slice 30,608. The other 18,544 bytes are fat-file alignment padding. The arm64 slice is larger because its segments round up to 16 KB pages. SwiftUI, AppKit and the Swift runtime link dynamically, so the binary holds only the app's own code. After slice 3: 397,168 bytes (arm64 200,560, x86_64 165,168), 3.5× slice 1. Reason: the first real code. In the arm64 slice, `__text` grew from 5,880 to 36,328 bytes (the statically linked core, the monitor, the menu and the IOKit adapter). `__LINKEDIT` grew from 48 KB to 112 KB, because the release binary keeps its symbol table (852 symbols, up from 342). Stripping local symbols in `scripts/bundle.sh` would shrink `__LINKEDIT` if size ever matters. After the round-1 review fixes (`2443161`): 404,976 bytes (arm64 208,368, x86_64 173,056), +2.0% over slice 3. At the end of job 001 (`f08892b`): 406,272 bytes (arm64 209,664, x86_64 178,528), +0.3% over `2443161`, from the rename and polish pass 2. In job 002 (round-1 fixes): 833,808 bytes (arm64 407,824, x86_64 394,720), +105% over job 001. Reason: the first DockOverlayKit code (AX reader, tracker, overlay window, geometry), statically linked, plus its symbols. Unsigned and built the same way, `main` gives 409,064 bytes and this job 819,656. In the arm64 slice `__text` grew from 35,624 to 101,116 bytes, `__LINKEDIT` from 112 KB to 240 KB, and the symbol count from 931 to 1,915. | must not grow by more than 20% without a reason |

## Not applicable

- Lighthouse and axe: this is a native app with no URL.
- osv-scanner: the project has zero dependencies. Add it if a dependency is ever approved.
- Semgrep: not installed. There is no user input or network surface in v1.

## Exceptions

| ID | Rule | Path | Reason | Owner | Expires |
|---|---|---|---|---|---|
| (none) | | | | | |
