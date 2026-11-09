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

`Overlay:` lines (what the overlay shows) and `Frame checks started`/`stopped` are logged at debug level, so keep `--level debug`. Each `Changed:` line is a status change. `Power source notification` is logged at debug level for every IOKit callback, including ones that change nothing in the menu.

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

| # | Check | Expected |
|---|---|---|
| 3.17 | With the grant and the cat showing, open the menu, go to Debug ▸ Simulate battery, move up and down through the levels, then pick 5%. Open it again and pick 80%. | The submenus open and the highlight follows the pointer as in other menu-bar menus. The menu closes with its usual fade, and the cat starts its transition (10.4, 10.11) as the menu disappears. A harness that drove this same SwiftUI menu measured AppKit's own work when the menu closes at 34 to 58 ms of main-thread time whether or not the app did anything. DrowsyDock's part was under 10 ms on the first pick and under 1.5 ms after that, and it runs after menu tracking has ended. If the menu stutters anyway, repeat the picks while `sample DrowsyDock 10 1 -file menu.txt` runs and attach `menu.txt`. |

## Accessibility (slice 4, `AccessibilityPermission` and `AppCoordinator`)

`AccessibilityPermission` wraps `AXIsProcessTrustedWithOptions` and opens System Settings. `AppCoordinator` holds the grant. It re-checks it when macOS posts the undocumented `com.apple.accessibility.api` distributed notification (at once and again 1 s later), and each time the menu opens (`NSMenu.didBeginTrackingNotification`), which stays the fallback. An ad-hoc signed build loses the grant on every rebuild. Sign with the "DrowsyDock Dev" certificate from `docs/dev-signing.md` to keep it.

Start these checks without the grant: `tccutil reset Accessibility com.drowsydock.DrowsyDock`, then launch the app.

**Precondition for every row that needs the grant (4.3 to 4.5, and every later row that needs the grant):** after each rebuild, make sure the grant belongs to the build you are running. An ad-hoc signed build is a new app to macOS. An old DrowsyDock entry in System Settings ▸ Privacy & Security ▸ Accessibility can show as on while the new build is untrusted, and the menu keeps saying `Grant Accessibility…`. If that happens, select the DrowsyDock entry, remove it with −, and grant again: choose `Grant Accessibility…` and turn the new entry on, or add `build/DrowsyDock.app` with +. `docs/dev-signing.md` explains why, and how a stable dev certificate avoids it.

| # | Check | Expected |
|---|---|---|
| 4.1 | Without the grant, open the menu. | Below the battery line: `Grant Accessibility…`. No overlay is drawn anywhere. The log shows `Accessibility granted: false`. |
| 4.2 | Choose `Grant Accessibility…`. | macOS shows its "would like to control this computer" alert, and System Settings opens at Privacy & Security ▸ Accessibility with DrowsyDock in the list. |
| 4.3 | Turn DrowsyDock on in that list, then open the menu again. Don't relaunch. | The item reads `Accessibility: Granted`, and the log shows `Accessibility granted: true`. Within 1 s the cat appears on the Dock, and the log shows `Observing the Dock list for:`. |
| 4.4 | Turn DrowsyDock off in the list, then open the menu again. | The item is back to `Grant Accessibility…`, and the overlay disappears. |
| 4.5 | Turn DrowsyDock on in the list and don't open the menu. Watch the log and the Dock. Then turn it off, again without opening the menu. | Within about 1 s of turning it on, the log shows `Accessibility granted: true` and the overlay appears on the Dock. Within about 1 s of turning it off, `Accessibility granted: false` and the overlay disappears. If neither happens until the menu opens, macOS didn't post `com.apple.accessibility.api`; note that here. The menu still catches the change. |

## Dock geometry (slice 5, `DockReader`)

`DockReader` reads the frames of the Dock's icon list and items over the Accessibility API and builds a `DockGeometry` (tested in `DockGeometryTests`). It needs the grant. Watch the log with category `dock`. Without the grant, Debug ▸ Log Dock geometry logs `Dock geometry unavailable: accessibility(attribute: "AXChildren", code: -25211)`.

To compare numbers, read the Dock's on-screen frame with Accessibility Inspector (Xcode ▸ Open Developer Tool), or measure it with Cmd-Shift-4. Logged frames are AppKit global coordinates, in points, with the origin at the bottom-left of the main display.

| # | Check | Expected |
|---|---|---|
| 5.1 | With a bottom Dock on the main display, choose Debug ▸ Log Dock geometry. | `orientation: …bottom`, `hidden: false`. `frame` starts at y = 0 and matches the Dock's width and height. `iconFrames` has one entry per Dock item, with no separators. `screenFrame` is the main display's frame. |
| 5.2 | Move the Dock to the left, then the right (System Settings ▸ Desktop & Dock ▸ Position on screen), and log again each time. | `orientation` reads `left`, then `right`. `perch` sits above the topmost icon, facing `right` on a left Dock and `left` on a right Dock. |
| 5.3 | With a second display, move the Dock to it (move the pointer to that display's bottom edge and wait), then log. | `screenFrame` is the second display's frame. On a display arranged above or to the left of the main one, the frame has a y above the main display's height or a negative x. |
| 5.3a | With the Dock on a second display arranged to the right of the main one, set Position on screen to Left and log, then Right and log. Repeat with a display arranged to the left of the main one. | `orientation` reads `left` and then `right` on every display, never the opposite. `perch` faces `right` on a left Dock and `left` on a right Dock. |
| 5.4 | Turn on "Automatically hide and show the Dock", move the pointer away so the Dock hides, then log from the menu. | `hidden: true`. The frame lies partly or fully below (or beside) its display. |
| 5.4a | Arrange two displays vertically (one above the other), put the Dock at the bottom of the upper display, turn on auto-hide and let the Dock hide. Log, and look at the top of the lower display. | `hidden: true`, and no cat anywhere, including at the top of the lower display. The pure logic would call a hidden frame that lands on the lower display visible. If the log shows that (`hidden: false` with the frame on the lower display), file it, so a unit test can pin the fix. |
| 5.5 | With the Dock visible, compare `perch` with the screen. | On a bottom Dock, a 64 × 80-point frame whose bottom edge is the Dock's top edge and whose right edge is the last icon's right edge. |

## Overlay window (slice 6, `OverlayWindow`)

`OverlayWindow` is a borderless, clear, click-through window at the Dock's window level + 1 that joins every Space. `MascotOverlay` places one at the perch from `DockTrackerState` (tested in `DockTrackerTests`) and draws the cat in it. Job 002 passed sections 6 and 7 with a pink debug outline; since slice 8 the cat replaces it, so "the cat" below means that window. These checks need the grant.

| # | Check | Expected |
|---|---|---|
| 6.1 | With the grant and a bottom Dock, launch the app. | The cat sits on the Dock's top edge above the last icon (usually the Trash), its paws on the edge. The log shows `Overlay: shown(…)`. |
| 6.2 | Click the Dock icon under the cat, then drag a file onto it. | The click opens that item and the drop lands on it, as if the cat weren't there. |
| 6.3 | Click on the desktop and in other apps' windows where the cat overlaps them. | The click goes to whatever is under the cat. The cat never takes focus or shows in Cmd-Tab or Mission Control's window list. |
| 6.4 | Switch between Spaces (Ctrl-Left/Right arrow). | The cat stays on the Dock in every Space and doesn't slide with the Space animation. |
| 6.5 | Make an app full screen (green button), then move the pointer to the bottom edge to reveal the Dock. | The cat never covers the full-screen app while the Dock is hidden. Slice 7's checks cover hiding and re-showing. |
| 6.6 | Without the grant, launch the app. | No cat anywhere. The log shows `Accessibility granted: false` and no `Overlay: shown` line. |
| 6.7 | With the cat showing, switch to another app and press Cmd-Opt-H (Hide Others). | The cat stays on the Dock. |

## Following the Dock (slice 7, `DockTracker`)

`DockTracker` re-reads the Dock on Accessibility notifications from its list, display changes (`NSApplication.didChangeScreenParametersNotification`), `com.apple.dock.prefchanged`, Space changes, and the Dock reappearing in `NSWorkspace.runningApplications` after a relaunch (NSWorkspace posts no launch notification for the Dock, which is an LSUIElement app). Each event triggers a read 0.5 s later. It also reads at once, unless the pointer is near the Dock or has just left it; then the frame checks and the later read cover the change. Accessibility calls time out after 0.5 s, process-wide. While the pointer is within 128 points of the Dock, a once-a-second frame check also runs, which catches magnification. `DockTrackerState` makes the tracking decisions, including whether an event reads at once (tested in `DockTrackerTests`). `AppDelegate` owns the `AppCoordinator` and starts tracking in `applicationDidFinishLaunching`. Logs: category `dock`, with `--level debug` for `Frame checks started` and `Frame checks stopped`.

Checkpoint B (Milestone 2) passed with the debug outline when 7.1 to 7.13 (including 7.5a, 7.5b, 7.8a and 7.8b) passed. Re-run them with the cat. These checks need the grant.

| # | Check | Expected |
|---|---|---|
| 7.0 | Launch with the grant and read the log. | `Observing the Dock list for: ["AXCreated", "AXUIElementDestroyed"]`. A harness run against the Dock on macOS 27 found that the list accepts these two and rejects `AXMoved` and `AXResized` (-25207, notification unsupported). Note any difference here. |
| 7.1 | In System Settings ▸ Desktop & Dock, set Position on screen to Left, then Right, then Bottom. Then do the same from the Dock's own menu (Control-click the separator ▸ Position on Screen), so the pointer is on the Dock during the change. | Within 1 s of each change, the cat moves to the new perch: above the topmost icon on a side Dock, on the top edge inside the last icon on a bottom Dock. With the pointer on the Dock it must not stay faded at the old perch. |
| 7.2 | Drag the Size slider, and add or remove a Dock item. Then make the Dock larger by dragging its separator. | After the slider change and the item changes, the cat follows the Dock's new top edge and last icon within 1 s. While you drag the separator to enlarge the Dock, the cat stays faded, because a larger Dock looks like magnification. It moves to the new perch within 1 s of the pointer leaving the Dock. |
| 7.3 | With two displays, move the Dock to the other display (pointer at its bottom edge). | The cat moves to that display within 1 s. |
| 7.4 | Turn on "Automatically hide and show the Dock" and move the pointer away. | Within 1 s of the Dock hiding, the cat is hidden and the log shows `Overlay: hidden`. If it shows while the Dock is revealed, it must hide again within 1 s of the Dock hiding. Turn auto-hide off: the cat returns within 1 s. |
| 7.5 | Turn on Magnification, hover over the icons, then move the pointer up and away. | The cat fades out while the Dock is magnified. It fades back in within 1 s of the Dock shrinking back, at the same perch. |
| 7.5a | With Magnification on, magnify the icons, then move the pointer straight up just above the icons (still within about 100 points of the Dock) so the Dock shrinks back while the pointer stays near it. | The cat fades back in within 1 s, from the once-a-second frame check, without the pointer leaving the area. |
| 7.5b | Turn Magnification off and hover over the icons. | The cat never fades. The log may show `Frame checks started`, but no `Overlay: fadedOut` line. |
| 7.6 | Leave the pointer away from the Dock, then run `sample DrowsyDock 5`. | No timer fires: no `__CFRUNLOOP_IS_CALLING_OUT_TO_A_TIMER_CALLBACK_FUNCTION__` frames, and the main thread waits in `mach_msg`. The log's last frame-check line is `Frame checks stopped`. Rest the pointer on the Dock: `Frame checks started`. |
| 7.7 | Make an app full screen, then leave it again. | In the full-screen Space the cat is hidden while the Dock is hidden. It returns within 1 s of leaving full screen. Switching between ordinary Spaces leaves it in place. |
| 7.8 | Run `killall Dock`. | The Dock relaunches, and the log shows `The Dock relaunched` every time. `The Dock list was destroyed` may appear as well. The cat returns once the Dock's icons are back, within 1 s of them appearing. The tracker retries after 0.25, 0.5, 1, 2 and 4 s, so a Dock still missing after 7.75 s leaves the cat hidden until the next display, Space or Dock preference change. |
| 7.8a | After 7.8, without relaunching DrowsyDock, drag an app into the Dock, then remove it. | The cat follows the new last icon within 1 s each time. The log shows `Observing the Dock list for:` again after the relaunch, which proves the observer was re-installed on the new Dock. |
| 7.8b | Launch an app that isn't kept in the Dock, wait for its icon to appear, then quit it. | The cat moves to the new last icon within 1 s. The log shows no `The Dock list was destroyed` line and no new `Observing the Dock list for:` line, so an icon's removal isn't mistaken for the list's. |
| 7.9 | Choose Debug ▸ Simulate battery ▸ 80% (the awake cat; below 20% its loop runs and has the 3.0% budget of row 9.7). Then let the app settle before measuring: close the menu, move the pointer at least 130 points away from the Dock (beyond that the once-a-second frame checks stop), and wait about 10 s, so the crossfade, the window fades and any frame check have ended. Run the idle CPU measurement from CONSTRAINTS.md, and keep the menu closed and the pointer away from the Dock for its whole 60 s. | The average is at most 1.0%. Most samples read 0.0, with an occasional single sample of about 3% when the cat blinks. Opening the menu or hovering the Dock during the run adds AppKit's own work and invalidates it: a first run at 80% read 2.04% with menu use, and a hands-off re-run read 0.29% (twenty 1 s samples, all 0.0 but one 3.1% blink). |
| 7.10 | Change the main display's resolution or scaled size (System Settings ▸ Displays). | Within 1 s of the change the cat is back at the Dock's perch. This change moves `primary.maxY`, which every Accessibility-to-AppKit conversion uses. |
| 7.11 | With two displays, drag one to a new position in Displays ▸ Arrange. | Within 1 s the cat is back at the perch on the display holding the Dock. |
| 7.12 | Unplug the display that holds the Dock. | The Dock moves to the remaining display, and within 1 s of it settling the cat is at its perch there. |
| 7.13 | Freeze the Dock with `kill -STOP $(pgrep -x Dock)`, move the pointer onto the Dock area, then move it to the menu bar and open DrowsyDock's menu. Then run `kill -CONT $(pgrep -x Dock)`. | The menu opens after at most about 0.5 s, not 6 s or more. Each read of a frozen Dock waits for one 0.5 s timeout. About 0.5 s after the pointer leaves the Dock area, the log shows `Dock geometry unavailable: accessibility(… code: -25204)` (cannot complete), once, with no `Can't observe the Dock list` line before it. The frame checks that run while the pointer is on the Dock log nothing. After `kill -CONT` the cat is back within 1 s of the next event. |
| 7.14 | With the grant and the overlay showing, freeze the Dock with `kill -STOP $(pgrep -x Dock)`. Keep the pointer away from the Dock and switch Spaces three times (Ctrl-Left/Right arrow). Then run `kill -CONT $(pgrep -x Dock)` and switch once more. | One `Dock geometry unavailable: accessibility(… code: -25204)` line for the first switch, none for the next two (`RepeatedFailureFilter` in `DockTracker`). After `kill -CONT` the overlay returns, and a later failure would log again. |

## The cat (slice 8, `CatRenderer`, `MascotScene`, `DockCanvasScene` and `MascotOverlay`)

`CatRenderer` draws an original apricot cat in SpriteKit shapes (cream muzzle, paws and belly, a ginger forehead patch, rosy cheeks, a curled tail) and puts it into the `MascotPose` for its state (tested in `MascotPoseTests`). `MascotScene` holds the cat in the perch window. `DockCanvasScene` draws the veil in a second, Dock-sized window, which `MascotOverlay` orders out whenever the veil is off. After each change, each scene renders one frame and pauses its `SceneHostView`. These checks need the grant. Take a screenshot of each pose (Cmd-Shift-4, then Space and click the cat's window) and attach it to the QA record.

| # | Choose Debug ▸ Simulate battery ▸ … | Expected |
|---|---|---|
| 8.1 | 80% | Awake: round dark eyes with a white highlight, ears up, head straight. No "z", no bubble, no veil. |
| 8.2 | 40% | Drowsy: the eyelids cover a bit under half of each eye, with a dark lash line along the lid's edge. The head leans a few degrees toward the screen and the ears fold slightly. |
| 8.3 | 25% | Yawning (between yawns): eyelids lower than at 40%, the head leans further and the ears fold more. Clearly different from 40%. |
| 8.4 | 15% | Nodding off: the eyes are thin slits, the head leans further and the ears droop. One small blue "z" beside the head. |
| 8.5 | 5% | Asleep: eyes closed as curved lash lines, the head leans furthest, the ears droop fully, two "z"s (small and large) and a pale blue snore bubble at the nose. The whole Dock is dimmed by a dark veil; every icon stays recognisable. The veil's edge lies on the Dock's own outline all round, rounded ends included: no dark band above the Dock's top edge and no undimmed strip along its bottom edge. Zoom into a screenshot of the Dock's right end to check: the veil's edge and the outline are within 1 point of each other (ADR 0013). |
| 8.6 | 5%, then 15% | The veil disappears; the cat shows the 15% pose. |
| 8.7 | Charging | The cat ends in the awake pose, after the wake-up animation (10.5). |
| 8.8 | No battery | The cat and the veil disappear. Choosing 80% again brings the cat back. |

| # | Check | Expected |
|---|---|---|
| 8.9 | Move the Dock to the left, then the right, at 5%. | On a left Dock the cat sits above the top icon and faces right (tail on the left). On a right Dock it faces left. The "z"s read as the letter Z on both, never mirrored. The veil follows the Dock, and its edge is within 1 point of the Dock's outline all round, as in 8.5. Only a bottom Dock was measured (ADR 0013). If the edge is further off, record by how many points and on which side; the row fails. |
| 8.10 | With a left Dock, enlarge it (Size slider) until it fills the display's height. | The cat stays below the menu bar, overlapping the top icon if it must, never hidden under the menu bar (job 002 G8). |
| 8.11 | With a bottom Dock, rest the pointer on the last icon (the Trash) until its label appears, then on the cat itself. | The cat fades out within about 0.2 s, so the label is readable. Moving to another icon fades it back in. The log shows `Overlay: fadedOut` then `Overlay: shown`. At 5% the veil fades with it. |
| 8.12 | At 5%, with Magnification on, hover over the icons. | The cat and the veil fade out together and fade back in within 1 s of the Dock settling. |
| 8.13 | Leave the cat at 80%, 40% or 25% with the pointer away from the Dock for 10 s, then run `sample DrowsyDock 5`. Then choose 5%, wait for the snore loop, choose 80%, wait 10 s and sample again. (At 15% and 5% the loops draw at 15 fps on purpose, so those poses don't apply.) | Both samples show no drawing: no `SceneHostView.drawFrame` or `SKCRenderer` frames, and the main thread waits in `mach_msg`. The second covers the loop's ease-out, the crossfade, the veil's fade and the canvas pausing, one after another. |
| 8.14 | Look at the cat on a Retina display and, if you have one, on a non-Retina display. | Outlines are smooth on both, with no blurry or jagged edges. |
| 8.15 | With a bottom Dock, zoom into a screenshot of the cat and the Dock below it. | The cat's paws rest on the Dock's outline, with no gap between them. Before ADR 0013 they floated 5 points above it on macOS 26 and later. |

## Ambient behaviour (slice 9, `MascotScene`, `CatRenderer+Animations` and `SKAction+Additions`)

`AmbientSchedule` (tested in `AmbientScheduleTests`) picks what the cat does while it rests. `MascotScene` waits out an idle state's pause with a task, unpauses its view for the one action at 30 fps and pauses again. Looping states keep the view running at 15 fps. `SceneHostView` draws both scenes with `SKRenderer` into a Metal layer, driven by a display link that asks for exactly that rate and stops while paused (ADR 0011). The parts of the cat that never move on their own are rasterized (`SKEffectNode.shouldRasterize`), so a frame redraws only what moves. These checks need the grant.

| # | Check | Expected |
|---|---|---|
| 9.1 | Simulate 80% and watch the cat for a minute. | It blinks (a quick close and open, about 0.25 s) at irregular moments, 8 to 20 s apart. Nothing else moves. |
| 9.2 | Simulate 40% and watch for a minute. | Slow blinks (about 1 s: the heavy lids sink shut, hold, and lift back), 10 to 20 s apart. |
| 9.3 | Simulate 25% and watch for two minutes. | About every 45 s (40 to 50 s): the head leans back, the mouth opens wide with a pink tongue and the eyes squeeze shut, then the head nods forward, jerks back up and settles. About 3 s in all. |
| 9.4 | Simulate 15%. | Small "z"s rise from behind the head one after another (one every 1.6 s), drift up and away and fade. The head bobs slowly. The static "z" is gone while the loop runs. |
| 9.5 | Simulate 5%. | The body rises gently on each breath (about 3 s per breath). On each breath out the snore bubble swells and a "z" rises; on each breath in the bubble shrinks. |
| 9.6 | Choose 80%, close the menu, move the pointer at least 130 points away from the Dock and wait about 10 s. Then run the idle CPU command from CONSTRAINTS.md, with the menu closed and the pointer away from the Dock for the whole 60 s. | The average is at most 1.0%, as in 7.9. If you opened the menu or touched the Dock during the run, run it again. |
| 9.7 | Choose 15%, close the menu, keep the pointer at least 130 points away from the Dock and wait about 10 s (the nod-off takes 2.2 s). Run the same command, hands off as in 9.6. Then do the same at 5%: wait about 10 s, because the crossfade and the crowd wave run for up to 4 s at 30 fps. | Each average is at most 3.0%. The same scene on screen in a harness measured about 1.9 to 2.3% (ADR 0011). A value above 3.0% fails the checkpoint (spec success criterion 6): record it here and stop. `MascotScene.loopFramesPerSecond` (15) is the lever for a fix: each frame per second costs about 0.15%. |
| 9.8 | At 5%, rest the pointer on the Trash (the cat fades), run `sample DrowsyDock 3`, then move the pointer away. | While faded, the sample shows no SpriteKit rendering. After the pointer leaves, the snore loop resumes. |
| 9.9 | At 25%, switch Simulate battery to 80% in the middle of a yawn. | The yawn stops at once and a 0.6 s crossfade carries the cat to the awake pose. |

## Transitions (slice 10, `MascotScene`, `CatRenderer+Animations` and `OverlayWindow`)

`AnimationDirector` (tested in `AnimationDirectorTests`) picks the animation into each new mood: a yawn into yawning, a nod-off into nodding off, a wake-up into waking, a crossfade for every other change. A change that arrives during an animation waits for it, and only the newest change waits. Charging is the exception: the wake-up interrupts whatever plays. While the cat is hidden or faded out, changes switch at once. `BatteryMonitor` still ends `waking` after 3 s (`DrowsinessTracker.wakingDuration`, ADR 0010), and the wake-up animation fits inside that. These checks need the grant.

| # | Choose Debug ▸ Simulate battery ▸ … | Expected |
|---|---|---|
| 10.1 | 80%, then 40% | A quick (0.6 s) crossfade: the lids sink, the head leans and the ears fold together. |
| 10.2 | 40%, then 25% | The cat settles into the yawning pose and yawns: head back, mouth wide, eyes squeezed shut, then a nod and a jerk back up. About 3.4 s. |
| 10.3 | 25%, then 15% | Nod-off: the head droops forward as the eyes fall shut, jerks back up with the eyes half open, and settles into the nodding-off pose. The "z" fades in. About 2.2 s. Then the floating "z" loop starts. |
| 10.4 | 15%, then 5% | A crossfade into the asleep pose: eyes shut, the bubble and two "z"s fade in, and the veil fades in over the Dock. Then the snore loop starts. |
| 10.5 | 5%, then Charging | Wake-up: the eyes snap open, the bubble pops, the "z"s fade, the veil fades out, the cat stretches tall, three small gold sparkles twinkle around its head, and it ends with a blink. At most 3 s. The menu reads `Waking`, then `Awake` about 3 s after the click, with no second animation. |
| 10.6 | 40%, then quickly 25%, 15% and 5% (within a second) | The yawn plays to its end, then one crossfade straight to the asleep pose. No nod-off plays in between. |
| 10.7 | 80%, then 5%, then hover the Trash in the middle of the crossfade | The cat fades out and comes back in the asleep pose, without replaying the crossfade. |
| 10.8 | With the Dock auto-hidden and off screen, choose 25%, then show the Dock | The cat appears in the yawning pose at once, without replaying the yawn. |
| 10.9 | Interrupt each transition by resting the pointer on the Trash as it starts: 40%, then 25% (yawn); 25%, then 15% (nod-off); 15%, then 5% (crossfade); 5%, then Charging (wake-up). Move the pointer away after a second. | Each time the cat fades out and comes back in the new state's pose, at its normal width and with no leftover "z"s or bubble. Within a few seconds the next ambient behaviour starts (a blink, the floating "z"s or the snore), and `sample DrowsyDock 3` shows no drawing once the cat is still. A cat that stays narrower after the wake-up, or that never pauses again, fails this row. |
| 10.10 | 40%, then 25%, then Charging within half a second (while the yawn plays). Repeat with 25%, then 15%, then Charging during the nod-off. | The yawn or nod-off stops and the wake-up plays at once: eyes snap open, stretch, sparkles, blink. The menu reads `Waking`, then `Awake` about 3 s after the click, with no second animation. A crossfade straight to the awake pose with no wake-up fails this row. |
| 10.11 | 5%, wait for the snore loop (a "z" rising, the bubble swelling and shrinking), then 80%. Repeat from 15% ("z"s rising, the head bobbing), then 80%. | As the menu closes the cat starts to move, with no pause you can see. Nothing jumps in the first frame: the "z"s already in the air fade out over about a quarter of a second where they are, and the bubble and the body ease back to their resting size while the 0.6 s crossfade carries the face to awake. Before job 003's rework the "z"s vanished and the bubble snapped to full size in one frame. At 5% the veil fades out over 0.2 s, faster than the cat's crossfade, as `MascotAnimation.crossfade` documents. Then check the other two kinds of transition out of a loop. (a) 5%, wait for the snore, then 15%: the head droops from wherever the breath left it, with no jump, and the body and bubble ease back. (b) 15%, then Charging; and 5%, then Charging: the bubble pops from its current size, the body is back at rest before the stretch starts, and the head doesn't jump. (c) About 10 s after the last change, `sample DrowsyDock 3` shows no `SceneHostView.drawFrame`. |

## The whole Dock nods off (slice 11, `CrowdEffectNode`, `DockCanvasScene`, `MascotOverlay` and `AppCoordinator`)

`CrowdEffectRule` (tested in `CrowdEffectRuleTests`) decides when the effect plays: on entering `asleep` while discharging, once per discharge cycle. Only AC power arms it again. `CrowdWave` (tested in `CrowdWaveTests`) times the wave: 0.15 s between icons, sped up on a crowded Dock so the whole wave takes at most 4 s. `DockGeometry.iconFramesAlongDock` orders the icons (tested in `DockGeometryTests`). `CrowdEffectNode` draws the wave in the Dock window. `AppCoordinator` logs `The whole Dock nods off` (category `mascot`) when it plays, or `… but the overlay isn't showing` when the rule fires while the cat is hidden or faded. The Settings toggle and quiet hours arrive in plan slices 12 and 13. These checks need the grant.

| # | Choose Debug ▸ Simulate battery ▸ … | Expected |
|---|---|---|
| 11.1 | 15%, then 5% | As the cat crossfades to sleep and the veil fades in, a wave runs left to right along the Dock: each icon darkens for 0.3 s and puffs a small blue "z" that drifts up and fades. The dark shape covers the icon's rounded square and nothing more: no taller box showing above or below the icon. The whole wave ends within 4 s (about 2.5 s for 11 icons). The log shows `The whole Dock nods off` once. |
| 11.2 | After 11.1: 15%, then 5% again | No wave and no new log line. |
| 11.3 | After 11.2: Charging, wait for `Awake`, then 5% | The wave plays again, with one new log line. |
| 11.4 | Charging, then 5%, then 5% again (pick it twice) | One wave only. |
| 11.5 | With a left Dock, Charging, then 5% | The wave runs from the top icon down, and the "z"s drift right, into the screen. On a right Dock they drift left. The dark shape covers each icon's rounded square and nothing more, as in 11.1. |
| 11.6 | Turn on Dock auto-hide and let the Dock hide. Choose Charging, wait for `Awake`, then 5%. Show the Dock. | No wave, and the log shows `… but the overlay isn't showing`. The cat appears asleep. Choosing 15% and 5% with the Dock shown plays nothing until the next charge. |
| 11.7 | Charging, then 5%, then hover the Trash in the middle of the wave | The wave stops at once and doesn't resume when the pointer leaves. |
| 11.8 | Launch the app with the battery simulated or really below 10% | No wave at launch. |
