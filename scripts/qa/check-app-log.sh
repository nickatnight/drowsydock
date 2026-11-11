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

append() {
  local number
  for number in "$@"; do sed -n "${number}p" "$FIXTURE" >>"$app_log"; done
}

open() {
  echo "open $*" >>"$calls"
  if [[ -n ${OPEN_WRITES:-} ]]; then append $OPEN_WRITES; fi
}
pgrep() { if [[ $* == "-x DrowsyDock" && -z ${APP_NEVER_RUNS:-} ]]; then echo 4242; fi; }
ps() { echo "$app_binary"; }
kill() { [[ $1 == -0 && $2 == 4242 && -z ${APP_GONE:-} ]]; }
sleep() { :; }
menu() { echo "menu $*" >>"$calls"; append 6; }
read_dock() { dock_perch="${DOCK_PERCH:-1070,84,64,80}"; }

answer() {
  if "${@:2}"; then echo "$1: yes"; else echo "$1: no"; fi
}

start_run() {
  append 1
  open_app_log
  app_log_pid=4242
}

time_overlay_change() {
  change_started="$(awk -v s="$1" 'BEGIN { printf "%.3f", 1794270667.123 - s }')"
  change_done="$(awk -v d="$2" 'BEGIN { printf "%.3f", 1794270667.123 - d }')"
}

case_this_runs_lines_of_this_app() {
  start_run
  answer "an earlier run's line" wait_log "Accessibility granted" 1
  append 2 3 4
  answer "this app's grant" wait_log "Accessibility granted: true" 1
  answer "another DrowsyDock's line" wait_log "Changed: 5%" 1
  echo "lines read: $(app_log_lines | wc -l | tr -d ' ')"
}

case_mark() {
  start_run
  append 2 3
  mark_log
  answer "nothing since the mark" app_runs_with_no_log_since_mark "Accessibility granted"
  append 6
  answer "a line since the mark" wait_log "Changed: 80%" 1
  answer "no such line since the mark" app_runs_with_no_log_since_mark "Changed: 80%"
  echo "last: $(last_log "Changed:" | cut -d' ' -f3-)"
}

case_app_gone() {
  start_run
  append 2
  mark_log
  answer "no line, but the app is gone" app_runs_with_no_log_since_mark "Changed:"
  answer "waiting, with the app gone" wait_log "Changed:" 5
}

case_started_over() {
  start_run
  append 2 3 5 6
  mark_log
  : >"$app_log"
  append 8 9
  answer "a line after the app started the file over" wait_log "Overlay: hidden" 1
}

case_run_log() {
  append 1 5 7
  open_app_log
  append 2 4
  save_run_log
  echo "run log: $(cut -d' ' -f2 "$run_log" | tr '\n' ' ')"
  : >"$app_log"
  append 8
  save_run_log
  echo "run log after the start-over: $(cut -d' ' -f4- "$run_log")"
}

case_overlay_in_time() {
  start_run
  mark_log
  append 5
  time_overlay_change 0.300 0.120
  expect_overlay_within shown 1 7.1 position "the cat moves"
}

case_overlay_late() {
  start_run
  mark_log
  append 5
  time_overlay_change 1.700 1.500
  expect_overlay_within shown 1 7.1 position "the cat moves"
}

case_overlay_elsewhere() {
  start_run
  mark_log
  append 5
  time_overlay_change 0.300 0.120
  DOCK_PERCH=0,0,64,80 expect_overlay_within shown 1 7.1 position "the cat moves"
}

case_overlay_undone() {
  start_run
  mark_log
  append 5 7
  time_overlay_change 0.300 0.120
  expect_overlay_within shown 1 7.1 position "the cat moves"
}

case_facing() {
  start_run
  append 5
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
expect "FAIL QA 7.1 (position): the cat moves: a later line undid it: $(sed -n '7s/.*Overlay: //p' Tests/LiveQAKitTests/Fixtures/qa.log)"

run_case expect_line
expect "PASS QA 3.9 to 3.13 (levels): 80% shows '80% · Discharging · Awake'"
grep -qxF "menu Debug Simulate battery 80%" "$scratch/calls.log" ||
  fail "expect_line didn't pick 80% in the menu: $(cat "$scratch/calls.log")"

run_case launch OPEN_WRITES=3
expect "launch: 0, pid 4242"
grep -qxF "open $scratch/DrowsyDock.app --args --qa-log" "$scratch/calls.log" ||
  fail "launch_app doesn't open this build with --qa-log: $(cat "$scratch/calls.log")"

run_case launch
expect "launch: 1, pid 4242"

run_case launch APP_NEVER_RUNS=1
expect "launch: 1, pid "

exit "$failed"
