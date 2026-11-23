# MARK: - Settings

live_settings=(root dry_run qa_dir report run_log app app_binary helper dock_backup run_pid_file
  results owns_backup app_log keep_captures)

# The functions below read these globals. A caller sets them all, then runs this.
require_live_settings() {
  local name
  for name in "${live_settings[@]}"; do
    if ! declare -p "$name" >/dev/null 2>&1; then
      echo "live-functions.sh: set $name before calling require_live_settings" >&2
      exit 2
    fi
  done
}

# MARK: - Output

# shellcheck source=scripts/lib.sh
source "${BASH_SOURCE[0]%/*}/../lib.sh"

say() { printf '%s\n' "$*"; }

run_or_print() {
  if $dry_run; then
    printf '    would run:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

qa_helper() {
  if $dry_run; then
    printf '    UNGUARDED: qa-helper %s\n' "$*"
    return 0
  fi
  "$helper" "$@"
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
    return 1
  fi
}

write_report() {
  $dry_run && return
  mkdir -p "$qa_dir"
  {
    echo "# Live QA report"
    echo
    echo "$(date '+%Y-%m-%d %H:%M'), branch $(git rev-parse --abbrev-ref HEAD) at $(git rev-parse --short HEAD), macOS $(sw_vers -productVersion)"
    echo
    echo "| Result | QA rows | Scenario | Detail |"
    echo "|---|---|---|---|"
    local entry verdict rows scenario detail
    # Bash 3.2 treats an empty array as unbound under set -u, so guard the expansion.
    for entry in ${results[@]+"${results[@]}"}; do
      IFS='|' read -r verdict rows scenario detail <<<"$entry"
      echo "| $verdict | $rows | $scenario | ${detail//|/\\|} |"
    done
  } >"$report"
  say "Report: $report"
}

# MARK: - Dock preferences

# Changes one Dock preference the way System Settings does, through System Events, so the Dock
# keeps running and the app sees the change through com.apple.dock.prefchanged and Accessibility.
dock_preference() {
  # Both words go into AppleScript as written, so only these properties and values may.
  case "$1" in
    "screen edge") [[ $2 == left || $2 == right || $2 == bottom ]] ;;
    autohide | magnification) [[ $2 == true || $2 == false ]] ;;
    "dock size" | "magnification size") [[ $2 =~ ^(0?\.[0-9]+|1\.0)$ ]] ;;
    *) false ;;
  esac || {
    result FAIL - dock "refused to set the Dock's $1 to $2: not a property and value this script sets"
    return 1
  }
  if $dry_run; then
    run_or_print osascript -e \
      "tell application \"System Events\" to tell dock preferences to set $1 to $2"
    return
  fi
  local error
  if ! error="$(osascript -e "with timeout of 10 seconds" \
    -e "tell application \"System Events\" to tell dock preferences to set $1 to $2" \
    -e "end timeout" 2>&1 >/dev/null)"; then
    result FAIL - dock "System Events couldn't set the Dock's $1 to $2: $error"
    return 1
  fi
}

take_dock_backup() {
  step "Saving the Dock's preferences"
  if $dry_run; then
    printf '    would run: defaults export com.apple.dock %s, then check it parses and matches\n' \
      "$dock_backup"
  elif ! save_dock_backup; then
    say "Couldn't save and verify the Dock's preferences at $dock_backup; changing nothing." >&2
    exit 1
  fi
  owns_backup=true
  say "If this run is killed, restore the Dock with:"
  say "  cd $(printf '%q' "$root") && scripts/qa-live.sh --restore --yes"
  say "or, without this script:"
  say "  $(dock_restore_command)"
}

# Restores the Dock's preferences if this run saved them. Returns 1 when the restore can't be
# verified, or when the backup this run saved has gone; the backup is then kept, if it exists, and
# the command to retry printed.
put_dock_back() {
  $owns_backup || return 0
  if $dry_run; then
    printf '    would restore the Dock from %s and delete the backup once it matches\n' "$dock_backup"
    return 0
  fi
  if [[ ! -f $dock_backup ]]; then
    say "The backup this run saved at $dock_backup disappeared; the Dock wasn't restored." >&2
    return 1
  fi
  restore_dock
}

other_run_pid() {
  [[ -f $run_pid_file ]] || return 1
  local pid
  pid="$(cat "$run_pid_file")"
  [[ $pid =~ ^[0-9]+$ && $pid != "$$" ]] || return 1
  ps -o command= -p "$pid" 2>/dev/null | grep -q 'qa-live\.sh' || return 1
  printf '%s\n' "$pid"
}

# Restores the Dock first, since that is what matters; the relaunch after it only stops the QA log,
# and quit_app gives up after 5 s. Signals are ignored from here on, so a second Ctrl-C can't cut
# the restore short.
cleanup() {
  local status=$?
  trap '' INT TERM HUP
  trap - EXIT
  if ! put_dock_back; then
    result FAIL - dock "the Dock's preferences couldn't be restored; see the message above"
    status=1
  fi
  if ! $dry_run; then
    if app_running && ! relaunch_without_qa_log; then status=1; fi
    save_run_log
  fi
  write_report
  if ! $dry_run && [[ $(cat "$run_pid_file" 2>/dev/null) == "$$" ]]; then
    rm -f "$run_pid_file"
  fi
  exit "$status"
}

restore_from_backup() {
  if [[ ! -f $dock_backup ]]; then
    say "No backup at $dock_backup; nothing to restore."
    return 0
  fi
  local pid
  if pid="$(other_run_pid)"; then
    say "qa-live.sh is still running (pid $pid) and owns this backup; it restores the Dock when it ends." >&2
    return 1
  fi
  say "Backup saved $(stat -f '%Sm' "$dock_backup")."
  local scratch
  scratch="$(mktemp -d)"
  defaults export com.apple.dock "$scratch/live.plist"
  if [[ -x $helper ]]; then
    say "Restoring it changes these keys of the Dock's preferences:"
    "$helper" preferences-change "$scratch/live.plist" "$dock_backup" | sed 's/^/  /'
  fi
  local lines
  lines="$(diff <(plutil -convert xml1 -o - "$scratch/live.plist") \
    <(plutil -convert xml1 -o - "$dock_backup") | grep -E '^[<>]' | sed 's/^</  -/; s/^>/  +/')"
  rm -rf "$scratch"
  say "The lines that change (- now, + backup):"
  printf '%s\n' "$lines" | head -n 40
  local total
  total="$(printf '%s\n' "$lines" | grep -c .)"
  if ((total > 40)); then
    say "  … and $((total - 40)) more lines."
  fi
  if ! $assume_yes; then
    local answer
    read -r -p "Restore the Dock's preferences from this backup? [y/N] " answer
    [[ $answer == y || $answer == Y ]] || {
      say "Left as it is; the backup is kept."
      return 1
    }
  fi
  restore_dock
}

# MARK: - Waiting and the app's log

pause() {
  if $dry_run; then
    printf '    would wait %s s\n' "$1"
    return
  fi
  sleep "$1"
}

# The app's lines the scenarios wait for, as grep -E patterns. QALogMessageTests checks each one
# against the line the app logs, so the two can't drift apart.
log_granted='Accessibility granted: (true|false)'
log_started_real='Started: .* \(real\)'
log_changed='Changed: '
log_changed_real='Changed: .* \(real\)'
log_overlay='Overlay: '
log_dock_geometry='Dock geometry: .*orientation: '
log_dock_hidden='hidden: true'
log_wave='The whole Dock nods off'
log_wave_without_overlay='would nod off, but the overlay isn.t showing'
log_observing_list='Observing the Dock list for:'
log_observing_create_and_destroy='Observing the Dock list for: .*AXCreated.*AXUIElementDestroyed'
log_dock_relaunched='The Dock relaunched'
log_list_destroyed='The Dock list was destroyed'

app_log_opened=false
run_start=0
log_mark=0
app_log_pid=""

# The app's QA log, under the home folder in the account record (id -P), where the app's getpwuid
# finds it too; HOME doesn't move it.
qa_log_path() {
  printf '%s/Library/Logs/DrowsyDock/qa.log\n' "$(id -P | cut -d: -f9)"
}

app_log_size() {
  if [[ -f $app_log ]]; then stat -f %z "$app_log"; else echo 0; fi
}

open_app_log() {
  if $dry_run; then
    printf '    would read the lines DrowsyDock appends to %s from here on\n' "$app_log"
    return
  fi
  run_start="$(app_log_size)"
  log_mark="$run_start"
  app_log_opened=true
}

# Prints the QA log from byte offset $1. Once the app has started the file over at its size limit,
# the file is shorter than the offset and all of it is newer.
app_log_from() {
  local from="$1"
  if (($(app_log_size) < from)); then from=0; fi
  tail -c "+$((from + 1))" "$app_log"
}

app_log_lines() {
  local from="$run_start"
  if [[ ${1:-} == since-mark ]]; then from="$log_mark"; fi
  [[ -f $app_log ]] || return 0
  app_log_from "$from" | grep -F -- " DrowsyDock[$app_log_pid] "
}

mark_log() {
  $dry_run && return
  log_mark="$(app_log_size)"
}

# grep reads every line instead of stopping at the first match (-q), so the reads before it in the
# pipe can't die of SIGPIPE and fail the pipeline under pipefail.
logged_since_mark() {
  [[ -n $(app_log_lines since-mark | grep -E -- "$1") ]]
}

app_alive() {
  [[ -n $app_log_pid ]] && kill -0 "$app_log_pid" 2>/dev/null
}

wait_log() {
  local pattern="$1" seconds="$2" waited=0
  if $dry_run; then
    printf '    would wait up to %s s for a log line matching: %s\n' "$seconds" "$pattern"
    return 0
  fi
  while ((waited < seconds * 10)); do
    if logged_since_mark "$pattern"; then return 0; fi
    app_alive || return 1
    sleep 0.1
    waited=$((waited + 1))
  done
  return 1
}

last_log() {
  app_log_lines since-mark | grep -E -- "$1" | tail -n 1
}

app_runs_with_no_log_since_mark() {
  app_alive || return 1
  ! logged_since_mark "$1"
}

save_run_log() {
  $app_log_opened && [[ -f $app_log ]] || return 0
  mkdir -p "$qa_dir"
  app_log_from "$run_start" >"$run_log"
}

# MARK: - Driving the app

menu() {
  if $dry_run; then
    printf '    would click in the menu: %s\n' "$(printf '%s ▸ ' "$@" | sed 's/ ▸ $//')"
    return 0
  fi
  osascript - "$@" >/dev/null <<'APPLESCRIPT'
on run itemPath
  with timeout of 10 seconds
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
  end timeout
end run
APPLESCRIPT
}

simulate() {
  menu Debug "Simulate battery" "$1"
}

start_from_no_battery() {
  simulate "No battery"
}

menu_first_line() {
  osascript <<'APPLESCRIPT'
with timeout of 10 seconds
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
end timeout
APPLESCRIPT
}

app_pid() {
  local pid
  for pid in $(pgrep -x DrowsyDock); do
    if [[ $(ps -o comm= -p "$pid") == "$app_binary" ]]; then
      printf '%s\n' "$pid"
      return 0
    fi
  done
  return 1
}

app_running() { [[ -n $(app_pid) ]]; }

app_stopped() { ! app_running; }

# Opens the menu and presses Cmd-Q only once the menu is open, so the key never reaches the
# terminal or whatever app is in front.
cmd_q_with_menu_open() {
  osascript <<'APPLESCRIPT'
with timeout of 10 seconds
  tell application "System Events"
    tell process "DrowsyDock"
      set barItem to menu bar item 1 of last menu bar
      click barItem
      delay 0.3
      if not (exists menu 1 of barItem) then return "no menu"
      keystroke "q" using command down
      return "sent"
    end tell
  end tell
end timeout
APPLESCRIPT
}

menu_bar_item_exists() {
  [[ $(osascript -e 'with timeout of 10 seconds' \
    -e 'tell application "System Events" to exists menu bar item 1 of last menu bar of process "DrowsyDock"' \
    -e 'end timeout') == true ]]
}

launch_app() {
  mark_log
  run_or_print open "$app" --args --qa-log
  if ! $dry_run; then
    app_log_pid="$(wait_for_app_pid)" || return 1
  fi
  wait_log "$log_granted" 10
}

# Prints the pid of this build's DrowsyDock once it runs, within 10 s.
wait_for_app_pid() {
  local waited=0
  while ((waited < 100)); do
    app_pid && return 0
    sleep 0.1
    waited=$((waited + 1))
  done
  return 1
}

# Opening the app while it still runs would only bring the --qa-log copy forward.
relaunch_without_qa_log() {
  quit_app
  if app_running; then
    result FAIL - cleanup \
      "DrowsyDock (pid $(app_pid)) didn't quit within 5 s, so it may still write the QA log; quit it"
    return 1
  fi
  open "$app"
}

quit_app() {
  if $dry_run; then
    printf '    would run: kill -TERM <the pid of %s> (if it runs)\n' "$app_binary"
    return 0
  fi
  app_running || return 0
  kill -TERM "$(app_pid)"
  local waited=0
  while app_running && ((waited < 50)); do
    sleep 0.1
    waited=$((waited + 1))
  done
}

read_dock() {
  if $dry_run; then
    printf '    would run: %s dock %s\n' "$helper" "$*"
    dock_orientation=bottom
    dock_background=0,0,0,0
    dock_screen=0,0,0,0
    dock_scale=2
    dock_first_icon=0,0,0,0
    dock_last_icon=0,0,0,0
    dock_perch=0,0,64,80
    dock_capture=0,0,0,0
    dock_capture_region=0,0,0,0
    return 0
  fi
  local output key value
  output="$(qa_helper dock "$@")" || return 1
  while IFS='=' read -r key value; do
    case $key in
      orientation) dock_orientation="$value" ;;
      background) dock_background="$value" ;;
      screen) dock_screen="$value" ;;
      scale) dock_scale="$value" ;;
      first-icon) dock_first_icon="$value" ;;
      last-icon) dock_last_icon="$value" ;;
      perch) dock_perch="$value" ;;
      capture) dock_capture="$value" ;;
      capture-region) dock_capture_region="$value" ;;
    esac
  done <<<"$output"
}

read_dock_and_logged_perch() {
  if $dry_run; then
    printf '    would read the perch from the newest "Overlay: shown" line in %s\n' "$app_log"
    dock_logged_perch=0,0,64,80
    read_dock sprite=64,80
    return 0
  fi
  local line
  line="$(app_log_lines | grep -E "${log_overlay}(shown|fadedOut)" | tail -n 1)"
  dock_logged_perch="$(qa_helper logged-perch "$line")" || return 1
  read_dock sprite="$(field "$dock_logged_perch" 3),$(field "$dock_logged_perch" 4)"
}

same_frame() {
  awk -F, -v a="$1" -v b="$2" 'BEGIN {
    split(a, p, ","); split(b, q, ",")
    for (i = 1; i <= 4; i++) if (p[i] - q[i] > 0.5 || q[i] - p[i] > 0.5) exit 1
  }'
}

field() { cut -d, -f"$2" <<<"$1"; }
mid_x() { awk -F, '{print $1 + $3 / 2}' <<<"$1"; }
mid_y() { awk -F, '{print $2 + $4 / 2}' <<<"$1"; }

pointer_away() {
  if ! read_dock; then
    result FAIL - pointer "couldn't read the Dock to move the pointer away from it"
    return 1
  fi
  run_or_print "$helper" move-pointer "$(mid_x "$dock_screen")" \
    "$(awk -F, '{print $2 + $4 * 0.6}' <<<"$dock_screen")"
}

pointer_to() {
  run_or_print "$helper" move-pointer "$1" "$2"
}

capture() {
  if $dry_run; then
    printf '    would run: screencapture -x -R <the Dock and the perch> %s/%s.png\n' "$qa_dir" "$1"
    return 0
  fi
  screencapture -x -R "$dock_capture_region" "$qa_dir/$1.png" && [[ -s $qa_dir/$1.png ]]
}

draw_symbols='drawFrame|displayLinkFired|SKCRenderer'
timer_symbols='__CFRUNLOOP_IS_CALLING_OUT_TO_A_TIMER_CALLBACK_FUNCTION__'

sample_app() {
  local pid
  if $dry_run; then
    printf '    would run: sample <the pid of %s> %s -file %s\n' "$app_binary" "$2" "$qa_dir/$1.txt"
    return 0
  fi
  rm -f "$qa_dir/$1.txt"
  pid="$(app_pid)"
  [[ -n $pid ]] && sample "$pid" "$2" -file "$qa_dir/$1.txt" >/dev/null 2>&1
}

sample_has() {
  [[ -s $qa_dir/$2.txt ]] && grep -Eq -- "$1" "$qa_dir/$2.txt"
}

sample_lacks() {
  [[ -s $qa_dir/$2.txt ]] && ! grep -Eq -- "$1" "$qa_dir/$2.txt"
}

# MARK: - Preflight

preflight() {
  step "Preflight"
  say "Checking for the tools it uses."
  local tool
  for tool in osascript screencapture defaults sample top pmset plutil swift git; do
    command -v "$tool" >/dev/null || {
      say "Missing $tool." >&2
      exit 1
    }
  done

  say "Building the helper (it is never part of the app bundle)."
  if ! run_or_print swift build -c release --product qa-helper; then
    say "qa-helper failed to build; see the swift build output above." >&2
    exit 1
  fi
  if ! $dry_run && [[ ! -x $helper ]]; then
    say "qa-helper isn't at $helper after the build." >&2
    exit 1
  fi

  preflight_app
}

preflight_app() {
  say "The app must be a fresh bundle of this checkout: clean sources, built after the last commit."
  if ! $dry_run; then
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

  say "Your terminal needs Accessibility (pointer moves, the menu) and Screen Recording (screenshots)."
  if ! $dry_run; then
    local permissions
    permissions="$(qa_helper permissions)"
    if ! grep -q 'accessibility=true' <<<"$permissions"; then
      say "Grant your terminal Accessibility in System Settings ▸ Privacy & Security, then run again." >&2
      exit 1
    fi
    if ! grep -q 'screen-recording=true' <<<"$permissions"; then
      say "Grant your terminal Screen Recording in System Settings ▸ Privacy & Security, then run again." >&2
      exit 1
    fi
  fi

  say "System Events must be allowed to change the Dock's preferences (Automation)."
  if ! $dry_run; then
    local probe
    if ! probe="$(osascript -e 'with timeout of 10 seconds' \
      -e 'tell application "System Events" to get screen edge of dock preferences' \
      -e 'end timeout' 2>&1)"; then
      say "System Events refused: $probe" >&2
      say "Allow your terminal to control System Events in System Settings ▸ Privacy & Security ▸ Automation, then run again." >&2
      exit 1
    fi
  fi

  say "Reading the lines DrowsyDock writes to its QA log when launched with --qa-log."
  run_or_print mkdir -p "$qa_dir"
  open_app_log

  if ! $dry_run; then
    local others
    others="$(pgrep -x DrowsyDock | grep -vx "$(app_pid)" || true)"
    if [[ -n $others ]]; then
      say "Another DrowsyDock is running (pid $others). Quit it, so the menu and the log belong to this build." >&2
      exit 1
    fi
  fi

  say "DrowsyDock needs its Accessibility grant: relaunching it to read the grant from its QA log."
  quit_app
  if ! $dry_run && app_running; then
    say "DrowsyDock (pid $(app_pid)) didn't quit within 5 s, so it can't be relaunched with --qa-log; quit it, then run again." >&2
    exit 1
  fi
  if ! launch_app; then
    say "DrowsyDock wrote no 'Accessibility granted:' line to $app_log within 10 s." >&2
    say "It refuses a link there, or a file or folder you don't own; remove it and run again." >&2
    exit 1
  fi
  if ! $dry_run && ! last_log "$log_granted" | grep -q true; then
    say "DrowsyDock lacks the Accessibility grant. Grant it (docs/manual-qa.md, section 4), then run again." >&2
    exit 1
  fi
}

# MARK: - Scenarios

scenario_launch() {
  step "launch (QA 1.1 to 1.3, 7.0)"
  check 1.1 launch "the app runs" app_running
  check 7.0 launch "the app observes the Dock list for AXCreated and AXUIElementDestroyed" \
    wait_log "$log_observing_create_and_destroy" 3
  check 1.1 launch "the bundle is a menu-bar app (LSUIElement), so no Dock icon or Cmd-Tab entry" \
    test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$app/Contents/Info.plist" 2>/dev/null)" = true
  check 1.1 launch "the menu-bar item exists" menu_bar_item_exists
  menu "Quit DrowsyDock"
  pause 2
  check 1.2 launch "Quit DrowsyDock ends the app" app_stopped
  launch_app
  if $dry_run; then
    printf '    would open the menu and, only if it opened, press Cmd-Q\n'
  elif [[ $(cmd_q_with_menu_open) != sent ]]; then
    result FAIL 1.3 launch "the menu didn't open, so Cmd-Q wasn't sent (it would reach another app)"
  fi
  pause 2
  check 1.3 launch "Cmd-Q with the menu open ends the app" app_stopped
  launch_app
}

scenario_battery() {
  step "battery (QA 3.0, 3.1)"
  simulate Real
  quit_app
  launch_app
  check 3.0 battery "the log shows 'Started: … (real)'" wait_log "$log_started_real" 5
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
  check "$3" levels "$1 shows '$2'" wait_log "$log_changed$2 \\(" 3
}

scenario_levels() {
  step "levels (QA 3.9 to 3.16)"
  simulate Real
  local order
  for order in "80 40 25 15 5" "5 15 25 40 80"; do
    start_from_no_battery
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
  check 3.14 levels "Charging shows Waking" wait_log "${log_changed}5% · Charging · Waking" 3
  check 3.14 levels "then Awake about 3 s later" wait_log "${log_changed}5% · Charging · Awake" 5
  expect_line "No battery" "No battery detected" 3.15
  simulate 5%
  pause 1
  mark_log
  simulate Real
  check 3.16 levels "Real shows the real battery again, not Asleep" \
    wait_log "$log_changed_real" 3
}

now() {
  qa_helper now
}

change_started=""
change_done=""

timed_change() {
  mark_log
  if $dry_run; then
    "$@"
    return
  fi
  change_started="$(now)"
  "$@"
  local status=$?
  change_done="$(now)"
  return "$status"
}

newest_overlay_line() {
  app_log_lines since-mark | grep -E "${log_overlay}(shown|fadedOut|hidden)" | tail -n 1
}

first_overlay_line() {
  local state="$1" line perch
  while IFS= read -r line; do
    if [[ $state != shown ]]; then
      printf '%s\n' "$line"
      return 0
    fi
    perch="$(qa_helper logged-perch "$line")" || continue
    if same_frame "$perch" "$dock_perch"; then
      printf '%s\n' "$line"
      return 0
    fi
  done < <(app_log_lines since-mark | grep -E "$log_overlay$state")
  return 1
}

expect_overlay_within() {
  local state="$1" budget="$2" rows="$3" scenario="$4" detail="$5"
  if $dry_run; then
    printf '    would check: %s within %s s, by the log timestamp (QA %s)\n' "$detail" "$budget" "$rows"
    return 0
  fi
  if [[ -z $change_started || -z $change_done ]]; then
    result FAIL "$rows" "$scenario" "$detail: the change wasn't timed"
    return 1
  fi
  if ! wait_log "$log_overlay$state" "$(awk -v b="$budget" 'BEGIN { print int(b + 4) }')"; then
    result FAIL "$rows" "$scenario" "$detail: no 'Overlay: $state' line"
    return 1
  fi
  sleep 1
  if [[ $state == shown ]] && ! read_dock_and_logged_perch; then
    result FAIL "$rows" "$scenario" "$detail: couldn't read the Dock or the logged perch"
    return 1
  fi
  local line logged newest
  if ! line="$(first_overlay_line "$state")"; then
    result FAIL "$rows" "$scenario" "$detail: no 'Overlay: $state' line at the Dock's perch"
    return 1
  fi
  newest="$(newest_overlay_line)"
  if [[ $newest != *"$log_overlay$state"* ]]; then
    result FAIL "$rows" "$scenario" "$detail: a later line undid it: ${newest##*"$log_overlay"}"
    return 1
  fi
  if ! logged="$(qa_helper log-time "$line")"; then
    result FAIL "$rows" "$scenario" "$detail: the log line has no timestamp"
    return 1
  fi
  local after before
  after="$(awk -v l="$logged" -v d="$change_done" 'BEGIN { printf "%.2f", l - d }')"
  before="$(awk -v l="$logged" -v s="$change_started" 'BEGIN { printf "%.2f", l - s }')"
  local timing="$after s after the change returned ($before s after it started; budget $budget s)"
  if awk -v l="$after" -v b="$budget" 'BEGIN { exit !(l <= b) }'; then
    result PASS "$rows" "$scenario" "$detail: $timing"
  else
    result FAIL "$rows" "$scenario" "$detail: $timing"
    return 1
  fi
}

expect_logged_perch_matches() {
  local rows="$1" scenario="$2" detail="$3"
  if $dry_run; then
    printf '    would check: %s (QA %s)\n' "$detail" "$rows"
    return 0
  fi
  if ! read_dock_and_logged_perch; then
    result FAIL "$rows" "$scenario" "$detail: couldn't read the logged perch or the Dock"
    return 1
  fi
  check "$rows" "$scenario" "$detail" same_frame "$dock_logged_perch" "$dock_perch"
}

expect_overlay() {
  check "$3" "$4" "$5" wait_log "$log_overlay$1" "$2"
}

scenario_position() {
  step "position (QA 5.1, 5.2, 7.1, 8.9, 11.5)"
  pointer_away
  local side
  for side in left right bottom; do
    timed_change dock_preference "screen edge" "$side"
    expect_overlay_within shown 1 7.1 position "the cat moves to the $side Dock's perch"
    expect_logged_perch_matches 7.1 position "the logged perch is the $side Dock's perch"
    read_dock
    check "5.1 5.2" position "Accessibility reads a $side Dock" test "$dock_orientation" = "$side"
    mark_log
    menu Debug "Log Dock geometry"
    check "5.1 5.2" position "Log Dock geometry logs orientation $side" \
      wait_log "$log_dock_geometry.*$side" 3
    if [[ $side != bottom ]]; then
      local facing=right
      [[ $side == right ]] && facing=left
      check 8.9 position "on a $side Dock the app's logged perch faces $facing" \
        logged_facing_is "$facing"
      simulate Charging
      pause 4
      mark_log
      simulate 5%
      check 11.5 position "the wave plays on a $side Dock" wait_log "$log_wave" 3
      pause 5
      align_checks "8.9" "$side Dock"
      simulate 80%
    fi
  done

  step "position, with the pointer on the Dock during the change (QA 7.1)"
  read_dock
  pointer_to "$(mid_x "$dock_first_icon")" "$(mid_y "$dock_first_icon")"
  pause 1
  timed_change dock_preference "screen edge" left
  expect_overlay_within shown 1 7.1 position "with the pointer on the Dock, the cat shows at the new perch"
  expect_logged_perch_matches 7.1 position "it isn't left faded at the old perch"
  pointer_away
  dock_preference "screen edge" bottom
  pause 3
}

logged_facing_is() {
  local line
  line="$(app_log_lines | grep -E "${log_overlay}(shown|fadedOut)" | tail -n 1)"
  [[ $(qa_helper logged-facing "$line") == "$1" ]]
}

scenario_size() {
  step "size (QA 7.2)"
  pointer_away
  local size
  for size in 0.2 0.5; do
    timed_change dock_preference "dock size" "$size"
    expect_overlay_within shown 1 7.2 size "the cat follows the Dock at size $size"
    expect_logged_perch_matches 7.2 size "the logged perch is the Dock's perch at size $size"
  done
}

scenario_autohide() {
  step "autohide (QA 5.4, 7.4, 11.6)"
  simulate 80%
  pointer_away
  timed_change dock_preference autohide true
  expect_overlay_within hidden 1 7.4 autohide "the cat hides with the Dock"
  mark_log
  menu Debug "Log Dock geometry"
  check 5.4 autohide "Log Dock geometry logs hidden: true" wait_log "$log_dock_hidden" 3
  pointer_away
  simulate Charging
  pause 4
  mark_log
  simulate 5%
  check 11.6 autohide "falling asleep with the Dock hidden logs that the overlay isn't showing" \
    wait_log "$log_wave_without_overlay" 3
  timed_change dock_preference autohide false
  expect_overlay_within shown 1 7.4 autohide "the cat returns when auto-hide is off"
  mark_log
  simulate 15%
  simulate 5%
  pause 2
  check 11.6 autohide "no wave until the next charge" \
    app_runs_with_no_log_since_mark "$log_wave"
  simulate 80%
}

scenario_hover() {
  step "hover (QA 7.5b, 8.11, 9.8)"
  dock_preference magnification false
  simulate 80%
  pointer_away
  pause 2
  if ! read_dock_and_logged_perch; then
    result FAIL 8.11 hover "couldn't read the logged perch or the Dock"
    return
  fi

  simulate "No battery"
  pointer_to "$(mid_x "$dock_last_icon")" "$(mid_y "$dock_last_icon")"
  pause 1
  capture_frame hover-bare "$dock_logged_perch"
  pointer_away
  simulate 80%
  pause 2

  timed_change pointer_to "$(mid_x "$dock_last_icon")" "$(mid_y "$dock_last_icon")"
  expect_overlay_within fadedOut 0.2 8.11 hover "resting on the last icon fades the cat"
  pause 0.5
  capture_frame hover-faded "$dock_logged_perch"
  check 8.11 hover "the faded cat leaves the perch as it looks with no cat (the label readable)" \
    screenshots_match hover-bare hover-faded && forget_captures hover-bare.png hover-faded.png
  mark_log
  pointer_to "$(mid_x "$dock_first_icon")" "$(mid_y "$dock_first_icon")"
  expect_overlay shown 3 8.11 hover "another icon brings it back"
  mark_log
  pause 2
  check 7.5b hover "with magnification off, resting on another icon never fades the cat" \
    app_runs_with_no_log_since_mark "${log_overlay}fadedOut"
  simulate 5%
  pause 5
  pointer_to "$(mid_x "$dock_last_icon")" "$(mid_y "$dock_last_icon")"
  pause 1
  sample_app hover-faded 3
  local passed=true
  check 9.8 hover "while faded at 5% the sample shows no drawing" \
    sample_lacks "$draw_symbols" hover-faded || passed=false
  pointer_away
  pause 2
  sample_app hover-shown 3
  check 9.8 hover "after the pointer leaves the snore draws again" \
    sample_has "$draw_symbols" hover-shown || passed=false
  $passed && forget_captures hover-faded.txt hover-shown.txt
  simulate 80%
}

scenario_magnification() {
  step "magnification (QA 7.5, 7.5a, 8.12)"
  dock_preference magnification true
  dock_preference "magnification size" 1.0
  simulate 5%
  pause 5
  read_dock
  timed_change pointer_to "$(mid_x "$dock_first_icon")" "$(mid_y "$dock_first_icon")"
  expect_overlay_within fadedOut 1 "7.5 8.12" magnification "magnifying the Dock fades the cat and the veil"
  timed_change pointer_away
  expect_overlay_within shown 1 "7.5 8.12" magnification "they return once the Dock settles"
  pointer_to "$(mid_x "$dock_first_icon")" "$(mid_y "$dock_first_icon")"
  pause 2
  timed_change pointer_to "$(mid_x "$dock_first_icon")" "$(awk -F, '{print $2 + $4 + 60}' <<<"$dock_first_icon")"
  expect_overlay_within shown 1 7.5a magnification "just above the icons the cat returns from the frame check"
  pointer_away
  dock_preference magnification false
  simulate 80%
}

scenario_relaunch() {
  step "relaunch (QA 7.8, 7.8a, 7.8b)"
  pointer_away
  mark_log
  run_or_print killall Dock
  check 7.8 relaunch "the log shows 'The Dock relaunched'" wait_log "$log_dock_relaunched" 10
  expect_overlay shown 10 7.8 relaunch "the cat returns once the Dock's icons are back"
  check 7.8a relaunch "the observer is installed on the new Dock" \
    wait_log "$log_observing_list" 10
  pause 2
  expect_logged_perch_matches 7.8a relaunch "after the relaunch the cat is at the new Dock's perch"
  if ! $dry_run && pgrep -x Calculator >/dev/null; then
    result SKIP 7.8b relaunch "Calculator is already open; the run doesn't quit an app you're using"
    return
  fi
  timed_change run_or_print open -g -a Calculator
  expect_overlay_within shown 1 "7.8a 7.8b" relaunch "the cat follows the last icon when an app's icon appears"
  pause 2
  expect_logged_perch_matches "7.8a 7.8b" relaunch "with Calculator's icon in the Dock, the perch is right"
  check 7.8b relaunch "an app's icon appearing isn't taken for the list's destruction" \
    app_runs_with_no_log_since_mark "$log_list_destroyed|$log_observing_list"
  timed_change run_or_print osascript -e 'tell application "Calculator" to quit'
  expect_overlay_within shown 1 "7.8a 7.8b" relaunch "the cat follows the last icon when it goes"
  pause 2
  expect_logged_perch_matches "7.8a 7.8b" relaunch "after Calculator quits, the perch is right"
  check 7.8b relaunch "an app's icon going isn't taken for the list's destruction" \
    app_runs_with_no_log_since_mark "$log_list_destroyed|$log_observing_list"
}

align_checks() {
  local rows="$1" label="$2"
  pointer_away
  if ! read_dock_and_logged_perch; then
    result FAIL "$rows" "align, $label" "couldn't read the perch the app logged or the Dock's frames"
    return
  fi
  local shot choice name wait
  for shot in "No battery|bare|2" "80%|awake|3" "5%|asleep|6"; do
    IFS='|' read -r choice name wait <<<"$shot"
    simulate "$choice"
    pause "$wait"
    if ! capture "$name"; then
      result FAIL "$rows" "align, $label" "the $name screenshot couldn't be taken"
      return
    fi
  done
  if $dry_run; then
    printf '    would run: %s align …\n' "$helper"
    printf '    would check: the Dock rim, the veil and the paws within 1 pt of the AX frames (QA %s)\n' "$rows"
    return
  fi
  local output status line align_failed=false
  output="$(qa_helper align orientation="$dock_orientation" scale="$dock_scale" \
    capture="$dock_capture" background="$dock_background" perch="$dock_logged_perch" \
    bare="$qa_dir/bare.png" awake="$qa_dir/awake.png" asleep="$qa_dir/asleep.png" \
    2>"$qa_dir/align.err")"
  status=$?
  if ((status > 1)) || [[ -z $output ]]; then
    result FAIL "$rows" "align, $label" "qa-helper align failed (exit $status): $(head -n 1 "$qa_dir/align.err")"
    return
  fi
  local line_rows
  while IFS= read -r line; do
    # Each check's name ends with its QA rows: "PASS paws on the Dock's top edge (8.15 6.1): …".
    line_rows="${line%%):*}"
    line_rows="${line_rows##*(}"
    [[ $line == *"):"* ]] || line_rows="$rows"
    result "${line%% *}" "$line_rows" "align, $label" "${line#* }"
    [[ $line == FAIL* ]] && align_failed=true
  done <<<"$output"
  $align_failed || forget_captures bare.png awake.png asleep.png align.err
}

forget_captures() {
  $dry_run && return
  $keep_captures && return
  local file
  for file in "$@"; do
    rm -f "$qa_dir/$file"
  done
}

scenario_align() {
  step "align (QA 5.5, 6.1, 8.5, 8.15)"
  read_dock
  if [[ $dock_orientation == bottom ]]; then
    expect_perch_on_last_icon
  else
    result SKIP "5.5 6.1" align "the Dock is on the $dock_orientation; 5.5's perch is a bottom Dock's"
  fi
  align_checks "8.5 8.15" "$dock_orientation Dock"
  simulate 80%
}

expect_perch_on_last_icon() {
  if $dry_run; then
    printf '    would check: the logged perch is 64 x 80, on the background, at the last icon (QA 5.5)\n'
    return
  fi
  if ! read_dock_and_logged_perch; then
    result FAIL "5.5 6.1" align "couldn't read the logged perch or the Dock"
    return
  fi
  check "5.5 6.1" align "the perch is 64 x 80 points" \
    test "$(field "$dock_logged_perch" 3),$(field "$dock_logged_perch" 4)" = "64.0,80.0"
  check "5.5 6.1" align "the perch's right edge is the last icon's" \
    near "$(frame_edge "$dock_logged_perch" maxX)" "$(frame_edge "$dock_last_icon" maxX)"
  check "5.5 6.1" align "the perch's bottom edge is the background's top edge" \
    near "$(frame_edge "$dock_logged_perch" minY)" "$(frame_edge "$dock_background" maxY)"
}

frame_edge() {
  awk -F, -v edge="$2" '{
    if (edge == "maxX") print $1 + $3; else if (edge == "minY") print $2; else print $2 + $4
  }' <<<"$1"
}

near() {
  awk -v a="$1" -v b="$2" 'BEGIN { exit !(a - b <= 0.5 && b - a <= 0.5) }'
}

capture_frame() {
  if $dry_run; then
    printf '    would run: screencapture -x -R <%s> %s/%s.png\n' "$2" "$qa_dir" "$1"
    return 0
  fi
  local region
  region="$(qa_helper region "$2")" || return 1
  screencapture -x -R "$region" "$qa_dir/$1.png" && [[ -s $qa_dir/$1.png ]]
}

screenshots_match() {
  local counts differing total
  counts="$(qa_helper differing-pixels "$qa_dir/$1.png" "$qa_dir/$2.png")" || return 1
  read -r differing total <<<"$counts"
  ((total > 0 && differing * 100 <= total))
}

cpu_average() {
  local pid
  pid="$(app_pid)"
  [[ -n $pid ]] || return 1
  top -l "$(($1 + 1))" -s 1 -stats cpu -pid "$pid" |
    awk 'NR>1 && /^[0-9.]+[[:space:]]*$/ {s+=$1; n++} END {if (n == 0) exit 1; printf "%.2f", s/n}'
}

cpu_check() {
  local choice="$1" budget="$2" rows="$3" average
  simulate "$choice"
  pointer_away
  say "Hands off the pointer and the menu for 70 s ($choice)."
  pause 10
  if $dry_run; then
    printf '    would run: top -l 61 -s 1 -stats cpu -pid <the pid of %s> and average it\n' "$app_binary"
    printf '    would check: the average is at most %s%% (QA %s)\n' "$budget" "$rows"
    return
  fi
  if ! average="$(cpu_average 60)" || [[ -z $average ]]; then
    result FAIL "$rows" cpu "$choice: no CPU samples (is DrowsyDock still running?)"
    return
  fi
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
  sample_app "$name" 5
  local passed=true
  check "$rows" idle-sample "$detail: no timer fires" sample_lacks "$timer_symbols" "$name" ||
    passed=false
  check "$rows" idle-sample "$detail: nothing draws" sample_lacks "$draw_symbols" "$name" ||
    passed=false
  check "$rows" idle-sample "$detail: the main thread waits in mach_msg" \
    sample_has mach_msg "$name" || passed=false
  $passed && forget_captures "$name.txt"
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
