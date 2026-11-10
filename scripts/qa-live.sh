#!/usr/bin/env bash
# Live QA: drives the real DrowsyDock on the real Dock and checks the rows of docs/manual-qa.md
# that need them. The owner runs it on their own Mac; agents only run it with --dry-run.
#
#   scripts/qa-live.sh                 run every scenario
#   scripts/qa-live.sh --only a,b      run the named scenarios (--list names them)
#   scripts/qa-live.sh --dry-run       print every step, change nothing
#   scripts/qa-live.sh --list          list the scenarios and the QA rows each checks
#   scripts/qa-live.sh --restore       restore the Dock preferences that a killed run left changed
#
# It changes the Dock's preferences (position, size, auto-hide, magnification) with
# `defaults write com.apple.dock` and `killall Dock`. Before any change it saves them to
# build/qa/dock-backup.plist and prints the command that restores them; a trap restores them on
# exit, error or Ctrl-C. A kill -9 skips the trap: run the printed command, or --restore.
#
# It drives Debug ▸ Simulate battery through the app's real menu with System Events, moves the
# pointer and takes screenshots through scripts/qa's helper, and reads the app's log. Your
# terminal needs Accessibility and Screen Recording (System Settings ▸ Privacy & Security), and
# DrowsyDock needs its own Accessibility grant. It prints PASS, FAIL or SKIP per QA row, writes
# build/qa/report.md, and exits 1 if any row fails.
set -uo pipefail
cd "$(dirname "$0")/.."
root="$PWD"

qa_dir="$root/build/qa"
backup="$qa_dir/dock-backup.plist"
report="$qa_dir/report.md"
app_log="$qa_dir/app.log"
app="$root/build/DrowsyDock.app"
helper="$root/.build/release/qa-helper"
subsystem="com.drowsydock.DrowsyDock"
restore_command="test -f '$backup' && defaults delete com.apple.dock && defaults import com.apple.dock '$backup' && killall Dock && rm '$backup'"

scenarios=(
  "restore-selftest|-|saves the Dock preferences, changes nothing, restores them"
  "launch|1.1 1.2 1.3 7.0|a menu-bar app with no Dock icon; Quit and Cmd-Q end it"
  "battery|3.0 3.1|the real battery's line matches pmset"
  "levels|3.9 3.10 3.11 3.12 3.13 3.14 3.15 3.16|every Simulate battery choice, in both orders"
  "position|5.1 5.2 7.1 8.9 11.5|the Dock on the left, right and bottom: geometry, perch and wave"
  "size|7.2|the overlay follows a Dock size change"
  "autohide|5.4 7.4 11.6|an auto-hidden Dock hides the cat and the wave"
  "hover|7.5b 8.11 9.8|the cat fades for its icon's label only; a faded snore draws nothing"
  "magnification|7.5 7.5a 8.12|magnifying the Dock fades the cat and the veil, and they return"
  "relaunch|7.8 7.8a 7.8b|the cat returns after killall Dock; an app's icon isn't the list"
  "align|8.5 8.15|veil and paws within 1 pt of the Dock's frames, from screenshots"
  "cpu|7.9 9.6 9.7|idle CPU against the budgets in CONSTRAINTS.md and exception E1"
  "idle-sample|3.7 7.6 8.13|no timer and no drawing while idle, from sample"
)

dry_run=false
only=""
results=()
failed=false
owns_backup=false
needs_app=false
log_pid=""

usage() {
  sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
}

list() {
  local entry name rows what
  for entry in "${scenarios[@]}"; do
    IFS='|' read -r name rows what <<<"$entry"
    printf '%-17s QA %-34s %s\n' "$name" "$rows" "$what"
  done
}

while (($#)); do
  case "$1" in
    --dry-run) dry_run=true ;;
    --only)
      only="${2:-}"
      shift
      ;;
    --list)
      list
      exit 0
      ;;
    --restore) mode_restore=true ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
  shift
done

# MARK: - Output

say() { printf '%s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }

act() {
  if $dry_run; then
    printf '    would run: %s\n' "$*"
    return 0
  fi
  "$@"
}

result() {
  local verdict="$1" rows="$2" scenario="$3" detail="$4"
  if $dry_run; then
    printf '    would report: QA %s (%s), %s\n' "$rows" "$scenario" "$detail"
    return
  fi
  printf '%s QA %s (%s): %s\n' "$verdict" "$rows" "$scenario" "$detail"
  results+=("$verdict|$rows|$scenario|$detail")
  if [[ $verdict == FAIL ]]; then failed=true; fi
}

check() {
  local rows="$1" scenario="$2" detail="$3"
  shift 3
  if $dry_run; then
    printf '    would check: %s (QA %s)\n' "$detail" "$rows"
    return
  fi
  if "$@"; then
    result PASS "$rows" "$scenario" "$detail"
  else
    result FAIL "$rows" "$scenario" "$detail"
  fi
}

write_report() {
  $dry_run && return
  mkdir -p "$qa_dir"
  {
    echo "# Live QA report"
    echo
    echo "$(date '+%Y-%m-%d %H:%M'), $(git rev-parse --short HEAD), macOS $(sw_vers -productVersion)"
    echo
    echo "| Result | QA rows | Scenario | Detail |"
    echo "|---|---|---|---|"
    local entry verdict rows scenario detail
    for entry in "${results[@]}"; do
      IFS='|' read -r verdict rows scenario detail <<<"$entry"
      echo "| $verdict | $rows | $scenario | ${detail//|/\\|} |"
    done
  } >"$report"
  say "Report: $report"
}

# MARK: - Dock preferences

save_dock_backup() {
  step "Saving the Dock's preferences"
  if [[ -f $backup ]] && ! $dry_run; then
    say "A backup from a run that never restored it is still at $backup." >&2
    say "Restore it first: scripts/qa-live.sh --restore" >&2
    exit 1
  fi
  act mkdir -p "$qa_dir"
  act defaults export com.apple.dock "$backup"
  owns_backup=true
  say "If this run is killed, restore the Dock with:"
  say "  $restore_command"
}

dock_matches_backup() {
  [[ -f $backup ]] || return 1
  cmp -s <(defaults export com.apple.dock - | plutil -convert xml1 -o - -) \
    <(plutil -convert xml1 -o - "$backup")
}

# Puts the Dock's preferences back exactly as saved, and deletes the backup. Safe to run twice.
restore_dock() {
  $dry_run && {
    printf '    would run: %s\n' "$restore_command"
    return
  }
  [[ -f $backup ]] || return 0
  if dock_matches_backup; then
    say "The Dock's preferences are unchanged."
  else
    say "Restoring the Dock's preferences."
    defaults delete com.apple.dock && defaults import com.apple.dock "$backup" && killall Dock
  fi
  rm -f "$backup"
}

dock_set() {
  act defaults write com.apple.dock "$@"
  act killall Dock
  pause 3
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if $needs_app && ! $dry_run && app_running; then
    simulate Real 2>/dev/null
  fi
  if [[ -n $log_pid ]]; then kill "$log_pid" 2>/dev/null; fi
  if $owns_backup; then restore_dock; fi
  write_report
  exit "$status"
}

if [[ ${mode_restore:-false} == true ]]; then
  if [[ ! -f $backup ]]; then
    say "No backup at $backup; nothing to restore."
    exit 0
  fi
  restore_dock
  exit 0
fi

# MARK: - Waiting and the app's log

pause() {
  if $dry_run; then
    printf '    would wait %s s\n' "$1"
    return
  fi
  sleep "$1"
}

log_mark=0
mark_log() {
  $dry_run && return
  log_mark="$(wc -l <"$app_log" | tr -d ' ')"
}

wait_log() {
  local pattern="$1" seconds="$2" waited=0
  if $dry_run; then
    printf '    would wait up to %s s for a log line matching: %s\n' "$seconds" "$pattern"
    return 0
  fi
  while ((waited < seconds * 10)); do
    if tail -n "+$((log_mark + 1))" "$app_log" | grep -Eq -- "$pattern"; then return 0; fi
    sleep 0.1
    waited=$((waited + 1))
  done
  return 1
}

last_log() {
  tail -n "+$((log_mark + 1))" "$app_log" | grep -E -- "$1" | tail -n 1
}

no_log_since_mark() {
  ! tail -n "+$((log_mark + 1))" "$app_log" | grep -Eq -- "$1"
}

# MARK: - Driving the app

menu() {
  if $dry_run; then
    printf '    would click in the menu: %s\n' "$(printf '%s ▸ ' "$@" | sed 's/ ▸ $//')"
    return 0
  fi
  osascript - "$@" >/dev/null <<'APPLESCRIPT'
on run itemPath
  tell application "System Events"
    tell process "DrowsyDock"
      set barItem to menu bar item 1 of last menu bar
      click barItem
      delay 0.3
      set currentMenu to menu 1 of barItem
      repeat with i from 1 to (count of itemPath) - 1
        set parentItem to menu item (item i of itemPath) of currentMenu
        click parentItem
        delay 0.3
        set currentMenu to menu 1 of parentItem
      end repeat
      click menu item (item -1 of itemPath) of currentMenu
    end tell
  end tell
end run
APPLESCRIPT
}

simulate() {
  menu Debug "Simulate battery" "$1"
}

menu_first_line() {
  osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "DrowsyDock"
    set barItem to menu bar item 1 of last menu bar
    click barItem
    delay 0.3
    set firstLine to name of menu item 1 of menu 1 of barItem
    key code 53
    return firstLine
  end tell
end tell
APPLESCRIPT
}

app_running() { pgrep -x DrowsyDock >/dev/null; }

menu_bar_item_exists() {
  [[ $(osascript -e 'tell application "System Events" to exists menu bar item 1 of last menu bar of process "DrowsyDock"') == true ]]
}

launch_app() {
  mark_log
  act open "$app"
  wait_log "Accessibility granted: (true|false)" 10
}

quit_app() {
  if $dry_run; then
    printf '    would run: osascript -e %s (if it runs)\n' "'tell application \"DrowsyDock\" to quit'"
    return 0
  fi
  app_running || return 0
  osascript -e 'tell application "DrowsyDock" to quit'
  local waited=0
  while app_running && ((waited < 50)); do
    sleep 0.1
    waited=$((waited + 1))
  done
}

read_dock() {
  if $dry_run; then
    printf '    would run: %s dock\n' "$helper"
    dock_orientation=bottom dock_hidden=false dock_background=0,0,0,0 dock_perch=0,0,64,80
    dock_capture=0,0,0,0 dock_scale=2 dock_primary_height=0 dock_last_icon=0,0,0,0
    dock_first_icon=0,0,0,0 dock_screen=0,0,0,0 dock_facing=left
    return 0
  fi
  local output key value
  output="$("$helper" dock)" || return 1
  while IFS='=' read -r key value; do
    printf -v "dock_${key//-/_}" '%s' "$value"
  done <<<"$output"
}

field() { cut -d, -f"$2" <<<"$1"; }
mid_x() { awk -F, '{print $1 + $3 / 2}' <<<"$1"; }
mid_y() { awk -F, '{print $2 + $4 / 2}' <<<"$1"; }

pointer_away() {
  read_dock || return 1
  act "$helper" move-pointer "$(mid_x "$dock_screen")" "$(awk -F, '{print $2 + $4 * 0.6}' <<<"$dock_screen")"
}

pointer_to() {
  act "$helper" move-pointer "$1" "$2"
}

capture() {
  local region
  if $dry_run; then
    printf '    would run: screencapture -x -R <the Dock and the perch> %s/%s.png\n' "$qa_dir" "$1"
    return 0
  fi
  region="$(awk -F, -v h="$dock_primary_height" '{printf "%d,%d,%d,%d", $1, h - $2 - $4, $3, $4}' <<<"$dock_capture")"
  screencapture -x -R "$region" "$qa_dir/$1.png"
}

# MARK: - Preflight

preflight() {
  step "Preflight"
  say "Checking for the tools it uses."
  local tool
  for tool in osascript screencapture defaults log sample top pmset plutil swift git; do
    command -v "$tool" >/dev/null || {
      say "Missing $tool." >&2
      exit 1
    }
  done

  $needs_app || return 0

  say "The app must be a fresh bundle from main."
  if ! $dry_run; then
    if [[ $(git rev-parse --abbrev-ref HEAD) != main ]]; then
      say "Check out main and run scripts/bundle.sh first (on $(git rev-parse --abbrev-ref HEAD))." >&2
      exit 1
    fi
    if [[ -n $(git status --porcelain -- Sources Resources Package.swift scripts/bundle.sh) ]]; then
      say "Sources have uncommitted changes; commit or stash them, then run scripts/bundle.sh." >&2
      exit 1
    fi
    if [[ ! -x $app/Contents/MacOS/DrowsyDock ]] ||
      (($(stat -f %m "$app/Contents/MacOS/DrowsyDock") < $(git log -1 --format=%ct))); then
      say "build/DrowsyDock.app is missing or older than the last commit; run scripts/bundle.sh." >&2
      exit 1
    fi
  fi

  say "Building the helper (it is never part of the app bundle)."
  act swift build -c release --product qa-helper

  say "Your terminal needs Accessibility (pointer moves, the menu) and Screen Recording (screenshots)."
  if ! $dry_run; then
    local permissions
    permissions="$("$helper" permissions)"
    if ! grep -q 'accessibility=true' <<<"$permissions"; then
      say "Grant your terminal Accessibility in System Settings ▸ Privacy & Security, then run again." >&2
      exit 1
    fi
    if ! grep -q 'screen-recording=true' <<<"$permissions"; then
      say "Grant your terminal Screen Recording in System Settings ▸ Privacy & Security, then run again." >&2
      exit 1
    fi
  fi

  say "Reading the app's log."
  act mkdir -p "$qa_dir"
  if ! $dry_run; then
    : >"$app_log"
    log stream --style compact --level debug --predicate "subsystem == \"$subsystem\"" >>"$app_log" 2>&1 &
    log_pid=$!
    sleep 2
  else
    printf '    would run: log stream --level debug --predicate %s >%s &\n' "'subsystem == \"$subsystem\"'" "$app_log"
  fi

  say "DrowsyDock needs its Accessibility grant: relaunching it to read the grant from its log."
  quit_app
  if ! launch_app; then
    say "DrowsyDock logged no 'Accessibility granted:' line within 10 s." >&2
    exit 1
  fi
  if ! $dry_run && ! last_log "Accessibility granted:" | grep -q true; then
    say "DrowsyDock lacks the Accessibility grant. Grant it (docs/manual-qa.md, section 4), then run again." >&2
    exit 1
  fi
}

# MARK: - Scenarios

scenario_restore_selftest() {
  step "restore-selftest: save, change nothing, restore"
  restore_dock
  if ! $dry_run; then
    check - restore-selftest "the backup is gone and nothing was left changed" test ! -f "$backup"
  fi
  save_dock_backup
}

scenario_launch() {
  step "launch (QA 1.1 to 1.3, 7.0)"
  check 1.1 launch "the app runs" app_running
  check 7.0 launch "the app observes the Dock list for AXCreated and AXUIElementDestroyed" \
    wait_log 'Observing the Dock list for: .*AXCreated.*AXUIElementDestroyed' 3
  check 1.1 launch "the bundle is a menu-bar app (LSUIElement), so no Dock icon or Cmd-Tab entry" \
    test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$app/Contents/Info.plist" 2>/dev/null)" = true
  check 1.1 launch "the menu-bar item exists" menu_bar_item_exists
  menu "Quit DrowsyDock"
  pause 2
  check 1.2 launch "Quit DrowsyDock ends the app" bash -c '! pgrep -x DrowsyDock >/dev/null'
  launch_app
  act osascript -e 'tell application "System Events" to tell process "DrowsyDock" to click menu bar item 1 of last menu bar' \
    -e 'delay 0.3' -e 'tell application "System Events" to keystroke "q" using command down'
  pause 2
  check 1.3 launch "Cmd-Q with the menu open ends the app" bash -c '! pgrep -x DrowsyDock >/dev/null'
  launch_app
}

scenario_battery() {
  step "battery (QA 3.0, 3.1)"
  simulate Real
  quit_app
  launch_app
  check 3.0 battery "the log shows 'Started: … (real)'" wait_log "Started: .* \\(real\\)" 5
  if $dry_run; then
    say "    would compare the menu's first line with pmset -g batt"
    return
  fi
  local line percent
  line="$(menu_first_line)"
  percent="$(pmset -g batt | grep -Eo '[0-9]+%' | head -n 1)"
  if [[ -z $percent ]]; then
    result SKIP 3.1 battery "no battery (pmset shows none); QA 3.8 covers this Mac"
  elif [[ $line == "$percent"* ]]; then
    result PASS 3.1 battery "menu '$line' matches pmset $percent"
  else
    result FAIL 3.1 battery "menu '$line' but pmset says $percent"
  fi
}

expect_line() {
  mark_log
  simulate "$1"
  check "$3" levels "$1 shows '$2'" wait_log "Changed: $2 \\(" 3
}

scenario_levels() {
  step "levels (QA 3.9 to 3.16)"
  simulate Real
  local order
  for order in "80 40 25 15 5" "5 15 25 40 80"; do
    simulate "No battery"
    local percent state
    for percent in $order; do
      case $percent in
        80) state="Awake" ;;
        40) state="Drowsy" ;;
        25) state="Yawning" ;;
        15) state="Nodding off" ;;
        5) state="Asleep" ;;
      esac
      expect_line "$percent%" "$percent% · Discharging · $state" "3.9 to 3.13"
    done
  done
  simulate 5%
  pause 1
  mark_log
  simulate Charging
  check 3.14 levels "Charging shows Waking" wait_log "Changed: 5% · Charging · Waking" 3
  check 3.14 levels "then Awake about 3 s later" wait_log "Changed: 5% · Charging · Awake" 5
  expect_line "No battery" "No battery detected" 3.15
  simulate 5%
  pause 1
  mark_log
  simulate Real
  check 3.16 levels "Real shows the real battery again, not Asleep" \
    wait_log "Changed: .* \\(real\\)" 3
}

expect_overlay() {
  check "$3" "$4" "$5" wait_log "Overlay: $1" "$2"
}

scenario_position() {
  step "position (QA 5.1, 5.2, 7.1, 8.9, 11.5)"
  pointer_away
  local side
  for side in left right bottom; do
    mark_log
    dock_set orientation -string "$side"
    expect_overlay shown 8 "7.1" position "the cat returns at the $side Dock's perch"
    read_dock
    check "5.1 5.2" position "Accessibility reads a $side Dock" test "$dock_orientation" = "$side"
    mark_log
    menu Debug "Log Dock geometry"
    check "5.1 5.2" position "Log Dock geometry logs orientation $side" \
      wait_log "Dock geometry: .*orientation: .*$side" 3
    if [[ $side != bottom ]]; then
      local facing=right
      [[ $side == right ]] && facing=left
      check 8.9 position "on a $side Dock the cat faces $facing" test "$dock_facing" = "$facing"
      simulate Charging
      pause 4
      mark_log
      simulate 5%
      check 11.5 position "the wave plays on a $side Dock" wait_log "The whole Dock nods off" 3
      pause 5
      align_checks "8.9" "$side Dock"
      simulate 80%
    fi
  done
}

scenario_size() {
  step "size (QA 7.2)"
  pointer_away
  local size
  for size in 36 64; do
    mark_log
    dock_set tilesize -int "$size"
    expect_overlay shown 8 7.2 size "the cat follows a Dock at tile size $size"
    if ! $dry_run; then
      read_dock
      local logged
      logged="$(last_log "Overlay: shown")"
      check 7.2 size "the logged perch is the perch Accessibility gives" \
        grep -q "x: $(field "$dock_perch" 1)" <<<"$logged"
    fi
  done
}

scenario_autohide() {
  step "autohide (QA 5.4, 7.4, 11.6)"
  simulate 80%
  mark_log
  dock_set autohide -bool true
  pointer_away
  expect_overlay hidden 5 7.4 autohide "the cat hides with the Dock"
  mark_log
  menu Debug "Log Dock geometry"
  check 5.4 autohide "Log Dock geometry logs hidden: true" wait_log "hidden: true" 3
  pointer_away
  simulate Charging
  pause 4
  mark_log
  simulate 5%
  check 11.6 autohide "falling asleep with the Dock hidden logs that the overlay isn't showing" \
    wait_log "would nod off, but the overlay isn't showing" 3
  mark_log
  dock_set autohide -bool false
  expect_overlay shown 8 7.4 autohide "the cat returns when auto-hide is off"
  mark_log
  simulate 15%
  simulate 5%
  pause 2
  check 11.6 autohide "no wave until the next charge" no_log_since_mark "The whole Dock nods off"
  simulate 80%
}

scenario_hover() {
  step "hover (QA 7.5b, 8.11, 9.8)"
  dock_set magnification -bool false
  simulate 80%
  pointer_away
  read_dock
  mark_log
  pointer_to "$(mid_x "$dock_last_icon")" "$(mid_y "$dock_last_icon")"
  expect_overlay fadedOut 2 8.11 hover "resting on the last icon fades the cat"
  mark_log
  pointer_to "$(mid_x "$dock_first_icon")" "$(mid_y "$dock_first_icon")"
  expect_overlay shown 3 8.11 hover "another icon brings it back"
  mark_log
  pause 2
  check 7.5b hover "with magnification off, resting on another icon never fades the cat" \
    no_log_since_mark "Overlay: fadedOut"
  simulate 5%
  pause 5
  pointer_to "$(mid_x "$dock_last_icon")" "$(mid_y "$dock_last_icon")"
  pause 1
  act sample DrowsyDock 3 -file "$qa_dir/hover-faded.txt"
  check 9.8 hover "while faded at 5% the sample shows no drawing" \
    bash -c "! grep -Eq 'drawFrame|SKCRenderer' '$qa_dir/hover-faded.txt'"
  pointer_away
  pause 2
  act sample DrowsyDock 3 -file "$qa_dir/hover-shown.txt"
  check 9.8 hover "after the pointer leaves the snore draws again" \
    grep -Eq 'drawFrame' "$qa_dir/hover-shown.txt"
  simulate 80%
}

scenario_magnification() {
  step "magnification (QA 7.5, 7.5a, 8.12)"
  dock_set magnification -bool true
  dock_set largesize -int 128
  simulate 5%
  pause 5
  read_dock
  mark_log
  pointer_to "$(mid_x "$dock_first_icon")" "$(mid_y "$dock_first_icon")"
  expect_overlay fadedOut 2 "7.5 8.12" magnification "magnifying the Dock fades the cat and the veil"
  mark_log
  pointer_away
  expect_overlay shown 3 "7.5 8.12" magnification "they return within 1 s of the Dock settling"
  pointer_to "$(mid_x "$dock_first_icon")" "$(mid_y "$dock_first_icon")"
  pause 2
  mark_log
  pointer_to "$(mid_x "$dock_first_icon")" "$(awk -F, '{print $2 + $4 + 60}' <<<"$dock_first_icon")"
  expect_overlay shown 3 7.5a magnification "just above the icons the cat returns from the frame check"
  pointer_away
  dock_set magnification -bool false
  simulate 80%
}

scenario_relaunch() {
  step "relaunch (QA 7.8, 7.8a, 7.8b)"
  pointer_away
  mark_log
  act killall Dock
  check 7.8 relaunch "the log shows 'The Dock relaunched'" wait_log "The Dock relaunched" 10
  expect_overlay shown 10 7.8 relaunch "the cat returns once the Dock's icons are back"
  check 7.8a relaunch "the observer is installed on the new Dock" \
    wait_log "Observing the Dock list for:" 10
  pause 2
  mark_log
  act open -g -a Calculator
  pause 4
  act osascript -e 'tell application "Calculator" to quit'
  pause 3
  check 7.8b relaunch "an app's icon coming and going isn't taken for the list's destruction" \
    no_log_since_mark "The Dock list was destroyed|Observing the Dock list for:"
}

align_checks() {
  local rows="$1" label="$2"
  pointer_away
  read_dock
  simulate "No battery"
  pause 2
  capture bare
  simulate 80%
  pause 3
  capture awake
  simulate 5%
  pause 6
  capture asleep
  if $dry_run; then
    printf '    would run: %s align …\n' "$helper"
    printf '    would check: the Dock rim, the veil and the paws within 1 pt of the AX frames (QA %s)\n' "$rows"
    return
  fi
  local line
  while IFS= read -r line; do
    result "${line%% *}" "$rows" "align, $label" "${line#* }"
  done < <("$helper" align orientation="$dock_orientation" scale="$dock_scale" \
    capture="$dock_capture" background="$dock_background" perch="$dock_perch" \
    bare="$qa_dir/bare.png" awake="$qa_dir/awake.png" asleep="$qa_dir/asleep.png")
}

scenario_align() {
  step "align (QA 8.5, 8.15)"
  align_checks "8.5 8.15" "bottom Dock"
  simulate 80%
}

cpu_average() {
  top -l "$(($1 + 1))" -s 1 -stats cpu -pid "$(pgrep -x DrowsyDock)" |
    awk 'NR>1 && /^[0-9.]+[[:space:]]*$/ {s+=$1; n++} END {printf "%.2f", s/n}'
}

cpu_check() {
  local choice="$1" budget="$2" rows="$3" average
  simulate "$choice"
  pointer_away
  say "Hands off the pointer and the menu for 70 s ($choice)."
  pause 10
  if $dry_run; then
    printf '    would run: top -l 61 -s 1 -stats cpu -pid $(pgrep -x DrowsyDock) and average it\n'
    printf '    would check: the average is at most %s%% (QA %s)\n' "$budget" "$rows"
    return
  fi
  average="$(cpu_average 60)"
  if awk -v a="$average" -v b="$budget" 'BEGIN { exit !(a <= b) }'; then
    result PASS "$rows" cpu "$choice: $average% (budget $budget%)"
  else
    result FAIL "$rows" cpu "$choice: $average% (budget $budget%; exception E1 in CONSTRAINTS.md records the last overage)"
  fi
}

scenario_cpu() {
  step "cpu (QA 7.9, 9.6, 9.7)"
  cpu_check 80% 1.0 "7.9 9.6"
  cpu_check 15% 3.0 9.7
  cpu_check 5% 3.0 9.7
  simulate 80%
}

sample_idle() {
  local name="$1" rows="$2" detail="$3"
  pointer_away
  pause 10
  act sample DrowsyDock 5 -file "$qa_dir/$name.txt"
  check "$rows" idle-sample "$detail: no timer fires" \
    bash -c "! grep -q '__CFRUNLOOP_IS_CALLING_OUT_TO_A_TIMER_CALLBACK_FUNCTION__' '$qa_dir/$name.txt'"
  check "$rows" idle-sample "$detail: nothing draws" \
    bash -c "! grep -Eq 'drawFrame|SKCRenderer' '$qa_dir/$name.txt'"
  check "$rows" idle-sample "$detail: the main thread waits in mach_msg" \
    grep -q mach_msg "$qa_dir/$name.txt"
}

scenario_idle_sample() {
  step "idle-sample (QA 3.7, 7.6, 8.13)"
  simulate 80%
  sample_idle idle-awake "3.7 7.6 8.13" "awake"
  simulate 5%
  pause 6
  simulate 80%
  sample_idle idle-after-snore 8.13 "after the snore, the crossfade and the veil's fade"
}

# MARK: - Main

selected() {
  [[ -z $only ]] && return 0
  [[ ",$only," == *",$1,"* ]]
}

if [[ -n $only ]]; then
  for name in ${only//,/ }; do
    known=false
    for entry in "${scenarios[@]}"; do
      [[ ${entry%%|*} == "$name" ]] && known=true
    done
    $known || {
      say "Unknown scenario '$name'. Scenarios:" >&2
      list >&2
      exit 2
    }
  done
fi

if $dry_run; then
  say "Dry run: nothing is launched, moved, captured or changed."
  say "Scenarios:"
  list
fi

for entry in "${scenarios[@]}"; do
  name="${entry%%|*}"
  if selected "$name" && [[ $name != restore-selftest ]]; then needs_app=true; fi
done

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

preflight
save_dock_backup

for entry in "${scenarios[@]}"; do
  name="${entry%%|*}"
  selected "$name" || continue
  "scenario_${name//-/_}"
done

if $needs_app; then
  step "Back to the real battery"
  simulate Real
fi

$failed && exit 1
exit 0
