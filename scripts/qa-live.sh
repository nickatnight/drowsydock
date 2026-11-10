#!/usr/bin/env bash
# Live QA: drives the real DrowsyDock on the real Dock and checks the rows of docs/manual-qa.md
# that need them. The owner runs it on their own Mac; agents only run it with --dry-run.
#
#   scripts/qa-live.sh                 run every scenario
#   scripts/qa-live.sh --only a,b      run the named scenarios (--list names them)
#   scripts/qa-live.sh --dry-run       print every step, change nothing
#   scripts/qa-live.sh --list          list the scenarios and the QA rows each checks
#   scripts/qa-live.sh --restore       restore the Dock preferences that a killed run left changed
#   scripts/qa-live.sh --restore --yes the same, without asking first
#   scripts/qa-live.sh --keep-captures keep the screenshots and samples even when their checks pass
#
# It changes the Dock's preferences (position, size, auto-hide, magnification). Before any change
# it saves them to build/qa/dock-backup.plist, checks the copy, and prints the command that
# restores them; a trap restores them on exit, error or Ctrl-C, and keeps the backup if the
# restore can't be verified. A kill -9 skips the trap: run the printed command, or --restore.
#
# It drives Debug ▸ Simulate battery through the app's real menu with System Events, moves the
# pointer and takes screenshots through scripts/qa's helper, and reads the app's log. Your
# terminal needs Accessibility and Screen Recording (System Settings ▸ Privacy & Security), and
# DrowsyDock needs its own Accessibility grant. It prints PASS, FAIL or SKIP per QA row, writes
# build/qa/report.md, and exits 1 if any row fails.
#
# build/qa keeps report.md and app.log. Screenshots and samples are deleted once their checks pass,
# and kept as evidence when they fail. Every process started from your terminal inherits its
# Accessibility and Screen Recording grants: consider a terminal profile used only for this run,
# and revoking the grants afterwards. The run quits and relaunches build/DrowsyDock.app only.
set -uo pipefail
cd "$(dirname "$0")/.."
root="$PWD"

# QA_DIR and QA_HELPER exist for scripts/qa/check-dry-run.sh, which points them at stubs.
qa_dir="${QA_DIR:-$root/build/qa}"
report="$qa_dir/report.md"
app_log="$qa_dir/app.log"
app="$root/build/DrowsyDock.app"
app_binary="$app/Contents/MacOS/DrowsyDock"
helper="${QA_HELPER:-$root/.build/release/qa-helper}"
subsystem="com.drowsydock.DrowsyDock"

# shellcheck source=scripts/qa/dock-preferences.sh
source "$root/scripts/qa/dock-preferences.sh"
dock_backup="$qa_dir/dock-backup.plist"
# This run's pid while it owns the backup, and log stream's pid while it runs, so another terminal
# and the next run can tell a live run from a killed one.
run_pid_file="$qa_dir/run.pid"
log_pid_file="$qa_dir/log.pid"

scenarios=(
  "restore-selftest|-|saves the Dock preferences, changes one harmless key, restores them"
  "launch|1.1 1.2 1.3 7.0|a menu-bar app with no Dock icon; Quit and Cmd-Q end it"
  "battery|3.0 3.1|the real battery's line matches pmset"
  "levels|3.9 3.10 3.11 3.12 3.13 3.14 3.15 3.16|every Simulate battery choice, in both orders"
  "position|5.1 5.2 7.1 8.9 11.5|the Dock on the left, right and bottom, set live: perch, facing, wave"
  "size|7.2|the overlay follows a live Dock size change within 1 s"
  "autohide|5.4 7.4 11.6|an auto-hidden Dock hides the cat and the wave"
  "hover|7.5b 8.11 9.8|the cat fades for its icon's label only (screenshot); a faded snore draws nothing"
  "magnification|7.5 7.5a 8.12|magnifying the Dock fades the cat and the veil, and they return"
  "relaunch|7.8 7.8a 7.8b|the cat returns after killall Dock and follows an app's icon"
  "align|5.5 6.1 8.5 8.15|perch size and place; veil, rim and paws within 1 pt, from screenshots"
  "cpu|7.9 9.6 9.7|idle CPU against the budgets in CONSTRAINTS.md and exception E1"
  "idle-sample|3.7 7.6 8.13|no timer and no drawing while idle, from sample"
)

dry_run=false
only=""
mode_restore=false
assume_yes=false
keep_captures=false
results=()
failed=false
owns_backup=false
needs_app=false
log_pid=""

usage() {
  sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
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
      if [[ -z ${2:-} || ${2:-} == --* ]]; then
        echo "--only needs scenario names, such as --only cpu,align (--list names them)" >&2
        exit 2
      fi
      only="$2"
      shift
      ;;
    --list)
      list
      exit 0
      ;;
    --restore) mode_restore=true ;;
    --yes) assume_yes=true ;;
    --keep-captures) keep_captures=true ;;
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

run_or_print() {
  if $dry_run; then
    printf '    would run:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

# In a dry run, every command that could touch the Dock, the app, the pointer, the screen or a
# file is replaced by a function that only reports it. A step that forgets run_or_print then prints
# UNGUARDED instead of acting, and scripts/qa/check-dry-run.sh fails on that word.
if $dry_run; then
  for command_name in defaults killall osascript open screencapture sample top swift log rm \
    mkdir mv kill pkill; do
    eval "$command_name() { printf '    UNGUARDED: %s %s\\n' $command_name \"\$*\"; }"
  done
  unset command_name
fi

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

owns_backup=false

# Changes one Dock preference the way System Settings does, through System Events, so the Dock
# keeps running and the app sees the change through com.apple.dock.prefchanged and Accessibility.
# PROPERTY and VALUE come from this script's own fixed set, such as "screen edge" left.
dock_preference() {
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

# The pid of another qa-live.sh run that owns build/qa, or nothing.
other_run_pid() {
  [[ -f $run_pid_file ]] || return 1
  local pid
  pid="$(cat "$run_pid_file")"
  [[ $pid =~ ^[0-9]+$ && $pid != "$$" ]] || return 1
  ps -o command= -p "$pid" 2>/dev/null | grep -q 'qa-live\.sh' || return 1
  printf '%s\n' "$pid"
}

# A log stream left by a killed run keeps appending to app.log until logout; stop it.
stop_stale_log_stream() {
  [[ -f $log_pid_file ]] || return 0
  local pid
  pid="$(cat "$log_pid_file")"
  if [[ $pid =~ ^[0-9]+$ ]] && ps -o command= -p "$pid" 2>/dev/null | grep -q '^log stream'; then
    kill "$pid" 2>/dev/null
  fi
  rm -f "$log_pid_file"
}

# Restores the Dock first, since that is what matters; the menu step after it is cosmetic and
# bounded by AppleScript timeouts. Signals are ignored from here on, so a second Ctrl-C can't cut
# the restore short.
cleanup() {
  local status=$?
  trap '' INT TERM HUP
  trap - EXIT
  if [[ -n $log_pid ]]; then kill "$log_pid" 2>/dev/null; fi
  $dry_run || rm -f "$log_pid_file"
  if ! put_dock_back; then
    result FAIL - dock "the Dock's preferences couldn't be restored; see the message above"
    status=1
  fi
  if $needs_app && ! $dry_run && app_running; then
    simulate Real 2>/dev/null
  fi
  write_report
  if ! $dry_run && [[ $(cat "$run_pid_file" 2>/dev/null) == "$$" ]]; then
    rm -f "$run_pid_file"
  fi
  exit "$status"
}

# --restore: shows how old the backup is and what it would change, and asks before applying it.
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
  stop_stale_log_stream
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

if $mode_restore && $dry_run; then
  echo "--restore applies the backup; it has no dry run. Run it without --dry-run." >&2
  exit 2
fi

if $mode_restore; then
  restore_from_backup
  exit $?
fi

# MARK: - Waiting and the app's log

pause() {
  if $dry_run; then
    printf '    would wait %s s\n' "$1"
    return
  fi
  sleep "$1"
}

# Every read of the app's log goes through these functions, so the source can change (today a
# `log stream` writing to build/qa/app.log) without touching the scenarios.

log_mark=0

start_app_log() {
  if $dry_run; then
    printf '    would run: log stream --style compact --level debug --predicate %q >%q &\n' \
      "subsystem == \"$subsystem\" AND process == \"DrowsyDock\"" "$app_log"
    return 0
  fi
  : >"$app_log"
  log stream --style compact --level debug \
    --predicate "subsystem == \"$subsystem\" AND process == \"DrowsyDock\"" >>"$app_log" 2>&1 &
  log_pid=$!
  printf '%s\n' "$log_pid" >"$log_pid_file"
  sleep 2
  app_log_alive
}

app_log_alive() {
  [[ -n $log_pid ]] && kill -0 "$log_pid" 2>/dev/null
}

# The whole log so far, or only what came after the last mark_log.
app_log_lines() {
  if [[ ${1:-} == since-mark ]]; then
    tail -n "+$((log_mark + 1))" "$app_log"
  else
    cat "$app_log"
  fi
}

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
    if app_log_lines since-mark | grep -Eq -- "$pattern"; then return 0; fi
    app_log_alive || return 1
    sleep 0.1
    waited=$((waited + 1))
  done
  return 1
}

last_log() {
  app_log_lines since-mark | grep -E -- "$1" | tail -n 1
}

# A negative check can only pass while the log is still being read.
no_log_since_mark() {
  app_log_alive || return 1
  ! app_log_lines since-mark | grep -Eq -- "$1"
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

# The app logs a Changed: line only when the menu line changes, and picking the choice already
# shown changes nothing. Every level differs from No battery, so a run of checks that waits for
# Changed: lines starts there.
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

# This build's process only, never another installed copy.
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
# terminal or whatever app is in front. Prints "sent" when it pressed it.
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
  run_or_print open "$app"
  wait_log "Accessibility granted: (true|false)" 10
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

# read_dock [sprite=W,H]: reads the Dock over Accessibility into shell variables named after the
# helper's keys: dock_orientation, dock_background, dock_screen, dock_first_icon, dock_last_icon,
# dock_facing, dock_scale, dock_primary_height, and with a sprite size dock_perch and dock_capture.
read_dock() {
  if $dry_run; then
    printf '    would run: %s dock %s\n' "$helper" "$*"
    dock_orientation=bottom dock_hidden=false dock_background=0,0,0,0 dock_perch=0,0,64,80
    dock_capture=0,0,0,0 dock_scale=2 dock_primary_height=0 dock_last_icon=0,0,0,0
    dock_first_icon=0,0,0,0 dock_screen=0,0,0,0 dock_facing=left dock_capture_region=0,0,0,0
    return 0
  fi
  local output key value
  output="$(qa_helper dock "$@")" || return 1
  while IFS='=' read -r key value; do
    case $key in
      orientation | hidden | icons | list | background | facing | perch | capture | screen | \
        scale | primary-height | first-icon | last-icon | capture-region)
        printf -v "dock_${key//-/_}" '%s' "$value"
        ;;
    esac
  done <<<"$output"
}

# Reads the perch the app last logged into dock_logged_perch, then the Dock with that sprite size,
# so the checks use the size the app draws rather than a copy of it.
read_dock_and_logged_perch() {
  if $dry_run; then
    printf '    would read the perch from the newest "Overlay: shown" line in %s\n' "$app_log"
    dock_logged_perch=0,0,64,80
    read_dock sprite=64,80
    return 0
  fi
  local line
  line="$(app_log_lines | grep -E "Overlay: (shown|fadedOut)" | tail -n 1)"
  dock_logged_perch="$(qa_helper logged-perch "$line")" || return 1
  read_dock sprite="$(field "$dock_logged_perch" 3),$(field "$dock_logged_perch" 4)"
}

# same_frame A B: whether two x,y,width,height frames agree within half a point.
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

# The symbols a sample shows while the cat draws, and while a run-loop timer fires. Positive and
# negative checks share them, so a renamed or inlined symbol fails the positive check.
draw_symbols='drawFrame|displayLinkFired|SKCRenderer'
timer_symbols='__CFRUNLOOP_IS_CALLING_OUT_TO_A_TIMER_CALLBACK_FUNCTION__'

# sample_app NAME SECONDS: samples this build's process into build/qa/NAME.txt.
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

# A sample check fails when the sample is missing or empty, whatever it looks for.
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
  for tool in osascript screencapture defaults log sample top pmset plutil swift git; do
    command -v "$tool" >/dev/null || {
      say "Missing $tool." >&2
      exit 1
    }
  done

  $needs_app || return 0

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

  say "Building the helper (it is never part of the app bundle)."
  if ! run_or_print swift build -c release --product qa-helper; then
    say "qa-helper failed to build; see the swift build output above." >&2
    exit 1
  fi
  if ! $dry_run && [[ ! -x $helper ]]; then
    say "qa-helper isn't at $helper after the build." >&2
    exit 1
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

  say "Reading the app's log."
  run_or_print mkdir -p "$qa_dir"
  if ! start_app_log; then
    say "Can't read the app's log: log stream stopped with: $(head -n 1 "$app_log")" >&2
    say "macOS lets only administrators run log stream. Run qa-live.sh from an admin account." >&2
    exit 1
  fi

  if ! $dry_run; then
    local others
    others="$(pgrep -x DrowsyDock | grep -vx "$(app_pid)" || true)"
    if [[ -n $others ]]; then
      say "Another DrowsyDock is running (pid $others). Quit it, so the menu and the log belong to this build." >&2
      exit 1
    fi
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

selftest_key="qa-live-selftest"

# Runs the real restore once: one harmless key the Dock ignores, then the restore that must remove
# it, then a fresh backup for the scenarios that follow.
scenario_restore_selftest() {
  step "restore-selftest: save, add one harmless key, restore"
  run_or_print defaults write com.apple.dock "$selftest_key" -bool true
  if $dry_run; then
    put_dock_back
    owns_backup=false
    take_dock_backup
    return
  fi
  if ! check - restore-selftest "the harmless key was written" selftest_key_present; then
    return
  fi
  local saved="$qa_dir/selftest-backup.plist"
  cp "$dock_backup" "$saved"
  if ! check - restore-selftest "the restore succeeds and verifies" put_dock_back; then
    # The backup this run saved is kept and still owned, so cleanup restores from it at the end.
    rm -f "$saved"
    return
  fi
  check - restore-selftest "the harmless key is gone" selftest_key_absent
  check - restore-selftest "the backup is deleted after a verified restore" test ! -e "$dock_backup"
  # The restore compared before it relaunched the Dock. This compares again once the Dock is back,
  # and names any key it wrote on launch: a Gate 2 watch item, kept strict until it's known.
  wait_for_dock_relaunch
  local changes
  changes="$(qa_helper preferences-change <(defaults export com.apple.dock -) "$saved")"
  check - restore-selftest "after the Dock relaunched, its preferences still equal the backup${changes:+ (differ: ${changes//$'\n'/, })}" \
    test -z "$changes"
  rm -f "$saved"
  owns_backup=false
  take_dock_backup
}

selftest_key_present() {
  defaults read com.apple.dock "$selftest_key" >/dev/null 2>&1
}

selftest_key_absent() {
  ! selftest_key_present
}

wait_for_dock_relaunch() {
  local waited=0
  while ! pgrep -x Dock >/dev/null && ((waited < 50)); do
    sleep 0.1
    waited=$((waited + 1))
  done
  sleep 1
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

# Seconds since the epoch, to the millisecond, from the helper (no perl needed).
now() {
  qa_helper now
}

change_started=""
change_done=""

# timed_change COMMAND…: marks the log, then runs COMMAND (a Dock or pointer change) and notes the
# time before and after it.
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

# The newest Overlay: line since the mark, and the first one that matches STATE (and, for shown,
# the perch DockGeometry gives for the Dock as it is now).
newest_overlay_line() {
  app_log_lines since-mark | grep -E "Overlay: (shown|fadedOut|hidden)" | tail -n 1
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
  done < <(app_log_lines since-mark | grep -E "Overlay: $state")
  return 1
}

# expect_overlay_within STATE BUDGET ROWS SCENARIO DETAIL: after the last timed_change, the app
# must log Overlay: STATE (for shown, at the settled Dock's perch) within BUDGET seconds of the
# change, by the app's own log timestamp, and no later Overlay: line may undo it. The report gives
# the latency from the command's end, and from its start.
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
  if ! wait_log "Overlay: $state" "$(awk -v b="$budget" 'BEGIN { print int(b + 4) }')"; then
    result FAIL "$rows" "$scenario" "$detail: no 'Overlay: $state' line"
    return 1
  fi
  # Let the Dock and the app settle, then read where the cat belongs.
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
  if [[ $newest != *"Overlay: $state"* ]]; then
    result FAIL "$rows" "$scenario" "$detail: a later line undid it: ${newest##*Overlay: }"
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

# The perch the app logged must be the one DockGeometry gives for the Dock as it is now.
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
  check "$3" "$4" "$5" wait_log "Overlay: $1" "$2"
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
      wait_log "Dock geometry: .*orientation: .*$side" 3
    if [[ $side != bottom ]]; then
      local facing=right
      [[ $side == right ]] && facing=left
      check 8.9 position "on a $side Dock the app's logged perch faces $facing" \
        logged_facing_is "$facing"
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
  line="$(app_log_lines | grep -E "Overlay: (shown|fadedOut)" | tail -n 1)"
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
  check 5.4 autohide "Log Dock geometry logs hidden: true" wait_log "hidden: true" 3
  pointer_away
  simulate Charging
  pause 4
  mark_log
  simulate 5%
  check 11.6 autohide "falling asleep with the Dock hidden logs that the overlay isn't showing" \
    wait_log "would nod off, but the overlay isn't showing" 3
  timed_change dock_preference autohide false
  expect_overlay_within shown 1 7.4 autohide "the cat returns when auto-hide is off"
  mark_log
  simulate 15%
  simulate 5%
  pause 2
  check 11.6 autohide "no wave until the next charge" no_log_since_mark "The whole Dock nods off"
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

  # What the perch looks like with the label showing and no cat, to compare the faded cat with.
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
    no_log_since_mark "Overlay: fadedOut"
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
  check 7.8 relaunch "the log shows 'The Dock relaunched'" wait_log "The Dock relaunched" 10
  expect_overlay shown 10 7.8 relaunch "the cat returns once the Dock's icons are back"
  check 7.8a relaunch "the observer is installed on the new Dock" \
    wait_log "Observing the Dock list for:" 10
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
    no_log_since_mark "The Dock list was destroyed|Observing the Dock list for:"
  timed_change run_or_print osascript -e 'tell application "Calculator" to quit'
  expect_overlay_within shown 1 "7.8a 7.8b" relaunch "the cat follows the last icon when it goes"
  pause 2
  expect_logged_perch_matches "7.8a 7.8b" relaunch "after Calculator quits, the perch is right"
  check 7.8b relaunch "an app's icon going isn't taken for the list's destruction" \
    no_log_since_mark "The Dock list was destroyed|Observing the Dock list for:"
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
    # The paws on the Dock's edge are also 6.1's "paws on the edge".
    line_rows="$rows"
    [[ $line == *"(8.15)"* ]] && line_rows="8.15 6.1"
    result "${line%% *}" "$line_rows" "align, $label" "${line#* }"
    [[ $line == FAIL* ]] && align_failed=true
  done <<<"$output"
  $align_failed || forget_captures bare.png awake.png asleep.png align.err
}

# Deletes screenshots and samples once their checks passed, unless --keep-captures. A failed
# check keeps them as evidence.
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

# QA 5.5: on a bottom Dock the perch is a 64 x 80 frame whose bottom edge is the background's top
# edge and whose right edge is the last icon's right edge. The size is the row's own number, so a
# wrong sprite size handed to the tracker fails here.
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

# near A B: within half a point.
near() {
  awk -v a="$1" -v b="$2" 'BEGIN { exit !(a - b <= 0.5 && b - a <= 0.5) }'
}

# capture_frame NAME FRAME: a screenshot of FRAME, in AppKit points, into build/qa/NAME.png.
capture_frame() {
  if $dry_run; then
    printf '    would run: screencapture -x -R <%s> %s/%s.png\n' "$2" "$qa_dir" "$1"
    return 0
  fi
  local region
  region="$(qa_helper region "$2")" || return 1
  screencapture -x -R "$region" "$qa_dir/$1.png" && [[ -s $qa_dir/$1.png ]]
}

# Whether two screenshots of the same area look the same: at most 1% of pixels differ by more
# than 24 levels of brightness, which allows for antialiasing and the label's shadow.
screenshots_match() {
  local counts differing total
  counts="$(qa_helper differing-pixels "$qa_dir/$1.png" "$qa_dir/$2.png")" || return 1
  read -r differing total <<<"$counts"
  ((total > 0 && differing * 100 <= total))
}

# The app's mean CPU over SECONDS of one-second samples, as CONSTRAINTS.md measures it. Fails with
# no output when the app isn't running or top gave no samples.
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

if ! $dry_run; then
  if pid="$(other_run_pid)"; then
    say "Another qa-live.sh run (pid $pid) is using build/qa and the Dock; let it finish." >&2
    exit 1
  fi
  if [[ -f $dock_backup ]]; then
    say "A backup that was never restored is still at $dock_backup." >&2
    say "Restore it first: scripts/qa-live.sh --restore" >&2
    exit 1
  fi
  stop_stale_log_stream
  mkdir -p "$qa_dir"
  printf '%s\n' "$$" >"$run_pid_file"
fi

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

preflight
take_dock_backup

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
