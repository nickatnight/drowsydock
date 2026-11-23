#!/usr/bin/env bash
# Proves that `scripts/qa-live.sh --dry-run` touches nothing. Every command that could change the
# Dock, the app, the pointer, the screen or a file is a stub on PATH that records its call, the
# helper is a recording stub through QA_HELPER, and QA_DIR points at a folder that must stay
# absent. The run must call no stub, print no UNGUARDED line (qa-live.sh's own backstop for a
# step that forgot run_or_print), and still reach every scenario and print the restore command.
set -euo pipefail
cd "$(dirname "$0")/../.."

stubs="$(mktemp -d)"
trap '/bin/rm -rf "$stubs"' EXIT
calls="$stubs/calls.log"
: >"$calls"
for tool in defaults killall osascript open screencapture log sample top pmset plutil swift rm \
  mkdir mv kill pkill cmp qa-helper; do
  printf '#!/bin/sh\necho "%s $*" >>"%s"\nexit 1\n' "$tool" "$calls" >"$stubs/$tool"
  chmod +x "$stubs/$tool"
done
# The folder exists and starts empty, as build/qa does on the owner's Mac after a first run, so
# a redirect into it would succeed; nothing may appear in it.
qa_dir="$stubs/qa"
mkdir "$qa_dir"
home="$stubs/home"
mkdir "$home"

dry_run() {
  PATH="$stubs:$PATH" HOME="$home" QA_HELPER="$stubs/qa-helper" QA_DIR="$qa_dir" \
    scripts/qa-live.sh "$@" 2>&1
}

failed=0

# A command named by its full path, such as /usr/bin/defaults, would skip both the PATH stubs and
# the UNGUARDED functions. Only the read-only PlistBuddy may be named that way.
if grep -nE '(^|[[:space:];|&(`])/(usr/)?(s)?bin/' scripts/qa-live.sh scripts/qa/live-functions.sh \
  scripts/qa/dock-preferences.sh |
  grep -v '^[^:]*:1:#!'; then
  echo "qa-live.sh names a command by its full path; call it by name so the dry run can stub it" >&2
  failed=1
fi

report_calls() {
  if [[ -s $calls ]]; then
    echo "qa-live.sh $1 ran commands it must only print:" >&2
    cat "$calls" >&2
    failed=1
    : >"$calls"
  fi
  if grep -q UNGUARDED <<<"$2"; then
    echo "qa-live.sh $1 reached commands outside run_or_print:" >&2
    grep UNGUARDED <<<"$2" >&2
    failed=1
  fi
  local folder
  for folder in "$qa_dir" "$home"; do
    if [[ -n $(ls -A "$folder") ]]; then
      echo "qa-live.sh $1 wrote into $folder:" >&2
      ls -AR "$folder" >&2
      failed=1
    fi
  done
}

output="$(dry_run --dry-run)"
report_calls --dry-run "$output"
while IFS= read -r name; do
  if ! grep -Eq "^==> $name( |:|$)" <<<"$output"; then
    echo "qa-live.sh --dry-run never reaches the $name scenario" >&2
    failed=1
  fi
done < <(scripts/qa-live.sh --list | cut -d' ' -f1)
for expected in "==> Preflight" "defaults import com.apple.dock" \
  "would run: defaults export com.apple.dock" "DrowsyDock.app --args --qa-log" \
  "would read the lines DrowsyDock appends to $(id -P | cut -d: -f9)/Library/Logs/DrowsyDock/qa.log"; do
  if ! grep -qF -- "$expected" <<<"$output"; then
    echo "qa-live.sh --dry-run doesn't print: $expected" >&2
    failed=1
  fi
done

exit "$failed"
