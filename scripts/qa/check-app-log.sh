#!/usr/bin/env bash
# Runs qa-live.sh's log reads over Tests/LiveQAKitTests/Fixtures/qa.log, the QA log the app writes
# when launched with --qa-log (ADR 0020), with the real debug qa-helper.
set -uo pipefail
cd "$(dirname "$0")/../.."
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

helper="$(swift build --show-bin-path)/qa-helper"
if [[ ! -x $helper ]]; then
  echo "check-app-log: no qa-helper at $helper; run swift build first" >&2
  exit 1
fi

cat >"$scratch/run-case.sh" <<'RUN'
set -uo pipefail
source scripts/qa/dock-preferences.sh
source scripts/qa/live-functions.sh

root="$PWD"
dry_run=false
failed=false
results=()
helper="$HELPER"
qa_dir="$SCRATCH/qa"
app="$SCRATCH/DrowsyDock.app"
app_binary="$app/Contents/MacOS/DrowsyDock"
app_log="$SCRATCH/qa.log"
run_log="$qa_dir/app.log"
report="$qa_dir/report.md"
dock_backup="$qa_dir/dock-backup.plist"
run_pid_file="$SCRATCH/run.pid"
owns_backup=false
keep_captures=false
assume_yes=false
require_live_settings
calls="$SCRATCH/calls.log"

# Every case works on a scratch defaults domain. A call that still names com.apple.dock, even
# inside a path, tries to relaunch the Dock, or runs osascript, which is how a live run changes the
# Dock, is refused and fails the case, whatever the case forgot to set. A case that needs osascript
# defines its own.
dock_domain="$SCRATCH/dock"
dock_restart() { echo "dock restart" >>"$calls"; }
killall() { echo "killall $*" >>"$SCRATCH/refused"; exit 99; }
osascript() { echo "osascript $*" >>"$SCRATCH/refused"; exit 99; }
defaults() {
  case "$*" in *com.apple.dock*) echo "defaults $*" >>"$SCRATCH/refused"; exit 99 ;; esac
  if [[ -n ${FAIL_IMPORTS:-} && $1 == import && $2 == "$dock_domain" ]]; then return 1; fi
  command defaults "$@"
}

# The fixture's lines by what they hold. 4242 is the app the run launched, 999 another DrowsyDock.
earlier_runs_grant=1
started=2
grant=3
other_apps_change=4
overlay_shown=5
change_to_80=6
overlay_faded=7
started_over=8
overlay_hidden=9

fixture_line() {
  sed -n "${1}p" "$FIXTURE"
}

append() {
  local number
  for number in "$@"; do fixture_line "$number" >>"$app_log"; done
}

# A fake process table: one "pid binary" line per running DrowsyDock. 4242 is this build's app, and
# 999, with OTHER_APP set, another copy's.
running="$SCRATCH/running"
: >"$running"
if [[ -n ${OTHER_APP:-} ]]; then
  echo "999 /Applications/DrowsyDock.app/Contents/MacOS/DrowsyDock" >>"$running"
fi
if [[ -z ${APP_STOPPED:-} ]]; then echo "4242 $app_binary" >>"$running"; fi

stop() {
  grep -v "^$1 " "$running" >"$running.new"
  mv "$running.new" "$running"
}

# Like LaunchServices, it starts this build's app only if that isn't running already.
open() {
  echo "open $*" >>"$calls"
  if [[ -z ${APP_NEVER_RUNS:-} ]] && ! grep -q "^4242 " "$running"; then
    echo "4242 $app_binary" >>"$running"
  fi
  if [[ -n ${OPEN_WRITES_GRANT:-} ]]; then append "$grant"; fi
}
pgrep() { if [[ $* == "-x DrowsyDock" ]]; then cut -d' ' -f1 "$running"; fi; }
ps() { awk -v pid="${@: -1}" '$1 == pid { print $2 }' "$running"; }
kill() {
  case $1 in
    -0) grep -q "^$2 " "$running" ;;
    -TERM)
      echo "kill -TERM $2" >>"$calls"
      if [[ -z ${IGNORES_TERM:-} ]]; then stop "$2"; fi
      ;;
    *) echo "kill $*" >>"$calls" ;;
  esac
}
sleep() { :; }
menu() { echo "menu $*" >>"$calls"; append "$change_to_80"; }
read_dock() { dock_perch="${DOCK_PERCH:-1070,84,64,80}"; }

answer() {
  if "${@:2}"; then echo "$1: yes"; else echo "$1: no"; fi
}

start_run() {
  append "$earlier_runs_grant"
  open_app_log
  app_log_pid=4242
}

# Times the change $2 s and $3 s before the app logged fixture line $1.
time_change_before() {
  local logged
  logged="$(qa_helper log-time "$(fixture_line "$1")")"
  change_started="$(awk -v t="$logged" -v s="$2" 'BEGIN { printf "%.3f", t - s }')"
  change_done="$(awk -v t="$logged" -v d="$3" 'BEGIN { printf "%.3f", t - d }')"
}

case_this_runs_lines_of_this_app() {
  start_run
  answer "an earlier run's line" wait_log "Accessibility granted" 1
  append "$started" "$grant" "$other_apps_change"
  answer "this app's grant" wait_log "Accessibility granted: true" 1
  answer "another DrowsyDock's line" wait_log "Changed: 5%" 1
  echo "lines read: $(app_log_lines | wc -l | tr -d ' ')"
}

case_mark() {
  start_run
  append "$started" "$grant"
  mark_log
  answer "nothing since the mark" app_runs_with_no_log_since_mark "Accessibility granted"
  append "$change_to_80"
  answer "a line since the mark" wait_log "Changed: 80%" 1
  answer "no such line since the mark" app_runs_with_no_log_since_mark "Changed: 80%"
  echo "last: $(last_log "Changed:" | cut -d' ' -f3-)"
}

case_app_gone() {
  start_run
  append "$started"
  mark_log
  stop 4242
  answer "no line, but the app is gone" app_runs_with_no_log_since_mark "Changed:"
  answer "waiting, with the app gone" wait_log "Changed:" 5
}

case_started_over() {
  start_run
  append "$started" "$grant" "$overlay_shown" "$change_to_80"
  mark_log
  : >"$app_log"
  append "$started_over" "$overlay_hidden"
  answer "a line after the app started the file over" wait_log "Overlay: hidden" 1
}

case_run_log() {
  append "$earlier_runs_grant" "$overlay_shown" "$overlay_faded"
  open_app_log
  append "$started" "$other_apps_change"
  save_run_log
  echo "run log: $(cut -d' ' -f2 "$run_log" | tr '\n' ' ')"
  : >"$app_log"
  append "$started_over"
  save_run_log
  echo "run log after the start-over: $(cut -d' ' -f4- "$run_log")"
}

case_shown_in_time_within_half_a_point() {
  start_run
  mark_log
  append "$overlay_shown"
  time_change_before "$overlay_shown" 0.300 0.120
  DOCK_PERCH=1070.4,84,64,80 expect_overlay_within shown 1 7.1 position "0.4 pt off"
}

case_old_perch_on_time_dock_perch_late() {
  start_run
  mark_log
  fixture_line "$overlay_shown" | sed 's/frame: (1070.0, 84.0/frame: (900.0, 84.0/' >>"$app_log"
  fixture_line "$overlay_shown" | sed 's/^2026-11-10T01:31:07.123/2026-11-10T01:31:08.423/' \
    >>"$app_log"
  time_change_before "$overlay_shown" 0.300 0.120
  expect_overlay_within shown 1 7.1 position "the cat moves"
}

case_shown_just_past_half_a_point() {
  start_run
  mark_log
  append "$overlay_shown"
  time_change_before "$overlay_shown" 0.300 0.120
  DOCK_PERCH=1069.4,84,64,80 expect_overlay_within shown 1 7.1 position "0.6 pt off"
}

case_overlay_undone() {
  start_run
  mark_log
  append "$overlay_faded" "$overlay_shown"
  time_change_before "$overlay_faded" 0.300 0.150
  expect_overlay_within fadedOut 0.2 8.11 hover "the cat fades"
}

# The fade's 0.2 s budget lies between the times since the change started and since it returned.
case_faded_at_the_budget() {
  start_run
  mark_log
  append "$overlay_faded"
  time_change_before "$overlay_faded" 0.300 0.200
  expect_overlay_within fadedOut 0.2 8.11 hover "the cat fades"
}

case_hidden_in_time() {
  start_run
  mark_log
  append "$overlay_hidden"
  time_change_before "$overlay_hidden" 0.300 0.100
  expect_overlay_within hidden 1 7.4 autohide "the cat hides"
}

case_faded_late() {
  start_run
  mark_log
  append "$overlay_faded"
  time_change_before "$overlay_faded" 0.300 0.250
  expect_overlay_within fadedOut 0.2 8.11 hover "the cat fades"
}

case_cleanup() {
  start_run
  append "$started" "$grant"
  put_dock_back() { return 0; }
  write_report() { :; }
  ( (exit 3); cleanup )
  echo "cleanup exit: $?"
  echo "run log: $(cut -d' ' -f4- "$run_log" | tr '\n' '|')"
}

# The exit trap with the real put_dock_back, on a scratch domain instead of com.apple.dock. The
# domain starts at orientation=bottom, is backed up, then changed to left.
change_scratch_dock() {
  write_report() { :; }
  defaults write "$dock_domain" orientation -string bottom
  save_dock_backup
  defaults write "$dock_domain" orientation -string left
}

dock_after_cleanup() {
  ( (exit 3); cleanup )
  echo "cleanup exit: $?"
  echo "orientation: $(defaults read "$dock_domain" orientation 2>/dev/null)"
  answer "backup kept" test -e "$dock_backup"
}

case_restore_on_exit() {
  change_scratch_dock
  owns_backup=true
  dock_after_cleanup
}

case_failed_restore_on_exit() {
  FAIL_IMPORTS=1
  change_scratch_dock
  owns_backup=true
  dock_after_cleanup
}

case_backup_not_owned() {
  change_scratch_dock
  dock_after_cleanup
}

# Runs the whole app preflight with the tools stubbed; the bundle is an empty executable.
case_preflight() {
  mkdir -p "$app/Contents/MacOS"
  : >"$app_binary"
  chmod +x "$app_binary"
  git() { if [[ $1 == log ]]; then echo 0; fi; }
  qa_helper() { echo "accessibility=true screen-recording=true"; }
  osascript() { echo bottom; }
  append "$earlier_runs_grant"
  preflight_app
  echo "preflight: $?, pid $app_log_pid"
  save_run_log
  echo "run log: $(cut -d' ' -f4- "$run_log" | tr '\n' '|')"
}

case_preflight_after_a_stuck_quit() {
  mkdir -p "$app/Contents/MacOS"
  : >"$app_binary"
  chmod +x "$app_binary"
  git() { if [[ $1 == log ]]; then echo 0; fi; }
  qa_helper() { echo "accessibility=true screen-recording=true"; }
  osascript() { echo bottom; }
  ( preflight_app )
  echo "preflight exit: $?"
}

case_facing() {
  start_run
  append "$overlay_shown"
  answer "faces left" logged_facing_is left
  answer "faces right" logged_facing_is right
}

case_expect_line() {
  start_run
  expect_line "80%" "80% · Discharging · Awake" "3.9 to 3.13"
}

case_launch() {
  launch_app
  echo "launch: $?, pid $app_log_pid"
}

"$CASE"
RUN

failed=0
output=""

fail() {
  echo "check-app-log: $1" >&2
  failed=1
}

run_case() {
  case_name="$1"
  rm -rf "$scratch/qa" "$scratch/qa.log" "$scratch/calls.log" "$scratch/dock.plist" \
    "$scratch/refused"
  : >"$scratch/calls.log"
  # A helper built for coverage writes a profile on exit; keep it out of the checkout.
  output="$(env SCRATCH="$scratch" HELPER="$helper" LLVM_PROFILE_FILE="$scratch/%p.profraw" \
    FIXTURE="$PWD/Tests/LiveQAKitTests/Fixtures/qa.log" CASE="case_$1" "${@:2}" \
    bash "$scratch/run-case.sh" 2>&1)"
  if [[ -s $scratch/refused ]]; then
    fail "$case_name reached for the real Dock: $(tr '\n' ';' <"$scratch/refused")"
  fi
}

expect() {
  grep -qxF -- "$1" <<<"$output" || fail "$case_name: expected the line '$1' in:"$'\n'"$output"
}

run_case this_runs_lines_of_this_app
expect "an earlier run's line: no"
expect "this app's grant: yes"
expect "another DrowsyDock's line: no"
expect "lines read: 2"

run_case mark
expect "nothing since the mark: yes"
expect "a line since the mark: yes"
expect "no such line since the mark: no"
expect "last: notice battery: Changed: 80% · Discharging · Awake (simulated 80%)"

run_case app_gone APP_GONE=1
expect "no line, but the app is gone: no"
expect "waiting, with the app gone: no"

run_case started_over
expect "a line after the app started the file over: yes"

run_case facing
expect "faces left: yes"
expect "faces right: no"

run_case run_log
expect "run log: DrowsyDock[4242] DrowsyDock[999] "
expect "run log after the start-over: qa-log: qa.log reached its limit of 1048576 bytes and started over"

run_case shown_in_time_within_half_a_point
expect "PASS QA 7.1 (position): 0.4 pt off: 0.12 s after the change returned (0.30 s after it started; budget 1 s)"

run_case old_perch_on_time_dock_perch_late
expect "FAIL QA 7.1 (position): the cat moves: 1.42 s after the change returned (1.60 s after it started; budget 1 s)"

run_case shown_just_past_half_a_point
expect "FAIL QA 7.1 (position): 0.6 pt off: no 'Overlay: shown' line at the Dock's perch"

run_case overlay_undone
shown="$(grep -m 1 'Overlay: shown' Tests/LiveQAKitTests/Fixtures/qa.log)"
expect "FAIL QA 8.11 (hover): the cat fades: a later line undid it: ${shown#*Overlay: }"

run_case faded_at_the_budget
expect "PASS QA 8.11 (hover): the cat fades: 0.20 s after the change returned (0.30 s after it started; budget 0.2 s)"

run_case hidden_in_time
expect "PASS QA 7.4 (autohide): the cat hides: 0.10 s after the change returned (0.30 s after it started; budget 1 s)"

run_case faded_late
expect "FAIL QA 8.11 (hover): the cat fades: 0.25 s after the change returned (0.30 s after it started; budget 0.2 s)"

run_case expect_line
expect "PASS QA 3.9 to 3.13 (levels): 80% shows '80% · Discharging · Awake'"
grep -qxF "menu Debug Simulate battery 80%" "$scratch/calls.log" ||
  fail "expect_line didn't pick 80% in the menu: $(cat "$scratch/calls.log")"

run_case launch OPEN_WRITES_GRANT=1 OTHER_APP=1
expect "launch: 0, pid 4242"
grep -qxF "open $scratch/DrowsyDock.app --args --qa-log" "$scratch/calls.log" ||
  fail "launch_app doesn't open this build with --qa-log: $(cat "$scratch/calls.log")"

run_case launch
expect "launch: 1, pid 4242"

run_case launch APP_STOPPED=1 APP_NEVER_RUNS=1
expect "launch: 1, pid "

run_case launch APP_STOPPED=1 APP_NEVER_RUNS=1 OTHER_APP=1
expect "launch: 1, pid "

run_case cleanup
expect "cleanup exit: 3"
expect "run log: battery: Started: 46% · Discharging · Drowsy (real)|accessibility: Accessibility granted: true|"
[[ $(cat "$scratch/calls.log") == "kill -TERM 4242"$'\n'"open $scratch/DrowsyDock.app" ]] ||
  fail "cleanup doesn't quit the app and reopen it without --qa-log: $(cat "$scratch/calls.log")"

run_case cleanup IGNORES_TERM=1
expect "cleanup exit: 1"
expect "FAIL QA - (cleanup): DrowsyDock (pid 4242) didn't quit within 5 s, so it may still write the QA log; quit it"
[[ $(cat "$scratch/calls.log") == "kill -TERM 4242" ]] ||
  fail "after a stuck quit, cleanup must not open the app again: $(cat "$scratch/calls.log")"

run_case restore_on_exit APP_STOPPED=1
expect "cleanup exit: 3"
expect "orientation: bottom"
expect "backup kept: no"
grep -qx "dock restart" "$scratch/calls.log" || fail "restore_on_exit didn't relaunch the Dock"

run_case failed_restore_on_exit APP_STOPPED=1
expect "FAIL QA - (dock): the Dock's preferences couldn't be restored; see the message above"
expect "cleanup exit: 1"
expect "backup kept: yes"

run_case backup_not_owned APP_STOPPED=1
expect "cleanup exit: 3"
expect "orientation: left"
expect "backup kept: yes"

run_case preflight_after_a_stuck_quit IGNORES_TERM=1 OPEN_WRITES_GRANT=1
expect "preflight exit: 1"
expect "DrowsyDock (pid 4242) didn't quit within 5 s, so it can't be relaunched with --qa-log; quit it, then run again."
grep -q '^open' "$scratch/calls.log" &&
  fail "after a stuck quit, the preflight opened the app: $(cat "$scratch/calls.log")"

run_case preflight OPEN_WRITES_GRANT=1
expect "preflight: 0, pid 4242"
expect "run log: accessibility: Accessibility granted: true|"

exit "$failed"
