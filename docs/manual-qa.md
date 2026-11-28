# QA

`docs/manual-qa.md` held 107 rows that the owner worked through by hand at every merge. Job 004 split them into three buckets:

1. **Automated**: `swift test`, so `scripts/check.sh task`, runs them on every commit. No grant, no Dock and no screen are needed.
2. **Live**: `scripts/qa-live.sh` runs them on the owner's Mac against the real Dock and the real app, and prints PASS, FAIL or SKIP per row. `scripts/qa-live.sh --list` names its scenarios; `--dry-run` prints every step and changes nothing. Agents never run it for real.
3. **Manual**: the checklist below, for what needs hardware, a macOS permission dialog or a human eye.

Every row keeps its number. The tables after the checklist map each automated or live row to the test or scenario that replaced it; this mapping is how each test names its QA row. `scripts/check.sh fast` fails when a test or scenario named here doesn't exist, or when an automated row names none.

Every Swift file that the coverage gate exempts must be named here in backticks; `scripts/check.sh fast` fails otherwise. The last section lists them.

`scripts/qa-live.sh` changes the Dock's preferences and puts them back: it saves and checks a backup in `build/qa/dock-backup.plist` before any change, restores it on exit and deletes it only once the Dock's preferences match it again. If a restore can't be verified, it keeps the backup and prints the command to retry; `scripts/qa-live.sh --restore` shows the backup's date and the keys it would change, asks first (`--yes` skips the question), and refuses while a run is still in progress. The backup is readable by your account only. After a run, `build/qa` holds `report.md` and `app.log`, the run's lines of the app's QA log; screenshots and samples are deleted when their checks pass and kept when they fail (`--keep-captures` keeps them all). The terminal you run it from needs Accessibility, Screen Recording and Automation of System Events (ADR 0018), and every process started from that terminal inherits them: consider a terminal profile used only for the run, and revoking the grants afterwards. It reads the app's log from `~/Library/Logs/DrowsyDock/qa.log`, which the app writes only when the run launches it with `--qa-log` (ADR 0020), so a standard account can run every scenario; when the run ends it relaunches the app without `--qa-log`. If the app doesn't quit within 5 s at that point, the run reports a FAIL row asking you to quit it, because it may still be writing the file. The run quits and relaunches `build/DrowsyDock.app` only, refuses to start while another DrowsyDock runs, and skips the Calculator step of 7.8b if Calculator is already open.

## Before a merge

```
scripts/bundle.sh && open build/DrowsyDock.app     # the branch to merge, clean
scripts/qa-live.sh --dry-run                        # every step, nothing changed
scripts/qa-live.sh                                  # then the manual checklist
scripts/qa-live.sh --restore --yes                  # only if a run was killed and left the Dock changed
```

An ad-hoc signed build is a new app to macOS, so after `scripts/bundle.sh` re-grant DrowsyDock's Accessibility as the precondition of section 4 says, or the preflight stops.

Watch the log in a second terminal for the manual rows. Launch the app with `--qa-log`, which any account can read, and follow its QA log:

```
pkill -x DrowsyDock; open build/DrowsyDock.app --args --qa-log
tail -F ~/Library/Logs/DrowsyDock/qa.log
```

Afterwards, quit it and open it without `--qa-log`, so it stops writing the file. On an administrator account, `log stream --level debug --predicate 'subsystem == "app.drowsydock.DrowsyDock"'` shows the same lines.

The QA log has every level. `Overlay:` lines, `Frame checks started`/`stopped` and `Power source notification` are debug lines, so `log stream` needs `--level debug` for them. Each `Changed:` line is a status change. `Power source notification` comes with every IOKit callback, including ones that change nothing in the menu.

## Manual checklist


### Real charger and Low Power Mode

The app's side of these (the lines, the 3 s waking clock, a re-plug, a full battery) is in `AppCoordinatorTests`; these rows check that macOS's own notifications arrive. Watch the log as described below.

| # | Check | Expected |
|---|---|---|
| 3.2 | Plug in the charger while watching the log. | Within 2 s: `Changed: … · Charging · Waking (real)`, or `… · Plugged in · Waking (real)` if macOS holds the charge. About 3 s later the same line with `Awake`. |
| 3.2a | With the battery full or held by Optimized Battery Charging, unplug, then plug in. | Within 2 s: `Changed: … · Plugged in · Waking (real)`. About 3 s later: `Changed: … · Plugged in · Awake (real)`. |
| 3.5 | Turn Low Power Mode on in System Settings ▸ Battery, then off. | The menu line gains ` · Low Power`, then loses it. A `Changed:` line is logged each time. |
| 3.6 | Keep the menu open while plugging in. | The line updates while the menu stays open. |

### A Mac with no battery, sleep and wake

| # | Check | Expected |
|---|---|---|
| 3.8 | On a Mac with no battery (Mac mini, iMac, Mac Studio), open the menu. | The first line reads `No battery detected`. |
| 3.8a | Sleep the Mac, wake it, then unplug. (This overlaps slice 15.) | The unplug is still logged within 2 s, so the IOKit notification survives sleep. |
| 15.1 | With the grant and the cat showing, on battery, sleep the Mac (Apple menu ▸ Sleep), wait a minute, then wake it while watching the log and the Dock. | `The Mac woke from sleep` within about 1 s of waking. The cat shows the pose for the battery's level at once, with no transition and no wave. A `Changed:` line follows only if the menu line changed. |
| 15.2 | On battery, sleep the Mac, plug in the charger while it sleeps, then wake it. | `The Mac woke from sleep`, and the line ends `Charging · Awake (real)` or `Plugged in · Awake (real)`. If no `Waking` line came before it, the resync ran first and the cat is awake without the wake-up. If IOKit's power notification arrived first, a `Waking` line comes first and the resync cuts the wake-up short within about 1 s. Note which order you saw. |

### An Intel Mac

| # | Check | Expected |
|---|---|---|
| 1.4 | On an Intel Mac, launch the same bundle. | It starts. The bundle is universal (`lipo -archs` lists `x86_64 arm64`). |

### The Accessibility grant dialogs

Start without the grant: `tccutil reset Accessibility app.drowsydock.DrowsyDock`, then launch the app. After each rebuild, make sure the grant belongs to the build you are running: an ad-hoc signed build is a new app to macOS, and an old DrowsyDock entry in System Settings ▸ Privacy & Security ▸ Accessibility can show as on while the new build is untrusted. If the menu keeps saying `Grant Accessibility…`, remove the entry with − and grant again. Each ad-hoc signature is new, so macOS keeps the grant with the old build; a stable dev certificate avoids this (`docs/dev-signing.md`, kept locally and not in git, has the steps). `AppCoordinator` re-checks the grant when macOS posts the undocumented `com.apple.accessibility.api` distributed notification (at once and again 1 s later) and each time the menu opens; `AppCoordinatorTests` covers the menu re-check.

| # | Check | Expected |
|---|---|---|
| 4.1 | Without the grant, open the menu. | Below the battery line: `Grant Accessibility…`. No overlay is drawn anywhere. The log shows `Accessibility granted: false`. |
| 4.2 | Choose `Grant Accessibility…`. | macOS shows its "would like to control this computer" alert, and System Settings opens at Privacy & Security ▸ Accessibility with DrowsyDock in the list. |
| 4.3 | Turn DrowsyDock on in that list, then open the menu again. Don't relaunch. | The item reads `Accessibility: Granted`, and the log shows `Accessibility granted: true`. Within 1 s the cat appears on the Dock, and the log shows `Observing the Dock list for:`. |
| 4.4 | Turn DrowsyDock off in the list, then open the menu again. | The item is back to `Grant Accessibility…`, and the overlay disappears. |
| 4.5 | Turn DrowsyDock on in the list and don't open the menu. Watch the log and the Dock. Then turn it off, again without opening the menu. | Within about 1 s of turning it on, the log shows `Accessibility granted: true` and the overlay appears on the Dock. Within about 1 s of turning it off, `Accessibility granted: false` and the overlay disappears. If neither happens until the menu opens, macOS didn't post `com.apple.accessibility.api`; note that here. The menu still catches the change. |

### Second displays and display changes

| # | Check | Expected |
|---|---|---|
| 5.3 | With a second display, move the Dock to it (move the pointer to that display's bottom edge and wait), then log. | `screenFrame` is the second display's frame. On a display arranged above or to the left of the main one, the frame has a y above the main display's height or a negative x. |
| 5.3a | With the Dock on a second display arranged to the right of the main one, set Position on screen to Left and log, then Right and log. Repeat with a display arranged to the left of the main one. | `orientation` reads `left` and then `right` on every display, never the opposite. `perch` faces `right` on a left Dock and `left` on a right Dock. |
| 5.4a | Arrange two displays vertically (one above the other), put the Dock at the bottom of the upper display, turn on auto-hide and let the Dock hide. Log, and look at the top of the lower display. | `hidden: true`, and no cat anywhere, including at the top of the lower display. The pure logic would call a hidden frame that lands on the lower display visible. If the log shows that (`hidden: false` with the frame on the lower display), file it, so a unit test can pin the fix. |
| 7.3 | With two displays, move the Dock to the other display (pointer at its bottom edge). | The cat moves to that display within 1 s. |
| 7.10 | Change the main display's resolution or scaled size (System Settings ▸ Displays). | Within 1 s of the change the cat is back at the Dock's perch. This change moves `primary.maxY`, which every Accessibility-to-AppKit conversion uses. |
| 7.11 | With two displays, drag one to a new position in Displays ▸ Arrange. | Within 1 s the cat is back at the perch on the display holding the Dock. |
| 7.12 | Unplug the display that holds the Dock. | The Dock moves to the remaining display, and within 1 s of it settling the cat is at its perch there. |

### Spaces and full screen

`OverlayWindowTests` checks the window's Space properties; these rows check the behaviour on screen.

| # | Check | Expected |
|---|---|---|
| 6.4 | Switch between Spaces (Ctrl-Left/Right arrow) with the cat showing. | The cat stays on the Dock in every Space and doesn't slide with the Space animation. |
| 6.5 | Make an app full screen (green button), then move the pointer to the bottom edge to reveal the Dock. | The cat never covers the full-screen app while the Dock is hidden. Slice 7's checks cover hiding and re-showing. |
| 7.7 | Make an app full screen, then leave it again. | In the full-screen Space the cat is hidden while the Dock is hidden. It returns within 1 s of leaving full screen. Switching between ordinary Spaces leaves it in place. |

### A frozen Dock

| # | Check | Expected |
|---|---|---|
| 7.13 | Freeze the Dock with `kill -STOP $(pgrep -x Dock)`, move the pointer onto the Dock area, then move it to the menu bar and open DrowsyDock's menu. Then run `kill -CONT $(pgrep -x Dock)`. | The menu opens after at most about 0.5 s, not 6 s or more. Each read of a frozen Dock waits for one 0.5 s timeout. About 0.5 s after the pointer leaves the Dock area, the log shows `Dock geometry unavailable: accessibility(… code: -25204)` (cannot complete), once, with no `Can't observe the Dock list` line before it. The frame checks that run while the pointer is on the Dock log nothing. After `kill -CONT` the cat is back within 1 s of the next event. |
| 7.14 | With the grant and the overlay showing, freeze the Dock with `kill -STOP $(pgrep -x Dock)`. Keep the pointer away from the Dock and switch Spaces three times (Ctrl-Left/Right arrow). Then run `kill -CONT $(pgrep -x Dock)` and switch once more. | One `Dock geometry unavailable: accessibility(… code: -25204)` line for the first switch, none for the next two (`RepeatedFailureFilter` in `DockTracker`). After `kill -CONT` the overlay returns, and a later failure would log again. |

### A notarized release

The owner's first real release checks spec success criterion 9, which no agent or CI run can: they run only `scripts/release.sh --dry-run`, which skips every step that needs Apple's servers, the keychain or a Developer ID. `docs/release.md` has the setup and the commands. The row stays open until that first notarized run.

| # | Check | Expected |
|---|---|---|
| 18.1 | With the Developer ID certificate and the `drowsydock-notary` profile set up, run `scripts/release.sh` with `DEVELOPER_ID` and `NOTARY_PROFILE` on a clean checkout tagged `v<version>`. Publish with `gh release create`, then download the zip from the release page on a Mac that has never run DrowsyDock, unzip it and open the app. | The run reports `Accepted`, then `source=Notarized Developer ID`, and ends with `dist/DrowsyDock-<version>.zip` and its `.sha256`; `shasum -a 256 -c` passes in `dist/`. On the other Mac, `spctl --assess --type execute -v DrowsyDock.app` reports `accepted` and `source=Notarized Developer ID`, and the app opens after macOS's usual question about an app downloaded from the internet, with no warning about an unidentified developer. If the script misread any of Apple's tools' output, note it here. |

### The eye

| # | Check | Expected |
|---|---|---|
| 8.14 | Look at the cat on a Retina display and, if you have one, on a non-Retina display. | Outlines are smooth on both, with no blurry or jagged edges. |
| 3.17 | With the grant and the cat showing, open the menu, go to Debug ▸ Simulate battery, move up and down through the levels, then pick 5%. Open it again and pick 80%. | The submenus open and the highlight follows the pointer as in other menu-bar menus. The menu closes with its usual fade, and the cat starts its transition (10.4, 10.11) as the menu disappears. A harness that drove this same SwiftUI menu measured AppKit's own work when the menu closes at 34 to 58 ms of main-thread time whether or not the app did anything. DrowsyDock's part was under 10 ms on the first pick and under 1.5 ms after that, and it runs after menu tracking has ended. If the menu stutters anyway, repeat the picks while `sample DrowsyDock 10 1 -file menu.txt` runs and attach `menu.txt`. |
| E.1 | Choose each Simulate battery level and Charging once, and look at the cat on the Dock for a few seconds each. | Each pose and its ambient behaviour look like the snapshots under `Tests/DrowsyDockTests/Snapshots/`, and nothing looks broken: no clipped ears, no stray shapes, the veil over the Dock. Once, after Charging then 5%, watch the wave: each dark square sits on its icon's artwork with no taller box above or below it (11.1; the snapshot draws its own fixture icons, so only the real Dock shows the fit). |

That is 30 rows. Not runnable yet:

| # | Check | Status |
|---|---|---|
| 3.8b | Release an `IOKitPowerSource.Subscription` while plugging in or out, then check for no crash, no `Changed:` line after the release, and 0 leaks. | Placeholder until a slice first releases an `IOKitPowerSource.Subscription`. The wake resync (slice 15) re-reads the battery and keeps its subscription, because 3.8a shows the IOKit notification survives sleep. Nothing releases a subscription yet, so the row can't run. |

## Automated and live rows

"Tests" are XCTest methods in `Tests/DrowsyDockTests`, `Tests/DockOverlayKitTests` and `Tests/DrowsyDockCoreTests`. Snapshot references live under `Tests/DrowsyDockTests/Snapshots/`; `RECORD_SNAPSHOTS=1 swift test` rewrites them (ADR 0016). "Live" names a `scripts/qa-live.sh` scenario.

| # | Check | Tests | Live |
|---|---|---|---|
| 1.1 | Launch the app | – | `launch` |
| 1.2 | Choose Quit DrowsyDock from the menu | – | `launch` |
| 1.3 | Open the menu and press Cmd-Q | – | `launch` |
| 3.0 | Launch the app while watching the log | – | `battery` |
| 3.1 | On battery, open the menu | `AppCoordinatorTests.testTheRealBatterysChangesAndLowPowerModeReachTheLine` | `battery` |
| 3.2b | Plug in, unplug and plug in again, all within 3 s | `AppCoordinatorTests.testWakingEndsThreeSecondsAfterTheLastPlugIn` | – |
| 3.3 | Unplug the charger while watching the log | `AppCoordinatorTests.testUnpluggingShowsTheDischargingState` | – |
| 3.4 | Leave the charger in until the battery is full or macOS holds the charge | `AppCoordinatorTests.testAFullBatteryOnACPowerSettlesOnPluggedInAwake` | – |
| 3.7 | Check that no timer polls the battery: run `sample DrowsyDock 5` while idle on battery | – | `idle-sample` |
| 3.9 | Simulate battery ▸ 80%: `80% · Discharging · Awake` | `AppCoordinatorTests.testEachSimulatedLevelShowsItsStateInEitherOrder` | `levels` |
| 3.10 | Simulate battery ▸ 40%: `40% · Discharging · Drowsy` | `AppCoordinatorTests.testEachSimulatedLevelShowsItsStateInEitherOrder` | `levels` |
| 3.11 | Simulate battery ▸ 25%: `25% · Discharging · Yawning` | `AppCoordinatorTests.testEachSimulatedLevelShowsItsStateInEitherOrder` | `levels` |
| 3.12 | Simulate battery ▸ 15%: `15% · Discharging · Nodding off` | `AppCoordinatorTests.testEachSimulatedLevelShowsItsStateInEitherOrder` | `levels` |
| 3.13 | Simulate battery ▸ 5%: `5% · Discharging · Asleep` | `AppCoordinatorTests.testEachSimulatedLevelShowsItsStateInEitherOrder` | `levels` |
| 3.14 | Simulate battery ▸ 5%, then Charging: `5% · Charging · Waking`, then `5% · Charging · Awake` about 3 s later | `AppCoordinatorTests.testChargingShowsWakingThenAwakeThreeSecondsLater` | `levels` |
| 3.15 | Simulate battery ▸ No battery: `No battery detected` | `AppCoordinatorTests.testNoBatteryShowsNoBatteryDetected` | `levels` |
| 3.16 | Simulate battery ▸ 5%, then Real: The real battery's line, with the history it kept while hidden (not stuck at Asleep, and no wake-up for a plug-in made meanwhile) | `AppCoordinatorTests.testRealAfterASimulationShowsTheRealBatteryAgain`, `BatterySessionTests.testReturningToRealKeepsTheRealBatterysHistory`, `BatterySessionTests.testPluggingInWhileSimulatingSettlesTheRealBatteryWithoutAWakeUp` | `levels` |
| 5.1 | With a bottom Dock on the main display, choose Debug ▸ Log Dock geometry | `DockGeometryTests` | `position` |
| 5.2 | Move the Dock to the left, then the right (System Settings ▸ Desktop & Dock ▸ Position on screen), and log again each time | `DockGeometryTests` (left and right perches) | `position` |
| 5.4 | Turn on "Automatically hide and show the Dock", move the pointer away so the Dock hides, then log from the menu | `DockGeometryTests` (hidden frames) | `autohide` |
| 5.5 | With the Dock visible, compare `perch` with the screen | `DockGeometryTests.testOnABottomDockThePerchSitsOnTheTopEdgeInsideTheLastIcon`, `PoseSnapshotTests.testAwakeOnABottomDockThereIsNoVeil` | `align` |
| 6.1 | With the grant and a bottom Dock, launch the app | `AppCoordinatorTests.testTheCatShowsAtThePerchTheTrackerReports`, `OverlayWindowTests.testItSitsOneLevelAboveTheDock` | `align` |
| 6.2 | Click the Dock icon under the cat, then drag a file onto it | `OverlayWindowTests.testItIgnoresTheMouse` | – |
| 6.3 | Click on the desktop and in other apps' windows where the cat overlaps them | `OverlayWindowTests.testItIgnoresTheMouse`, `OverlayWindowTests.testItCanNotBecomeKeyAndStaysOutOfTheWindowCycle` | – |
| 6.6 | Without the grant, launch the app | `DockTrackerTests.testTheOverlayStaysHiddenWithoutTheGrant` (the rule), `AppCoordinatorTests.testTheGrantReachesTheTrackerAndItsHiddenPresentationHidesTheCat` (the wiring) | – |
| 6.7 | With the cat showing, switch to another app and press Cmd-Opt-H (Hide Others) | `OverlayWindowTests.testHideOthersCanNotHideIt` | – |
| 7.0 | Launch with the grant and read the log | – | `launch` |
| 7.1 | In System Settings ▸ Desktop & Dock, set Position on screen to Left, then Right, then Bottom | `DockTrackerTests.testAReadWhileHoveringThatFindsALeftDockShowsTheLeftPerch` | `position` |
| 7.2 | Drag the Size slider, and add or remove a Dock item | `DockTrackerTests` (frame checks, settled reads) | `size` |
| 7.4 | Turn on "Automatically hide and show the Dock" and move the pointer away | `DockTrackerTests.testAnAutoHiddenDockHidesTheOverlay` | `autohide` |
| 7.5 | Turn on Magnification, hover over the icons, then move the pointer up and away | `DockTrackerTests.testAMagnifiedDockFadesTheOverlayOutAtTheRestingPerch` | `magnification` |
| 7.5a | With Magnification on, magnify the icons, then move the pointer straight up just above the icons (still within about 100 points of the… | `DockTrackerTests.testTheOverlayFadesBackInWhenTheDockReturnsToRest` | `magnification` |
| 7.5b | Turn Magnification off and hover over the icons | `DockTrackerTests.testTheRestingDockIsNotMagnified` | `hover` |
| 7.6 | Leave the pointer away from the Dock, then run `sample DrowsyDock 5` | `DockTrackerTests.testNoFrameChecksRunWhileThePointerIsAwayFromTheDock` | `idle-sample` |
| 7.8 | Run `killall Dock` | – | `relaunch` |
| 7.8a | After 7.8, without relaunching DrowsyDock, drag an app into the Dock, then remove it | – | `relaunch` |
| 7.8b | Launch an app that isn't kept in the Dock, wait for its icon to appear, then quit it | – | `relaunch` |
| 7.9 | Choose Debug ▸ Simulate battery ▸ 80% (the awake cat; below 20% its loop runs and has the 3.0% budget of row 9.7) | – | `cpu` |
| 8.1 | 80%: Awake: round dark eyes with a white highlight, ears up, head straight | `PoseSnapshotTests.testAwakeHasRoundOpenEyesUprightEarsAndAStraightHead` | – |
| 8.2 | 40%: Drowsy: the eyelids cover a bit under half of each eye, with a dark lash line along the lid's edge | `PoseSnapshotTests.testDrowsyLidsCoverUnderHalfOfEachEyeTheHeadLeansAndTheEarsFoldSlightly` | – |
| 8.3 | 25%: Yawning (between yawns): eyelids lower than at 40%, the head leans further and the ears fold more | `PoseSnapshotTests.testYawningLidsSitLowerTheHeadLeansFurtherAndTheEarsFoldMore` | – |
| 8.4 | 15%: Nodding off: the eyes are thin slits, the head leans further and the ears droop | `PoseSnapshotTests.testNoddingOffShowsSlitEyesDroopingEarsAndOneZ` | – |
| 8.5 | 5%: Asleep: eyes closed as curved lash lines, the head leans furthest, the ears droop fully, two "z"s (small and large) and a pale blue… | `PoseSnapshotTests.testAsleepShowsClosedEyesFullyDroopedEarsTwoZsAndASnoreBubble`, `PoseSnapshotTests.testAsleepOnABottomDockTheVeilCoversTheDockAndThePawsRestOnItsTopEdge`, `AppCoordinatorTests.testTheVeilShowsAtFivePercentAndGoesAtFifteen` | `align` |
| 8.6 | 5%, then 15%: The veil disappears; the cat shows the 15% pose | `AppCoordinatorTests.testTheVeilShowsAtFivePercentAndGoesAtFifteen`, `TransitionSnapshotTests.testLeavingTheSnoreForNoddingOffDroopsFromWhereTheHeadIs` | – |
| 8.7 | Charging: The cat ends in the awake pose, after the wake-up animation (10.5) | `TransitionSnapshotTests.testAsleepToWakingWakesUpAndEndsAwake` | – |
| 8.8 | No battery: The cat and the veil disappear | `AppCoordinatorTests.testNoBatteryHidesTheCatAndTheVeilUntilABatteryIsBack` | – |
| 8.9 | Move the Dock to the left, then the right, at 5% | `PoseSnapshotTests.testAsleepOnALeftDockTheCatFacesRightAndTheVeilFollowsTheDock`, `PoseSnapshotTests.testAsleepOnARightDockTheCatFacesLeftAndTheVeilFollowsTheDock` | `position` |
| 8.10 | With a left Dock, enlarge it (Size slider) until it fills the display's height | `DockGeometryTests.testOnATallSideDockThePerchStaysBelowTheMenuBar` | – |
| 8.11 | With a bottom Dock, rest the pointer on the last icon (the Trash) until its label appears, then on the cat itself | `AppCoordinatorTests.testHoveringThePerchFadesTheCatOutAndBack`, `DockTrackerTests.testThePointerOverTheIconUnderThePerchFadesTheOverlayOut` | `hover` |
| 8.12 | At 5%, with Magnification on, hover over the icons | `AppCoordinatorTests.testAtFivePercentTheVeilFadesWithTheCat` | `magnification` |
| 8.13 | Leave the cat at 80%, 40% or 25% with the pointer away from the Dock for 10 s, then run `sample DrowsyDock 5` | `SceneHostViewTests.testAnIdlePoseDrawsOneFrameAndThenNothing`, `SceneHostViewTests.testLeavingTheSnoreForAwakeEndsWithEveryViewPaused` | `idle-sample` |
| 8.15 | With a bottom Dock, zoom into a screenshot of the cat and the Dock below it | `PoseSnapshotTests.testAsleepOnABottomDockTheVeilCoversTheDockAndThePawsRestOnItsTopEdge` | `align` |
| 9.1 | Simulate 80% and watch the cat for a minute | `AmbientSnapshotTests.testAnAwakeCatBlinksAfterAPauseAndIsStillOtherwise` | – |
| 9.2 | Simulate 40% and watch for a minute | `AmbientSnapshotTests.testADrowsyCatBlinksSlowly` | – |
| 9.3 | Simulate 25% and watch for two minutes | `AmbientSnapshotTests.testAYawningCatYawnsAndNods` | – |
| 9.4 | Simulate 15% | `AmbientSnapshotTests.testANoddingOffCatFloatsZsAndBobsItsHead` | – |
| 9.5 | Simulate 5% | `AmbientSnapshotTests.testAnAsleepCatSnores` | – |
| 9.6 | Choose 80%, close the menu, move the pointer at least 130 points away from the Dock and wait about 10 s | – | `cpu` |
| 9.7 | Choose 15%, close the menu, keep the pointer at least 130 points away from the Dock and wait about 10 s (the nod-off takes 2.2 s) | `SceneHostViewTests.testTheLoopsDrawTwelveFramesASecond` | `cpu` |
| 9.8 | At 5%, rest the pointer on the Trash (the cat fades), run `sample DrowsyDock 3`, then move the pointer away | `SceneHostViewTests.testAFadedOutCatDrawsNothingAndResumesWhenShown` | `hover` |
| 9.9 | At 25%, switch Simulate battery to 80% in the middle of a yawn | `TransitionSnapshotTests.testAChangeInTheMiddleOfAnAmbientYawnStopsItAndCrossfades` | – |
| 10.1 | 80%, then 40%: A quick (0.6 s) crossfade: the lids sink, the head leans and the ears fold together | `TransitionSnapshotTests.testAwakeToDrowsyCrossfades`, `SceneHostViewTests.testATransitionDrawsThirtyFramesASecondUntilItEnds` | – |
| 10.2 | 40%, then 25%: The cat settles into the yawning pose and yawns: head back, mouth wide, eyes squeezed shut, then a nod and a jerk back up | `TransitionSnapshotTests.testDrowsyToYawningYawns` | – |
| 10.3 | 25%, then 15%: Nod-off: the head droops forward as the eyes fall shut, jerks back up with the eyes half open, and settles into the… | `TransitionSnapshotTests.testYawningToNoddingOffNodsOff` | – |
| 10.4 | 15%, then 5%: A crossfade into the asleep pose: eyes shut, the bubble and two "z"s fade in, and the veil fades in over the Dock | `TransitionSnapshotTests.testNoddingOffToAsleepCrossfades`, `AppCoordinatorTests.testTheVeilShowsAtFivePercentAndGoesAtFifteen` | – |
| 10.5 | 5%, then Charging: Wake-up: the eyes snap open, the bubble pops, the "z"s fade, the veil fades out, the cat stretches tall, three small… | `TransitionSnapshotTests.testAsleepToWakingWakesUpAndEndsAwake`, `AppCoordinatorTests.testChargingShowsWakingThenAwakeThreeSecondsLater` | – |
| 10.6 | 40%, then quickly 25%, 15% and 5% (within a second): The yawn plays to its end, then one crossfade straight to the asleep pose | `TransitionSnapshotTests.testChangesDuringAYawnWaitAndCollapseToTheLastOne` | – |
| 10.7 | 80%, then 5%, then hover the Trash in the middle of the crossfade: The cat fades out and comes back in the asleep pose, without… | `TransitionSnapshotTests.testHoveringDuringTheCrossfadeBringsTheCatBackAsleep` | – |
| 10.8 | With the Dock auto-hidden and off screen, choose 25%, then show the Dock: The cat appears in the yawning pose at once, without replaying… | `TransitionSnapshotTests.testAChangeWhileTheDockIsHiddenShowsTheNewPoseAtOnce` | – |
| 10.9 | Interrupt each transition by resting the pointer on the Trash as it starts: 40%, then 25% (yawn); 25%, then 15% (nod-off); 15%, then 5%… | `TransitionSnapshotTests.testHoveringAsEachTransitionStartsBringsTheCatBackInTheNewPose` | – |
| 10.10 | 40%, then 25%, then Charging within half a second (while the yawn plays) | `TransitionSnapshotTests.testChargingDuringTheYawnPlaysTheWakeUpAtOnce`, `TransitionSnapshotTests.testChargingDuringTheNodOffPlaysTheWakeUpAtOnce`, `TransitionSnapshotTests.testChargingMidTransitionShowsNoZOrBubbleThatWasntThere` | – |
| 10.11 | 5%, wait for the snore loop (a "z" rising, the bubble swelling and shrinking), then 80% | `TransitionSnapshotTests.testLeavingTheSnoreForAwakeEasesTheLoopOut`, `TransitionSnapshotTests.testLeavingTheFloatingZsForAwakeEasesTheLoopOut`, `TransitionSnapshotTests.testLeavingTheSnoreForNoddingOffDroopsFromWhereTheHeadIs`, `TransitionSnapshotTests.testLeavingTheSnoreForWakingPopsTheBubbleFromItsSize`, `TransitionSnapshotTests.testLeavingTheFloatingZsForWakingDoesNotJump`, `SceneHostViewTests.testLeavingTheSnoreForAwakeEndsWithEveryViewPaused` | – |
| 11.1 | 15%, then 5%: As the cat crossfades to sleep and the veil fades in, a wave runs left to right along the Dock: each icon darkens for 0.3… | `CrowdWaveSnapshotTests.testTheWaveRunsLeftToRightAlongABottomDock`, `AppCoordinatorTests.testFallingAsleepPlaysTheWave`, `SceneHostViewTests.testTheCanvasDrawsUntilTheWaveEndsThenPauses` | – |
| 11.2 | After 11.1: 15%, then 5% again: No wave and no new log line | `AppCoordinatorTests.testTheWavePlaysOncePerDischargeCycle` | – |
| 11.3 | After 11.2: Charging, wait for `Awake`, then 5%: The wave plays again, with one new log line | `AppCoordinatorTests.testTheWavePlaysOncePerDischargeCycle` | – |
| 11.4 | Charging, then 5%, then 5% again (pick it twice): One wave only | `AppCoordinatorTests.testPickingFivePercentTwicePlaysOneWave` | – |
| 11.5 | With a left Dock, Charging, then 5%: The wave runs from the top icon down, and the "z"s drift right, into the screen | `CrowdWaveSnapshotTests.testTheWaveRunsDownALeftDockAndTheZsDriftIntoTheScreen`, `CrowdWaveSnapshotTests.testOnARightDockTheZsDriftLeft` | `position` |
| 11.6 | Turn on Dock auto-hide and let the Dock hide | `AppCoordinatorTests.testFallingAsleepWhileTheDockIsHiddenUsesUpTheCycle` | `autohide` |
| 11.7 | Charging, then 5%, then hover the Trash in the middle of the wave: The wave stops at once and doesn't resume when the pointer leaves | `AppCoordinatorTests.testHoveringStopsTheWaveForGood` | – |
| 11.8 | Launch the app with the battery simulated or really below 10%: No wave at launch | `AppCoordinatorTests.testLaunchingAsleepPlaysNoWave` | – |
| 15.3 | Wake the Mac at another level than it slept at: The cat jumps to that level's pose without a transition, even when that is less sleepy | `AppCoordinatorTests.testWakingFromSleepJumpsToTheBatterysStateWithoutATransition`, `AppCoordinatorTests.testAChangeOnBatteryAnimatesTheCat`, `BatterySessionTests.testAResyncDerivesAfreshEvenWhenThatIsLessSleepy` | – |
| 15.4 | Wake the Mac below 10% after sleeping above it: The asleep pose and the veil at once, no wave, and no wave later in that discharge cycle | `AppCoordinatorTests.testWakingFromSleepIntoAsleepPlaysNoWaveAndUsesUpTheCycle`, `BatterySessionTests.testAResyncFromAwakeToAsleepGoesStraightToAsleep`, `CrowdEffectRuleTests.testAWakeResyncIntoAsleepDoesNotPlayIt` | – |
| 15.5 | Wake the Mac on AC power after sleeping on battery: `Awake`, without the wake-up | `AppCoordinatorTests.testWakingFromSleepOnACPowerShowsAwakeWithoutTheWakeUp`, `BatterySessionTests.testAResyncOntoACPowerIsAwakeWithoutAWakeUp` | – |
| 15.6 | Wake the Mac when it reads no battery: `No battery detected`, and the cat and the veil disappear | `AppCoordinatorTests.testWakingFromSleepWithNoBatteryHidesTheOverlay`, `BatterySessionTests.testAResyncWithNoBatteryLeavesNoTracker` | – |
| 15.7 | Sleep and wake the Mac with a Simulate battery level picked: The simulated line stays; Real then shows the battery as it woke | `BatterySessionTests.testAResyncWhileSimulatingChangesOnlyTheRealBattery` | – |

### When every snapshot fails at once

The references were drawn on the Mac `Tests/DrowsyDockTests/Snapshots/RECORDED_ON` names. Another Apple GPU, or a macOS update that changes SpriteKit's antialiasing, can fail all of them together; each failure message names both environments. Look at the diff images under `.build/snapshot-failures/` first. Re-record with `RECORD_SNAPSHOTS=1 swift test` only after a person has seen that just antialiased edges moved (ADR 0016).

## Coverage-exempt files

These files import AppKit, SpriteKit, IOKit, SwiftUI or the Accessibility API, or sit in the app target, which the gate doesn't cover, so the coverage gate skips them (ADR 0002). Each is still checked:

| File | Checked by |
|---|---|
| `DrowsyDockApp`, `AppDelegate` | live `launch` (1.1 to 1.3) |
| `MenuContent` | live `levels` and `battery` drive its real menu; manual 3.17 |
| `MenuBarGlyph` | `MenuBarGlyphTests`: a template image, its size and VoiceOver label, and a snapshot of the mark |
| `AppCoordinator` | `AppCoordinatorTests`; manual 4.1 to 4.5, 15.1, 15.2 |
| `BatteryMonitor` | `AppCoordinatorTests`; live `battery` and `levels`; manual 3.2, 3.5, 3.6, 15.1, 15.2 |
| `IOKitPowerSource` | live `battery`; manual 3.2, 3.2a, 3.5, 3.8, 3.8a |
| `MascotOverlay` | `AppCoordinatorTests`, `PoseSnapshotTests`, `CrowdWaveSnapshotTests`, `SceneHostViewTests` |
| `MascotScene` | `PoseSnapshotTests`, `TransitionSnapshotTests`, `AmbientSnapshotTests`, `SceneHostViewTests` |
| `DockCanvasScene`, `CrowdEffectNode` | `PoseSnapshotTests`, `CrowdWaveSnapshotTests`, `SceneHostViewTests` |
| `CatRenderer`, `CatRenderer+Animations`, `SKAction+Additions` | the snapshot tests; manual E.1 and 8.14 |
| `SceneHostView` | `SceneHostViewTests`; live `idle-sample` and `cpu` |
| `DockTracker+DockTracking` | `AppCoordinatorTests` (it lets them use a fake tracker) |
| `OverlayWindow` | `OverlayWindowTests`; manual 6.4, 6.5, 7.7 |
| `DockTracker`, `DockReader` | `DockTrackerTests` and `DockGeometryTests` for their decisions; live `position`, `size`, `autohide`, `hover`, `magnification`, `relaunch`; manual 7.13, 7.14 |
| `AccessibilityPermission` | manual 4.1 to 4.5 |
| `QALogFile` | `QALogFileTests`: no file without `--qa-log`, the folder's and the file's permissions, refused links, the size limit, each line's time as the script reads it, the same path as the script's `qa_log_path`, and every line reaching both the unified log and the file. `QALogMessageTests`: every `log_` pattern in `live-functions.sh` matches a line the app logs. Every live scenario reads the file |
| `LogSubsystem` | `LogSubsystemTests`: the subsystem equals `CFBundleIdentifier` in `Resources/Info.plist` |
| `QAHelper` | `LiveQAKitTests` for its checks (`LiveQAKit`); `scripts/qa/check-dry-run.sh` for the script's dry run |
| `FadeRecorder` | A test helper, not app code: `OverlayWindowTests` and `AppCoordinatorTests` run through it |
