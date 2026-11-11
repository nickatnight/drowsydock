#!/usr/bin/env bash
# Runs qa-live.sh's restore self-test and its exit cleanup against a scratch defaults domain, never
# com.apple.dock. A `defaults` stub sends com.apple.dock to the scratch domain and refuses any other
# name that contains it; killall, osascript, open, pkill, pgrep and sleep are stubs too.
set -uo pipefail
cd "$(dirname "$0")/../.."
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

helper="$(swift build --show-bin-path)/qa-helper"
if [[ ! -x $helper ]]; then
  echo "check-restore-selftest: no qa-helper at $helper; run swift build first" >&2
  exit 1
fi

# Executing qa-live.sh starts a run, so take only its function definitions.
awk '
  /^[a-z_]+\(\) \{.*\}$/ { print; next }
  /^[a-z_]+\(\) \{$/ { inside = 1 }
  inside { print }
  inside && /^\}$/ { inside = 0 }
' scripts/qa-live.sh >"$scratch/qa-live-functions.sh"

cat >"$scratch/run-selftest.sh" <<'RUN'
set -uo pipefail
source scripts/qa/dock-preferences.sh
source "$SCRATCH/qa-live-functions.sh"

domain="$SCRATCH/dock"
calls="$SCRATCH/calls.log"
imports_to_fail="${FAIL_IMPORTS:-0}"

defaults() {
  local arguments=() argument
  for argument in "$@"; do
    if [[ $argument == com.apple.dock ]]; then argument="$domain"; fi
    if [[ $argument == *com.apple.dock* ]]; then
      echo "refused: defaults $*" >>"$calls"
      return 1
    fi
    arguments+=("$argument")
  done
  if [[ ${arguments[0]} == import && ${arguments[1]} == "$domain" ]] && ((imports_to_fail > 0)); then
    imports_to_fail=$((imports_to_fail - 1))
    return 1
  fi
  command defaults "${arguments[@]}"
}

killall() {
  if [[ $* != Dock ]]; then
    echo "killall $*" >>"$calls"
    return 1
  fi
  if [[ -n ${RELAUNCH_WRITES:-} ]]; then
    command defaults write "$domain" "$RELAUNCH_WRITES" -bool true
  fi
}

osascript() { echo "osascript $*" >>"$calls"; }
open() { echo "open $*" >>"$calls"; }
pkill() { echo "pkill $*" >>"$calls"; }
pgrep() { return 0; }
sleep() {
  if [[ -n ${INTERRUPT_ON_SLEEP:-} ]]; then
    INTERRUPT_ON_SLEEP=""
    kill -INT $$
  fi
}

root="$PWD"
dry_run=false
needs_app=false
owns_backup=false
failed=false
results=()
log_pid=""
helper="$HELPER"
qa_dir="$SCRATCH/qa"
report="$qa_dir/report.md"
dock_domain="$domain"
dock_backup="$qa_dir/dock-backup.plist"
run_pid_file="$qa_dir/run.pid"
log_pid_file="$qa_dir/log.pid"
selftest_key="qa-live-selftest"

mkdir -p "$qa_dir"
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

take_dock_backup
scenario_restore_selftest
dock_preference "screen edge" left
$failed && exit 1
exit 0
RUN

for name in scenario_restore_selftest cleanup take_dock_backup put_dock_back check result; do
  if ! grep -q "^$name() {" "$scratch/qa-live-functions.sh"; then
    echo "check-restore-selftest: qa-live.sh no longer defines $name()" >&2
    exit 1
  fi
done

failed=0
fail() {
  echo "check-restore-selftest: $1" >&2
  failed=1
}

original="$scratch/original.xml"
output=""
status=0

run_selftest() {
  rm -rf "$scratch/dock.plist" "$scratch/qa" "$scratch/calls.log"
  : >"$scratch/calls.log"
  command defaults write "$scratch/dock" orientation -string bottom
  command defaults write "$scratch/dock" tilesize -int 48
  defaults export "$scratch/dock" - | plutil -convert xml1 -o "$original" -
  status=0
  # A helper built for coverage writes a profile on exit; keep it out of the checkout.
  output="$(env SCRATCH="$scratch" HELPER="$helper" LLVM_PROFILE_FILE="$scratch/%p.profraw" "$@" \
    bash "$scratch/run-selftest.sh" 2>&1)" ||
    status=$?
  if grep -q '^refused:' "$scratch/calls.log"; then
    fail "a case reached a defaults domain other than the scratch one: $(grep '^refused:' "$scratch/calls.log")"
  fi
}

domain_is_original() {
  cmp -s "$original" <(defaults export "$scratch/dock" - | plutil -convert xml1 -o - -)
}

has_line() {
  grep -qF -- "$1" <<<"$output"
}

rows() {
  printf 'exit %s\n' "$status"
  grep -E '^(PASS|FAIL) QA|usage' <<<"$output" | sed 's/^/  /'
}

relaunch_row="(restore-selftest): after the Dock relaunched, its preferences still equal the backup"

run_selftest
has_line "PASS QA - $relaunch_row" ||
  fail "a relaunch that changes nothing doesn't pass the compare (status $status):"$'\n'"$(rows)"
((status == 0)) || fail "a clean self-test exits $status"
domain_is_original || fail "a clean self-test leaves the domain changed"

run_selftest RELAUNCH_WRITES=qa-relaunch-key
has_line "PASS QA - $relaunch_row" &&
  fail "a relaunch that writes a key passes the compare:"$'\n'"$(rows)"
grep -q '^FAIL QA - (restore-selftest): .*qa-relaunch-key' <<<"$output" ||
  fail "a relaunch that writes a key isn't a FAIL naming the key:"$'\n'"$(rows)"
((status == 1)) || fail "a self-test with a failed compare exits $status, not 1"

printf '#!/bin/sh\necho "usage: qa-helper preferences-change LIVE.plist BACKUP.plist" >&2\nexit 2\n' \
  >"$scratch/broken-helper"
chmod +x "$scratch/broken-helper"
run_selftest HELPER="$scratch/broken-helper"
has_line "PASS QA - $relaunch_row" &&
  fail "a helper that fails passes the compare:"$'\n'"$(rows)"
grep -q '^FAIL QA - (restore-selftest)' <<<"$output" ||
  fail "a helper that fails records no FAIL:"$'\n'"$(rows)"
((status == 1)) || fail "a self-test whose helper fails exits $status, not 1"

run_selftest FAIL_IMPORTS=1
has_line "FAIL QA - (restore-selftest): the restore succeeds and verifies" ||
  fail "a failed self-test restore isn't reported:"$'\n'"$(rows)"
grep -q '^osascript' "$scratch/calls.log" &&
  fail "after a failed self-test restore, the run went on to change the Dock: $(cat "$scratch/calls.log")"
((status == 1)) || fail "a run whose self-test restore fails exits $status, not 1"
domain_is_original || fail "cleanup didn't restore the domain after a failed self-test restore"
[[ ! -e $scratch/qa/dock-backup.plist ]] ||
  fail "cleanup's restore after a failed self-test restore kept the backup"

run_selftest INTERRUPT_ON_SLEEP=1
((status == 130)) || fail "a Ctrl-C during the self-test exits $status, not 130"
grep -q '^FAIL QA' <<<"$output" &&
  fail "a Ctrl-C after a successful self-test restore records a FAIL:"$'\n'"$(rows)"
has_line "the Dock wasn't restored" &&
  fail "a Ctrl-C after a successful self-test restore says the Dock wasn't restored"
domain_is_original || fail "a Ctrl-C after a successful self-test restore leaves the domain changed"

exit "$failed"
