# Manual QA

These checks need a real Mac session: a screen, a charger, a Dock or an Accessibility grant. The automated checks (`scripts/check.sh task`) cannot reach them. Run them on the bundled app:

```
scripts/bundle.sh && open build/SleepyBattery.app
```

Watch the log in a second terminal (it needs an admin account):

```
log stream --level debug --predicate 'subsystem == "com.drowsydock.SleepyBattery"'
```

Each `Changed:` line is a status change. `Power source notification` is logged at debug level for every IOKit callback, including ones that change nothing in the menu.

## Menu-bar app (slice 1)

| # | Check | Expected |
|---|---|---|
| 1.1 | Launch the app. | A moon-and-z icon appears in the menu bar. No Dock icon appears, and the app is absent from the Cmd-Tab switcher. |
| 1.2 | Choose Quit Sleepy Battery from the menu. | The icon disappears and `pgrep -x SleepyBattery` prints nothing. |
| 1.3 | Open the menu and press Cmd-Q. | Same as 1.2. |
| 1.4 | On an Intel Mac, launch the same bundle. | It starts. The bundle is universal (`lipo -archs` lists `x86_64 arm64`). |

## Live battery (slice 3, `IOKitPowerSource` adapter)

`IOKitPowerSource` is a thin IOKit adapter, so it is exempt from coverage. These checks replace the tests.

| # | Check | Expected |
|---|---|---|
| 3.1 | On battery, open the menu. | The first line reads like `63% · Discharging · Drowsy`. The percentage matches `pmset -g batt`. |
| 3.2 | Plug in the charger while watching the log. | Within 2 s: `Changed: … · Charging · Waking (real)`. About 3 s later: `Changed: … · Charging · Awake (real)`. |
| 3.3 | Unplug the charger while watching the log. | Within 2 s: `Changed: … · Discharging · <state for that percentage> (real)`. |
| 3.4 | Leave the charger in until the battery is full or macOS holds the charge. | The menu shows `… · Plugged in · Awake`. |
| 3.5 | Turn Low Power Mode on in System Settings ▸ Battery, then off. | The menu line gains ` · Low Power`, then loses it. A `Changed:` line is logged each time. |
| 3.6 | Keep the menu open while plugging in. | The line updates while the menu stays open. |
| 3.7 | Check that no timer polls the battery: run `sample SleepyBattery 5` while idle on battery. | The main thread sits in `mach_msg` (run-loop wait). No timer callbacks appear. |
| 3.8 | On a Mac with no battery (Mac mini, iMac, Mac Studio), open the menu. | The first line reads `No battery detected`. |

## Debug ▸ Simulate battery (slice 3)

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
