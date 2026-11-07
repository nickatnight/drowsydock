#!/usr/bin/env bash
# Runs the checks from CONSTRAINTS.md.
#
#   scripts/check.sh fast   compile, format, secrets (run after every edit)
#   scripts/check.sh task   fast + tests, coverage gate, bundle (run before every commit)
#
# The coverage gate compares against the merge base with $CHECK_BASE (default: main).
set -euo pipefail
cd "$(dirname "$0")/.."

mode="${1:-}"
case "$mode" in
  fast | task) ;;
  *)
    echo "usage: scripts/check.sh fast|task" >&2
    exit 2
    ;;
esac

coverage_minimum=80
coverage_exempt_imports='^import (AppKit|ApplicationServices|Cocoa|IOKit|ServiceManagement|SpriteKit|SwiftUI)'

shopt -s nullglob

step() { printf '\n==> %s\n' "$*"; }

gated_files() {
  local file
  for file in Sources/SleepyBatteryCore/*.swift; do
    echo "$file"
  done
  for file in Sources/DockOverlayKit/*.swift; do
    grep -Eq "$coverage_exempt_imports" "$file" || echo "$file"
  done
}

changed_lines() {
  local merge_base="$1"
  shift
  git diff -U0 --no-color "$merge_base" -- "$@" | awk '
    /^\+\+\+ b\// { file = substr($0, 7); next }
    /^@@/ {
      split(substr($3, 2), range, ",")
      count = (range[2] == "" ? 1 : range[2])
      for (i = 0; i < count; i++) print file, range[1] + i
    }'
  local file
  while IFS= read -r file; do
    awk -v file="$file" '{ print file, NR }' "$file"
  done < <(git ls-files --others --exclude-standard -- "$@")
}

coverage_gate() {
  local merge_base bin_path lcov changed file
  merge_base="$(git merge-base "${CHECK_BASE:-main}" HEAD)"
  bin_path="$(swift build --show-bin-path)"
  lcov="$(mktemp)"
  changed="$(mktemp)"
  trap 'rm -f "$lcov" "$changed"' RETURN

  local files=()
  while IFS= read -r file; do files+=("$file"); done < <(gated_files)
  if ((${#files[@]} == 0)); then
    echo "No gated files yet."
    return 0
  fi

  xcrun llvm-cov export -format=lcov \
    -instr-profile "$bin_path/codecov/default.profdata" \
    "$bin_path/SleepyBatteryPackageTests.xctest/Contents/MacOS/SleepyBatteryPackageTests" \
    >"$lcov"
  changed_lines "$merge_base" "${files[@]}" >"$changed"

  awk -v root="$PWD/" -v minimum="$coverage_minimum" '
    NR == FNR { changed[$1 SUBSEP $2] = 1; next }
    /^SF:/ {
      file = substr($0, 4)
      if (index(file, root) == 1) file = substr(file, length(root) + 1)
      next
    }
    /^DA:/ {
      split(substr($0, 4), entry, ",")
      if (!((file SUBSEP entry[1]) in changed)) next
      total++
      if (entry[2] > 0) hit++
      else missed[file] = missed[file] " " entry[1]
    }
    END {
      if (total == 0) { print "No executable changed lines in gated files."; exit 0 }
      percent = hit * 100 / total
      printf "Changed-line coverage: %d/%d = %.1f%% (minimum %d%%)\n", hit, total, percent, minimum
      for (f in missed) print "  uncovered " f ":" missed[f]
      exit (percent < minimum)
    }' "$changed" "$lcov"
}

step "Compile (Swift 6, warnings are errors)"
swift build --build-tests -Xswiftc -warnings-as-errors

step "Format"
swift format lint --strict --recursive Sources Tests

step "Secrets"
gitleaks detect --redact --no-banner
# `detect` reads only commits, so also scan the uncommitted and untracked working-tree files.
leaks=0
while IFS= read -r -d '' file; do
  [[ -f $file ]] || continue
  gitleaks dir --redact --no-banner --log-level warn "$file" || leaks=1
done < <(git ls-files --cached --others --exclude-standard -z)
((leaks == 0)) || exit 1

if [[ $mode == fast ]]; then
  step "fast checks passed"
  exit 0
fi

step "Tests (with coverage)"
swift test --enable-code-coverage

step "Coverage of changed lines"
coverage_gate

step "Bundle"
scripts/bundle.sh
codesign --verify --strict build/SleepyBattery.app
plutil -lint Resources/Info.plist

step "task checks passed"
