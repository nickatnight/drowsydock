#!/usr/bin/env bash
# Runs the checks from CONSTRAINTS.md.
#
#   scripts/check.sh fast   compile, format, floor rules, secrets (run after every edit)
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

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

step() { printf '\n==> %s\n' "$*"; }

# Prints the Swift files tracked or untracked (not ignored) under the given directories, at any
# depth. A git pathspec `*` matches across `/`.
swift_files_under() {
  local dir file
  for dir in "$@"; do
    while IFS= read -r -d '' file; do
      if [[ -f $file ]]; then echo "$file"; fi
    done < <(git ls-files --cached --others --exclude-standard -z -- "$dir/*.swift")
  done
}

gated_files() {
  local file
  swift_files_under Sources/SleepyBatteryCore
  while IFS= read -r file; do
    grep -Eq "$coverage_exempt_imports" "$file" || echo "$file"
  done < <(swift_files_under Sources/DockOverlayKit)
}

floor_rules() {
  local failed=0
  if grep -rnF 'try!' Sources; then
    echo "Floor: try! outside tests" >&2
    failed=1
  fi
  if grep -rnE 'fatalError\("(TODO|not implemented)' Sources Tests; then
    echo "Floor: unimplemented stub" >&2
    failed=1
  fi
  if grep -rnE 'catch[[:space:]]*\{[[:space:]]*\}' Sources Tests; then
    echo "Floor: empty catch" >&2
    failed=1
  fi
  # A suppression needs a `//` comment on its own line or the line above, explaining why.
  if swift_files_under Sources Tests | xargs awk '
    FNR == 1 { previous = "" }
    /swift-format-ignore|@preconcurrency|nonisolated\(unsafe\)|@unchecked Sendable/ &&
      $0 !~ /\/\/.*[[:alpha:]]/ && previous !~ /^[[:space:]]*\/\// {
      print FILENAME ":" FNR ": " $0
      found = 1
    }
    { previous = $0 }
    END { exit !found }'; then
    echo "Floor: suppression without an explaining comment" >&2
    failed=1
  fi
  if ! grep -Eq '^  dependencies: \[\],?$' Package.swift; then
    echo "Floor: Package.swift must declare empty package dependencies" >&2
    failed=1
  fi
  return "$failed"
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
  lcov="$work/coverage.lcov"
  changed="$work/changed-lines.txt"

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

step "Floor rules"
floor_rules

step "Secrets"
gitleaks detect --redact --no-banner
# `detect` reads only commits, so also scan a copy of the uncommitted and untracked working-tree
# files. One `gitleaks dir` run over the copy skips build output and ignored files.
mkdir "$work/tree"
while IFS= read -r -d '' file; do
  if [[ -f $file ]]; then printf '%s\0' "$file"; fi
done < <(git ls-files --cached --others --exclude-standard -z) |
  tar -cf - --null -T - | tar -xf - -C "$work/tree"
gitleaks dir --redact --no-banner --log-level warn "$work/tree"

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
