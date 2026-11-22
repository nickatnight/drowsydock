#!/usr/bin/env bash
# Plants faults in scratch copies of the README, docs/readme/ and the app's Swift values, and
# expects check-readme.sh to fail on each with the right message; the clean plants must pass. The
# plants run in parallel.
set -uo pipefail
cd "$(dirname "$0")/../.."
scratch="$(mktemp -d)"
git_ignored_file="build/readme-selftest-$$.md"
trap 'rm -rf "$scratch"; rm -f "$git_ignored_file"' EXIT
mkdir -p build
: >"$git_ignored_file"

failed=0
plants=0

# Makes the next plant's scratch copy of the README and docs/readme/, and points $copy at it.
new_plant() {
  plants=$((plants + 1))
  copy="$scratch/$plants"
  mkdir -p "$copy/assets"
  cp README.md "$copy/README.md"
  cp docs/readme/* "$copy/assets/"
}

# run_plant NAME EXPECTED [VAR=VALUE...]: runs the check on $copy in the background. EXPECTED is
# "pass", or the message the check must print when it fails.
run_plant() {
  local name="$1" expected="$2" dir="$copy"
  shift 2
  printf '%s\n' "$name" >"$dir/name"
  printf '%s\n' "$expected" >"$dir/expected"
  (
    if env README_ASSETS="$dir/assets" "$@" scripts/readme/check-readme.sh "$dir/README.md" \
      >/dev/null 2>"$dir/stderr" </dev/null; then
      echo pass >"$dir/outcome"
    else
      echo fail >"$dir/outcome"
    fi
  ) &
}

expect_readme_edit() {
  local name="$1" expected="$2" perl_edit="$3"
  new_plant
  perl -0pi -e "$perl_edit" "$copy/README.md"
  if cmp -s "$copy/README.md" README.md; then
    echo "check-readme-selftest: the plant '$name' changed nothing" >&2
    failed=1
    return
  fi
  run_plant "$name" "$expected"
}

expect_asset_flip() {
  new_plant
  perl -0pi -e 's/(.)\z/chr(ord($1) ^ 1)/se' "$copy/assets/$2"
  run_plant "$1" "differs from"
}

# expect_source_edit NAME EXPECTED FILE PERL_EDIT: edits a scratch copy of one of the Swift files
# banner.sh reads.
expect_source_edit() {
  local name="$1" expected="$2" file="$3" perl_edit="$4" swift
  new_plant
  for swift in Sources/DrowsyDockCore/Thresholds.swift Sources/DrowsyDockCore/MascotPose.swift \
    Sources/DrowsyDockCore/CrowdWave.swift Sources/DrowsyDock/CrowdEffectNode.swift; do
    mkdir -p "$copy/sources/${swift%/*}"
    cp "$swift" "$copy/sources/$swift"
  done
  perl -0pi -e "$perl_edit" "$copy/sources/$file"
  if cmp -s "$copy/sources/$file" "$file"; then
    echo "check-readme-selftest: the plant '$name' changed nothing" >&2
    failed=1
    return
  fi
  run_plant "$name" "$expected" README_SOURCES="$copy/sources"
}

new_plant
run_plant "the unchanged README" pass
expect_readme_edit "a broken link inside a code block" pass \
  's/\n```sh\n/\n```sh\n[x](no-such-file.md)\n/'
expect_readme_edit "a broken link inside a ~~~ fence" pass \
  's/\n## Docs\n/\n~~~\n[x](no-such-file.md)\n~~~\n\n## Docs\n/'
expect_readme_edit "a broken link inside inline code" pass \
  's/\n## Docs\n/\nWrite `[x](no-such-file.md)` or `<img src="nope.png">`.\n\n## Docs\n/'
expect_readme_edit "a broken link inside an HTML comment" pass \
  's/\n## Docs\n/\n<!-- [x](no-such-file.md) -->\n\n## Docs\n/'
expect_readme_edit "a link from the repo root" pass 's{\(CLAUDE\.md\)}{(/CLAUDE.md)}'
expect_readme_edit "a link to a missing file" "names no file" \
  's{\(docs/manual-qa\.md\)}{(docs/no-such-file.md)}'
expect_readme_edit "a missing image" "names no file" \
  's{src="docs/readme/cat\.png"}{src="docs/readme/no-such-image.png"}'
expect_readme_edit "a missing image in single quotes" "names no file" \
  "s{src=\"docs/readme/cat\\.png\"}{src='docs/readme/no-such-image.png'}"
expect_readme_edit "a missing reference-style target" "names no file" \
  's/\z/\n[ref]: docs\/no-such-file.md\n/'
expect_readme_edit "an anchor with no heading" "names no heading" \
  's{href="#requirements"}{href="#no-such-heading"}'
expect_readme_edit "a link to a file git ignores" "isn't in git's index" \
  "s{\\(CLAUDE\\.md\\)}{($git_ignored_file)}"
expect_readme_edit "a link that leaves the repo" "isn't in git's index" \
  "s{\\(CLAUDE\\.md\\)}{(../${PWD##*/}/CLAUDE.md)}"
expect_readme_edit "a link in the wrong case" "isn't in git's index" \
  's{\(CLAUDE\.md\)}{(claude.md)}'
expect_asset_flip "a changed banner" banner.svg
expect_asset_flip "a changed header image" cat.png
expect_source_edit "a changed app value" "differs from" Sources/DrowsyDock/CrowdEffectNode.swift \
  's/dimOpacity: CGFloat = 0\.35/dimOpacity: CGFloat = 0.4/'
expect_source_edit "a threshold that leaves a banner level outside its pose" \
  "Thresholds.swift makes that band" Sources/DrowsyDockCore/Thresholds.swift \
  's/asleepBelow: 10/asleepBelow: 4/'
wait

for dir in "$scratch"/*/; do
  [[ -e $dir/name ]] || continue
  name="$(cat "$dir/name")"
  expected="$(cat "$dir/expected")"
  outcome="$(cat "$dir/outcome")"
  if [[ $expected == pass ]]; then
    if [[ $outcome != pass ]]; then
      echo "check-readme-selftest: expected $name to pass the check, but it failed:" >&2
      cat "$dir/stderr" >&2
      failed=1
    fi
  elif [[ $outcome != fail ]] || ! grep -qF -- "$expected" "$dir/stderr"; then
    echo "check-readme-selftest: expected $name to fail the check with \"$expected\";" \
      "it ${outcome}ed" >&2
    failed=1
  fi
done
exit "$failed"
