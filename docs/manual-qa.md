# Manual QA

These checks need a real Mac session: a screen, a charger, a Dock or an Accessibility grant. The automated checks (`scripts/check.sh task`) cannot reach them. Run them on the bundled app:

```
scripts/bundle.sh && open build/DrowsyDock.app
```

Every Swift file that the coverage gate exempts must be named here in backticks. `scripts/check.sh fast` fails otherwise.

Watch the log in a second terminal (it needs an admin account):

```
log stream --level debug --predicate 'subsystem == "com.drowsydock.DrowsyDock"'
```

Each `Changed:` line is a status change. `Power source notification` is logged at debug level for every IOKit callback, including ones that change nothing in the menu.

## Menu-bar app (slice 1, `DrowsyDockApp`)

| # | Check | Expected |
|---|---|---|
| 1.1 | Launch the app. | A moon-and-z icon appears in the menu bar. No Dock icon appears, and the app is absent from the Cmd-Tab switcher. |
| 1.2 | Choose Quit DrowsyDock from the menu. | The icon disappears and `pgrep -x DrowsyDock` prints nothing. |
| 1.3 | Open the menu and press Cmd-Q. | Same as 1.2. |
| 1.4 | On an Intel Mac, launch the same bundle. | It starts. The bundle is universal (`lipo -archs` lists `x86_64 arm64`). |

## Live battery (slice 3, `IOKitPowerSource` and `BatteryMonitor`)

`IOKitPowerSource` is a thin IOKit adapter. `BatteryMonitor` is app wiring: it ends `waking` after 3 s and logs only status changes. Both are exempt from coverage, and these checks replace their tests.

| # | Check | Expected |
|---|---|---|
| 3.0 | Launch the app while watching the log. | `Started: <menu line> (real)` |
| 3.1 | On battery, open the menu. | The first line reads like `63% · Discharging · Drowsy`. The percentage matches `pmset -g batt`. |
| 3.2 | Plug in the charger while watching the log. | Within 2 s: `Changed: … · Charging · Waking (real)`, or `… · Plugged in · Waking (real)` if macOS holds the charge. About 3 s later the same line with `Awake`. |
| 3.2a | With the battery full or held by Optimized Battery Charging, unplug, then plug in. | Within 2 s: `Changed: … · Plugged in · Waking (real)`. About 3 s later: `Changed: … · Plugged in · Awake (real)`. |
| 3.2b | Plug in, unplug and plug in again, all within 3 s. | `Waking` ends about 3 s after the last plug-in, never earlier. |
| 3.3 | Unplug the charger while watching the log. | Within 2 s: `Changed: … · Discharging · <state for that percentage> (real)`. |
| 3.4 | Leave the charger in until the battery is full or macOS holds the charge. | The menu shows `… · Plugged in · Awake`. |
| 3.5 | Turn Low Power Mode on in System Settings ▸ Battery, then off. | The menu line gains ` · Low Power`, then loses it. A `Changed:` line is logged each time. |
| 3.6 | Keep the menu open while plugging in. | The line updates while the menu stays open. |
| 3.7 | Check that no timer polls the battery: run `sample DrowsyDock 5` while idle on battery. | The main thread sits in `mach_msg` (run-loop wait). No timer callbacks appear. |
| 3.8 | On a Mac with no battery (Mac mini, iMac, Mac Studio), open the menu. | The first line reads `No battery detected`. |
| 3.8a | Sleep the Mac, wake it, then unplug. (This overlaps slice 15.) | The unplug is still logged within 2 s, so the IOKit notification survives sleep. |
| 3.8b | Placeholder until a slice first releases an `IOKitPowerSource.Subscription` (likely slice 15). Release it while plugging the charger in or pulling it out, so the release can race an IOKit callback. | No crash, no `Changed:` line after the release, and `leaks DrowsyDock` reports 0 leaks. Nothing releases a subscription yet, so this row can't run today. |

## Debug ▸ Simulate battery (slice 3, `MenuContent`)

On launch the Simulate battery picker shows a check mark on Real. The check mark follows each choice. Each choice that changes the menu line also logs `Changed: <menu line> (simulated <choice>)`, or `(real)` for Real.

| # | Choose | Expected first menu line |
|---|---|---|
| 3.9 | 80% | `80% · Discharging · Awake` |
| 3.10 | 40% | `40% · Discharging · Drowsy` |
| 3.11 | 25% | `25% · Discharging · Yawning` |
| 3.12 | 15% | `15% · Discharging · Nodding off` |
| 3.13 | 5% | `5% · Discharging · Asleep` |
| 3.14 | 5%, then Charging | `5% · Charging · Waking`, then `5% · Charging · Awake` about 3 s later |
| 3.15 | No battery | `No battery detected` |
| 3.16 | 5%, then Real | The real battery's line, re-derived (not stuck at Asleep) |

The choices in reverse order (5% up to 80%) must show the same states. A simulated level is a jump, not a discharge.

## Accessibility (slice 4, `AccessibilityPermission` and `AppCoordinator`)

`AccessibilityPermission` wraps `AXIsProcessTrustedWithOptions` and opens System Settings. `AppCoordinator` holds the grant and re-checks it each time the menu opens (`NSMenu.didBeginTrackingNotification`). An ad-hoc signed build loses the grant on every rebuild. Sign with the "DrowsyDock Dev" certificate from `docs/dev-signing.md` to keep it.

Start these checks without the grant: `tccutil reset Accessibility com.drowsydock.DrowsyDock`, then launch the app.

| # | Check | Expected |
|---|---|---|
| 4.1 | Without the grant, open the menu. | Below the battery line: `Grant Accessibility…`. No overlay is drawn anywhere. The log shows `Accessibility granted: false`. |
| 4.2 | Choose `Grant Accessibility…`. | macOS shows its "would like to control this computer" alert, and System Settings opens at Privacy & Security ▸ Accessibility with DrowsyDock in the list. |
| 4.3 | Turn DrowsyDock on in that list, then open the menu again. Don't relaunch. | The item reads `Accessibility: Granted`, and the log shows `Accessibility granted: true`. |
| 4.4 | Turn DrowsyDock off in the list, then open the menu again. | The item is back to `Grant Accessibility…`, and the overlay disappears. |

## Dock geometry (slice 5, `DockReader`)

`DockReader` reads the frames of the Dock's icon list and items over the Accessibility API and builds a `DockGeometry` (tested in `DockGeometryTests`). It needs the grant. Watch the log with category `dock`. Without the grant, Debug ▸ Log Dock geometry logs `Dock geometry unavailable: accessibility(attribute: "AXChildren", code: -25211)`.

To compare numbers, read the Dock's on-screen frame with Accessibility Inspector (Xcode ▸ Open Developer Tool), or measure it with Cmd-Shift-4. Logged frames are AppKit global coordinates, in points, with the origin at the bottom-left of the main display.

| # | Check | Expected |
|---|---|---|
| 5.1 | With a bottom Dock on the main display, choose Debug ▸ Log Dock geometry. | `orientation: …bottom`, `hidden: false`. `frame` starts at y = 0 and matches the Dock's width and height. `iconFrames` has one entry per Dock item, with no separators. `screenFrame` is the main display's frame. |
| 5.2 | Move the Dock to the left, then the right (System Settings ▸ Desktop & Dock ▸ Position on screen), and log again each time. | `orientation` reads `left`, then `right`. `perch` sits above the topmost icon, facing `right` on a left Dock and `left` on a right Dock. |
| 5.3 | With a second display, move the Dock to it (move the pointer to that display's bottom edge and wait), then log. | `screenFrame` is the second display's frame. On a display arranged above or to the left of the main one, the frame has a y above the main display's height or a negative x. |
| 5.4 | Turn on "Automatically hide and show the Dock", move the pointer away so the Dock hides, then log from the menu. | `hidden: true`. The frame lies partly or fully below (or beside) its display. |
| 5.5 | With the Dock visible, compare `perch` with the screen. | On a bottom Dock, a 64-point square whose bottom edge is the Dock's top edge and whose right edge is the last icon's right edge. |

## Overlay window (slice 6, `OverlayWindow`)

`OverlayWindow` is a borderless, clear, click-through window at the Dock's window level + 1 that joins every Space. Until the mascot exists, `AppCoordinator` draws a pink 64-point outline at the perch from `DockTrackerState` (tested in `DockTrackerTests`). These checks need the grant.

| # | Check | Expected |
|---|---|---|
| 6.1 | With the grant and a bottom Dock, launch the app. | A pink square outline sits on the Dock's top edge, its right edge in line with the last icon's right edge. The log shows `Overlay: shown(…)`. |
| 6.2 | Click the Dock icon under the outline, then drag a file onto it. | The click opens that item and the drop lands on it, as if the outline weren't there. |
| 6.3 | Click on the desktop and in other apps' windows where the outline overlaps them. | The click goes to whatever is under the outline. The outline never takes focus or shows in Cmd-Tab or Mission Control's window list. |
| 6.4 | Switch between Spaces (Ctrl-Left/Right arrow). | The outline stays on the Dock in every Space and doesn't slide with the Space animation. |
| 6.5 | Make an app full screen (green button), then move the pointer to the bottom edge to reveal the Dock. | The outline never covers the full-screen app while the Dock is hidden. Slice 7's checks cover hiding and re-showing. |
| 6.6 | Without the grant, launch the app. | No outline anywhere, and the log shows `Overlay: hidden`. |

## Following the Dock (slice 7, `DockTracker`)

`DockTracker` re-reads the Dock on Accessibility notifications from its list, display changes (`NSApplication.didChangeScreenParametersNotification`), `com.apple.dock.prefchanged`, Space changes and a Dock relaunch. Each event triggers a read at once and another 0.5 s later. While the pointer is within 128 points of the Dock, a once-a-second frame check also runs, which catches magnification. `DockTrackerState` makes every decision (tested in `DockTrackerTests`). `AppDelegate` owns the `AppCoordinator` and starts tracking in `applicationDidFinishLaunching`. Logs: category `dock`, with `--level debug` for `Frame checks started` and `Frame checks stopped`.

Checkpoint B (Milestone 2) passes when 7.1 to 7.9 pass with the debug outline. These checks need the grant.

| # | Check | Expected |
|---|---|---|
| 7.0 | Launch with the grant and read the log. | `Observing the Dock list for: [...]` lists the notifications the Dock accepted. Note them here, because the Dock may reject some. |
| 7.1 | In System Settings ▸ Desktop & Dock, set Position on screen to Left, then Right, then Bottom. | Within 1 s of each change, the outline moves to the new perch: above the topmost icon on a side Dock, on the top edge inside the last icon on a bottom Dock. |
| 7.2 | Drag the Size slider, and add or remove a Dock item. | The outline follows the Dock's new top edge and last icon within 1 s of each change. |
| 7.3 | With two displays, move the Dock to the other display (pointer at its bottom edge). | The outline moves to that display within 1 s. |
| 7.4 | Turn on "Automatically hide and show the Dock" and move the pointer away. | Within 1 s of the Dock hiding, the outline is hidden and the log shows `Overlay: hidden`. If it shows while the Dock is revealed, it must hide again within 1 s of the Dock hiding. Turn auto-hide off: the outline returns within 1 s. |
| 7.5 | Turn on Magnification, hover over the icons, then move the pointer up and away. | The outline fades out while the Dock is magnified. It fades back in within 1 s of the Dock shrinking back, at the same perch. |
| 7.6 | Leave the pointer away from the Dock, then run `sample DrowsyDock 5`. | No timer fires: no `__CFRUNLOOP_IS_CALLING_OUT_TO_A_TIMER_CALLBACK_FUNCTION__` frames, and the main thread waits in `mach_msg`. The log's last frame-check line is `Frame checks stopped`. Rest the pointer on the Dock: `Frame checks started`. |
| 7.7 | Make an app full screen, then leave it again. | In the full-screen Space the outline is hidden while the Dock is hidden. It returns within 1 s of leaving full screen. Switching between ordinary Spaces leaves it in place. |
| 7.8 | Run `killall Dock`. | The Dock relaunches. The log shows `The Dock relaunched`, and the outline returns once the Dock's icons are back, within 1 s of them appearing. The tracker retries after 0.25, 0.5, 1, 2 and 4 s, so a Dock still missing after 7.75 s leaves the outline hidden until the next display, Space or Dock preference change. |
| 7.9 | With the pointer away from the Dock, run the idle CPU measurement from CONSTRAINTS.md. | The average is at most 1.0%. |
