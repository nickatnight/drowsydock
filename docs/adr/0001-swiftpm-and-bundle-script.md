# ADR-0001: Build with SwiftPM and a bundle script, not an Xcode project

## Status

Accepted (Gate 1, 2026-11-06)

## Context

Sleepy Battery is a macOS menu-bar app (`LSUIElement`), and agents build most of it. Every build, test and signing step has to run from a shell without a GUI. An `.xcodeproj` keeps targets, files and settings in a `project.pbxproj` file. Almost every file you add changes it, and it merges badly. The app needs no storyboards, asset catalogs or app extensions.

## Decision

- The repo is a SwiftPM package (`swift-tools-version: 6.0`, macOS 14, `dependencies: []`).
- `scripts/bundle.sh` builds a universal release binary (`swift build -c release --arch arm64 --arch x86_64`). It assembles `build/DrowsyDock.app` from that binary and `Resources/Info.plist`, then runs `codesign` with `$SIGN_IDENTITY`. The default is `-`, an ad-hoc signature.
- `swift test` runs the XCTest targets.

## Alternatives considered

- **Xcode project.** It brings asset catalogs, entitlements editing and archive/export for free. It was rejected because of `project.pbxproj` churn and merge conflicts, and because it is GUI-centric.
- **XcodeGen or Tuist** (generate the project from YAML or Swift). This keeps a project without hand-editing `pbxproj`, but it is a third-party tool. CONSTRAINTS requires asking before adding any dependency.

## Consequences

- The bundle is assembled by hand. `Info.plist` is copied as is, and nothing compiles asset catalogs. An app icon would have to be added to the script.
- The `--arch` flags hand the build to the Xcode build system. The binary lands in `.build/apple/Products/Release`, not `.build/release`.
- Hardened runtime, entitlements and notarization are script work. That belongs to `scripts/release.sh` in plan slice 18.
- Ad-hoc signing changes the code identity on every build, so macOS forgets the Accessibility grant after each rebuild. Plan slice 4 adds `docs/dev-signing.md` for a self-signed identity.
