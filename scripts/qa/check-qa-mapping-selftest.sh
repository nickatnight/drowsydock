#!/usr/bin/env bash
# Shows that scripts/qa/check-qa-mapping.sh catches each kind of error: it plants one at a time in
# a copy of docs/manual-qa.md (or of docs/qa-rows.txt) and expects the check to fail, and expects
# the unchanged copy to pass. scripts/check.sh fast runs it.
set -uo pipefail
cd "$(dirname "$0")/../.."
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

failed=0
check_copy() {
  scripts/qa/check-qa-mapping.sh "$scratch/manual-qa.md" "$scratch/qa-rows.txt" >/dev/null 2>&1
}

fresh() {
  cp docs/manual-qa.md "$scratch/manual-qa.md"
  cp docs/qa-rows.txt "$scratch/qa-rows.txt"
}

fresh
if ! check_copy; then
  echo "check-qa-mapping-selftest: the unchanged doc fails the check" >&2
  failed=1
fi

# Each plant: a name, then a perl substitution for the doc, or for the row list with "rows:".
plants=(
  'a missing method|s/`AppCoordinatorTests\.testLaunchingAsleepPlaysNoWave`/`AppCoordinatorTests.testNoSuchThing`/'
  'an unknown class|s/`AppCoordinatorTests\.testLaunchingAsleepPlaysNoWave`/`NoSuchTests`/'
  'prose in the Tests cell|s/`AppCoordinatorTests\.testLaunchingAsleepPlaysNoWave`/`the coordinator tests`/'
  'a method under the wrong class|s/`AppCoordinatorTests\.testLaunchingAsleepPlaysNoWave`/`PoseSnapshotTests.testLaunchingAsleepPlaysNoWave`/'
  'an unknown scenario|s/(\| 7\.9 \|.*)`cpu`/$1`cpus`/'
  'a non-scenario token in the Live column|s/(\| 7\.9 \|.*)`cpu`/$1`CPU scenario`/'
  'a scenario that does not list the row|s/(\| 1\.1 \|.*)`launch`/$1`cpu`/'
  'a row with no citation|s/^(\| 11\.8 \|[^|]*\|)[^|]*\|[^|]*\|$/$1 – | – |/'
  'a deleted row|s/^\| 11\.8 \|.*\n//'
  'a renumbered row|s/^\| 11\.8 \|/| 11.9 |/'
  'rows:a row missing from the list|s/^11\.8\n//'
)
for plant in "${plants[@]}"; do
  name="${plant%%|*}"
  edit="${plant#*|}"
  fresh
  target="$scratch/manual-qa.md"
  if [[ $name == rows:* ]]; then
    target="$scratch/qa-rows.txt"
    name="${name#rows:}"
  fi
  perl -pi -e "$edit" "$target"
  if cmp -s "$target" "docs/$(basename "$target")"; then
    echo "check-qa-mapping-selftest: the plant '$name' changed nothing" >&2
    failed=1
  elif check_copy; then
    echo "check-qa-mapping-selftest: the check missed $name" >&2
    failed=1
  fi
done
exit "$failed"
