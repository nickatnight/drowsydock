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
source scripts/qa/live-functions.sh

root="$PWD"
dry_run=false
needs_app=true
failed=false
results=()
helper="$HELPER"
qa_dir="$SCRATCH/qa"
app="$SCRATCH/DrowsyDock.app"
app_binary="$app/Contents/MacOS/DrowsyDock"
app_log="$SCRATCH/qa.log"
run_log="$qa_dir/app.log"
calls="$SCRATCH/calls.log"

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

case_overlay_in_time() {
  start_run
  mark_log
  append "$overlay_shown"
  time_change_before "$overlay_shown" 0.300 0.120
  expect_overlay_within shown 1 7.1 position "the cat moves"
}

case_overlay_late() {
  start_run
  mark_log
  append "$overlay_shown"
  time_change_before "$overlay_shown" 1.700 1.500
  expect_overlay_within shown 1 7.1 position "the cat moves"
}

case_overlay_elsewhere() {
  start_run
  mark_log
  append "$overlay_shown"
  time_change_before "$overlay_shown" 0.300 0.120
  DOCK_PERCH=0,0,64,80 expect_overlay_within shown 1 7.1 position "the cat moves"
}

case_overlay_undone() {
  start_run
  mark_log
  append "$overlay_shown" "$overlay_faded"
  time_change_before "$overlay_shown" 0.300 0.120
  expect_overlay_within shown 1 7.1 position "the cat moves"
}

case_perch_within_half_a_point() {
  start_run
  mark_log
  append "$overlay_shown"
  time_change_before "$overlay_shown" 0.300 0.120
  DOCK_PERCH=1070.4,84,64,80 expect_overlay_within shown 1 7.1 position "0.4 pt off"
  DOCK_PERCH=1070.6,84,64,80 expect_overlay_within shown 1 7.1 position "0.6 pt off"
}

case_just_past_the_budget() {
  start_run
  mark_log
  append "$overlay_shown"
  time_change_before "$overlay_shown" 1.200 1.050
  expect_overlay_within shown 1 7.1 position "the cat moves"
}

case_old_perch_early_new_perch_late() {
  start_run
  mark_log
  fixture_line "$overlay_shown" | sed 's/frame: (1070.0, 84.0/frame: (900.0, 84.0/' >>"$app_log"
  fixture_line "$overlay_shown" | sed 's/^2026-11-10T01:31:07.123/2026-11-10T01:31:08.423/' \
    >>"$app_log"
  time_change_before "$overlay_shown" 0.300 0.120
  expect_overlay_within shown 1 7.1 position "the cat moves"
}

case_faded_in_time() {
  start_run
  mark_log
  append "$overlay_faded"
  time_change_before "$overlay_faded" 0.300 0.150
  expect_overlay_within fadedOut 0.2 8.11 hover "the cat fades"
}

case_faded_late() {
  start_run
  mark_log
  append "$overlay_faded"
  time_change_before "$overlay_faded" 0.300 0.250
  expect_overlay_within fadedOut 0.2 8.11 hover "the cat fades"
}

case_faded_then_shown() {
  start_run
  mark_log
  append "$overlay_faded" "$overlay_shown"
  time_change_before "$overlay_faded" 0.300 0.150
  expect_overlay_within fadedOut 0.2 8.11 hover "the cat fades"
}

case_hidden_in_time() {
  start_run
  mark_log
  append "$overlay_hidden"
  time_change_before "$overlay_hidden" 0.300 0.100
  expect_overlay_within hidden 1 7.4 autohide "the cat hides"
}

case_cleanup() {
  start_run
  append "$started" "$grant"
  put_dock_back() { return 0; }
  write_report() { :; }
  run_pid_file="$SCRATCH/run.pid"
  ( (exit 3); cleanup )
  echo "cleanup exit: $?"
  echo "run log: $(cut -d' ' -f4- "$run_log" | tr '\n' '|')"
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
  rm -rf "$scratch/qa" "$scratch/qa.log" "$scratch/calls.log"
  : >"$scratch/calls.log"
  # A helper built for coverage writes a profile on exit; keep it out of the checkout.
  output="$(env SCRATCH="$scratch" HELPER="$helper" LLVM_PROFILE_FILE="$scratch/%p.profraw" \
    FIXTURE="$PWD/Tests/LiveQAKitTests/Fixtures/qa.log" CASE="case_$1" "${@:2}" \
    bash "$scratch/run-case.sh" 2>&1)"
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

run_case overlay_in_time
expect "PASS QA 7.1 (position): the cat moves: 0.12 s after the change returned (0.30 s after it started; budget 1 s)"

run_case overlay_late
expect "FAIL QA 7.1 (position): the cat moves: 1.50 s after the change returned (1.70 s after it started; budget 1 s)"

run_case overlay_elsewhere
expect "FAIL QA 7.1 (position): the cat moves: no 'Overlay: shown' line at the Dock's perch"

run_case overlay_undone
faded="$(grep -m 1 'Overlay: fadedOut' Tests/LiveQAKitTests/Fixtures/qa.log)"
expect "FAIL QA 7.1 (position): the cat moves: a later line undid it: ${faded#*Overlay: }"

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

run_case perch_within_half_a_point
expect "PASS QA 7.1 (position): 0.4 pt off: 0.12 s after the change returned (0.30 s after it started; budget 1 s)"
expect "FAIL QA 7.1 (position): 0.6 pt off: no 'Overlay: shown' line at the Dock's perch"

run_case just_past_the_budget
expect "FAIL QA 7.1 (position): the cat moves: 1.05 s after the change returned (1.20 s after it started; budget 1 s)"

run_case old_perch_early_new_perch_late
expect "FAIL QA 7.1 (position): the cat moves: 1.42 s after the change returned (1.60 s after it started; budget 1 s)"

run_case faded_in_time
expect "PASS QA 8.11 (hover): the cat fades: 0.15 s after the change returned (0.30 s after it started; budget 0.2 s)"

run_case faded_late
expect "FAIL QA 8.11 (hover): the cat fades: 0.25 s after the change returned (0.30 s after it started; budget 0.2 s)"

run_case faded_then_shown
shown="$(grep -m 1 'Overlay: shown' Tests/LiveQAKitTests/Fixtures/qa.log)"
expect "FAIL QA 8.11 (hover): the cat fades: a later line undid it: ${shown#*Overlay: }"

run_case hidden_in_time
expect "PASS QA 7.4 (autohide): the cat hides: 0.10 s after the change returned (0.30 s after it started; budget 1 s)"

run_case cleanup
expect "cleanup exit: 3"
expect "run log: battery: Started: 46% · Discharging · Drowsy (real)|accessibility: Accessibility granted: true|"
[[ $(cat "$scratch/calls.log") == "kill -TERM 4242"$'\n'"open $scratch/DrowsyDock.app" ]] ||
  fail "cleanup doesn't quit the app and reopen it without --qa-log: $(cat "$scratch/calls.log")"

run_case preflight OPEN_WRITES_GRANT=1
expect "preflight: 0, pid 4242"
expect "run log: accessibility: Accessibility granted: true|"

exit "$failed"
