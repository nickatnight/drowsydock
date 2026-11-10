#!/usr/bin/env bash
# Proves that `scripts/qa-live.sh --dry-run` touches nothing: every command that could change the
# Dock, the app, the pointer, the screen or the log is replaced by a stub that records its call, and
# the dry run must call none of them, create no build/qa folder, and still print every scenario and
# the Dock-restore command. scripts/check.sh fast runs it.
set -euo pipefail
cd "$(dirname "$0")/../.."

stubs="$(mktemp -d)"
trap 'rm -rf "$stubs"' EXIT
calls="$stubs/calls.log"
: >"$calls"
for tool in defaults killall osascript open screencapture log sample top pmset plutil swift; do
  printf '#!/bin/sh\necho "%s $*" >>"%s"\nexit 1\n' "$tool" "$calls" >"$stubs/$tool"
  chmod +x "$stubs/$tool"
done

had_qa_dir=false
[[ -e build/qa ]] && had_qa_dir=true
output="$(PATH="$stubs:$PATH" scripts/qa-live.sh --dry-run 2>&1)"

failed=0
if [[ -s $calls ]]; then
  echo "qa-live.sh --dry-run ran commands it must only print:" >&2
  cat "$calls" >&2
  failed=1
fi
if ! $had_qa_dir && [[ -e build/qa ]]; then
  echo "qa-live.sh --dry-run created build/qa" >&2
  failed=1
fi
while IFS= read -r name; do
  if ! grep -Eq "^==> $name( |:|$)" <<<"$output"; then
    echo "qa-live.sh --dry-run never reaches the $name scenario" >&2
    failed=1
  fi
done < <(scripts/qa-live.sh --list | cut -d' ' -f1)
for expected in "==> Preflight" "defaults import com.apple.dock" "would run: defaults export com.apple.dock"; do
  if ! grep -qF -- "$expected" <<<"$output"; then
    echo "qa-live.sh --dry-run doesn't print: $expected" >&2
    failed=1
  fi
done
selftest="$(PATH="$stubs:$PATH" scripts/qa-live.sh --dry-run --only restore-selftest 2>&1)"
if ! grep -q "^==> Preflight" <<<"$selftest" || grep -q "DrowsyDock.app" <<<"$selftest"; then
  echo "qa-live.sh --only restore-selftest must run its preflight and leave the app alone" >&2
  failed=1
fi
if [[ -s $calls ]]; then
  echo "qa-live.sh --dry-run --only restore-selftest ran commands:" >&2
  cat "$calls" >&2
  failed=1
fi
exit "$failed"
