#!/usr/bin/env bash
# Shows that scripts/qa/check-qa-mapping.sh catches each kind of error: it plants one at a time in
# a copy of docs/manual-qa.md (or of docs/qa-rows.txt) and expects the check to fail, and expects
# the unchanged copy to pass. scripts/check.sh fast runs it.
set -uo pipefail
cd "$(dirname "$0")/../.."
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

failed=0

# copy NAME: a fresh copy of the doc and the row list in their own folder.
copy() {
  mkdir -p "$scratch/$1"
  cp docs/manual-qa.md docs/qa-rows.txt "$scratch/$1/"
}

check_copy() {
  scripts/qa/check-qa-mapping.sh "$scratch/$1/manual-qa.md" "$scratch/$1/qa-rows.txt" >/dev/null 2>&1
}

copy unchanged
if ! check_copy unchanged; then
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
# The checks run side by side, each on its own copy; the results are read once all have ended.
index=0
for plant in "${plants[@]}"; do
  index=$((index + 1))
  name="${plant%%|*}"
  edit="${plant#*|}"
  copy "$index"
  target="$scratch/$index/manual-qa.md"
  if [[ $name == rows:* ]]; then
    target="$scratch/$index/qa-rows.txt"
  fi
  perl -pi -e "$edit" "$target"
  if cmp -s "$target" "docs/$(basename "$target")"; then
    echo "check-qa-mapping-selftest: the plant '${name#rows:}' changed nothing" >&2
    failed=1
    continue
  fi
  (check_copy "$index" && touch "$scratch/$index/passed") &
done
wait
index=0
for plant in "${plants[@]}"; do
  index=$((index + 1))
  if [[ -e $scratch/$index/passed ]]; then
    name="${plant%%|*}"
    echo "check-qa-mapping-selftest: the check missed ${name#rows:}" >&2
    failed=1
  fi
done
exit "$failed"
