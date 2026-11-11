#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

failed=0

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

planted=()

# plant NAME FILE EDIT: copies the doc and the row list, applies the perl EDIT to FILE in the copy,
# and checks the copy in the background.
plant() {
  local index=$((${#planted[@]} + 1)) target
  planted+=("$1")
  copy "$index"
  target="$scratch/$index/$2"
  perl -pi -e "$3" "$target"
  if cmp -s "$target" "docs/$2"; then
    echo "check-qa-mapping-selftest: the plant '$1' changed nothing" >&2
    failed=1
    return
  fi
  (check_copy "$index" && touch "$scratch/$index/passed") &
}

wave='`AppCoordinatorTests\.testLaunchingAsleepPlaysNoWave`'
plant "a missing method" manual-qa.md "s/$wave/\`AppCoordinatorTests.testNoSuchThing\`/"
plant "an unknown class" manual-qa.md "s/$wave/\`NoSuchTests\`/"
plant "prose in the Tests cell" manual-qa.md "s/$wave/\`the coordinator tests\`/"
plant "a method under the wrong class" manual-qa.md \
  "s/$wave/\`PoseSnapshotTests.testLaunchingAsleepPlaysNoWave\`/"
plant "an unknown scenario" manual-qa.md 's/(\| 7\.9 \|.*)`cpu`/$1`cpus`/'
plant "a non-scenario token in the Live column" manual-qa.md \
  's/(\| 7\.9 \|.*)`cpu`/$1`CPU scenario`/'
plant "a scenario that does not list the row" manual-qa.md 's/(\| 1\.1 \|.*)`launch`/$1`cpu`/'
plant "a row with no citation" manual-qa.md 's/^(\| 11\.8 \|[^|]*\|)[^|]*\|[^|]*\|$/$1 – | – |/'
plant "a deleted row" manual-qa.md 's/^\| 11\.8 \|.*\n//'
plant "a renumbered row" manual-qa.md 's/^\| 11\.8 \|/| 11.9 |/'
plant "a row missing from the list" qa-rows.txt 's/^11\.8\n//'
wait

index=0
for name in "${planted[@]}"; do
  index=$((index + 1))
  if [[ -e $scratch/$index/passed ]]; then
    echo "check-qa-mapping-selftest: the check missed $name" >&2
    failed=1
  fi
done
exit "$failed"
