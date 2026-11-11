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

# shellcheck source=scripts/qa/live-functions.sh
source "$root/scripts/qa/live-functions.sh"

if $mode_restore && $dry_run; then
  echo "--restore applies the backup; it has no dry run. Run it without --dry-run." >&2
  exit 2
fi

if $mode_restore; then
  restore_from_backup
  exit $?
fi

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
