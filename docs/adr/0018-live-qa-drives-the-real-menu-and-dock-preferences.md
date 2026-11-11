# ADR-0018: The live QA script drives the app's real menu, and the Dock through System Events

## Status

Accepted (job 004). The app side is Gate 1 decision 2 (2026-11-09). The Dock side replaced the spec's `defaults write` and `killall Dock` after the round-1 test review.

## Context

42 rows of `docs/manual-qa.md` cite a live scenario, because they need the real app on the real Dock: the perch after a Dock change, the veil against the drawn Dock, hover and magnification, idle CPU. `scripts/qa-live.sh` checks them on the owner's Mac. To do that it has to put the app in each battery state and change the Dock's position, size, auto-hide and magnification, then read what the app did.

Two questions had to be settled:

- **How to put the app in a state.** The app already has Debug ▸ Simulate battery. The other choice was a control channel compiled only into a QA build.
- **How to change the Dock.** The spec suggested `defaults write com.apple.dock` and `killall Dock`. The round-1 test review showed that this exercises only the app's Dock-relaunch path: the `NSWorkspace` relaunch detection and its retries. The rows describe a change made in System Settings, where the Dock keeps running and the app learns of the change through `com.apple.dock.prefchanged` and Accessibility notifications. With `killall`, a broken `prefchanged` observer would pass all four scenarios.

## Decision

- **The app is driven through its own menu.** The script clicks Debug ▸ Simulate battery with System Events (`osascript`), the way a person would. The app has no QA-only code.
- **Results come from the app's log.** The script reads `Started:`, `Changed:`, `Overlay: …` and `Accessibility granted:` lines with `log stream --level debug`. Latency is measured from each line's own timestamp.
- **The Dock is changed through System Events' `dock preferences`** (`screen edge`, `dock size`, `autohide`, `magnification`, `magnification size`). That applies the change live, as System Settings does. Only QA 7.8, the Dock relaunch, uses `killall Dock`.
  - `dock_preference` accepts only the properties and values the scenarios use, because both go into AppleScript as written.
  - Every AppleScript call to System Events or the app runs inside `with timeout of 10 seconds`.
- **Every Dock change is undone.** Before any change, the script saves and verifies a backup of `com.apple.dock` in `build/qa/dock-backup.plist`. A trap restores it on exit, error or Ctrl-C, and deletes the backup only once the domain matches it again. The `restore-selftest` scenario proves the restore on the real Dock before any other change, and the run stops if that restore fails. `--restore` recovers after a `kill -9`.
- **Pointer moves, screenshots and Accessibility reads of the Dock go through `qa-helper`**, a separate executable product that `scripts/bundle.sh` never includes.

## Alternatives considered

- **A control channel in a QA-only build.** This was spec option 2, and Gate 1 rejected it. It would add a code path the shipped app doesn't have, so the checks would run against a different app, and the menu would go untested.
- **`defaults write` plus `killall Dock` for every Dock change.** This was the spec's suggestion, and round 1 dropped it for the reason above. It stays only for QA 7.8, which is the relaunch row.

## Consequences

- The menu is tested every run, and the app gains no code for testing.
- The terminal running the script needs three grants: Accessibility (the menu clicks and pointer moves), Screen Recording (screenshots) and Automation of System Events. Every process started from that terminal inherits them. The preflight checks each grant and stops with the System Settings path.
- `log stream` needs an administrator account. On a standard account the preflight stops and says so.
- If System Events can't drive the Dock live on some macOS version, the System Settings path of QA 7.1, 7.2, 7.4 and 7.5 goes back to the manual list. The relaunch path stays covered by 7.8.
- Agents never run the script for real. `scripts/check.sh fast` proves that `--dry-run` touches nothing, and runs the restore and the restore self-test against a scratch defaults domain.
