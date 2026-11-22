#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
scratch="$(mktemp -d)"
git_ignored_file="build/readme-selftest-$$.md"
trap 'rm -rf "$scratch"; rm -f "$git_ignored_file"' EXIT
mkdir -p build
: >"$git_ignored_file"

failed=0
index=0

copy_fixture() {
  index=$((index + 1))
  copy="$scratch/$index"
  mkdir -p "$copy/assets"
  cp README.md "$copy/README.md"
  cp docs/readme/* "$copy/assets/"
}

expect_outcome() {
  local name="$1" expected="$2" outcome=pass
  if ! README_ASSETS="$copy/assets" scripts/readme/check-readme.sh "$copy/README.md" \
    >/dev/null 2>&1; then
    outcome=fail
  fi
  if [[ $outcome != "$expected" ]]; then
    echo "check-readme-selftest: expected $name to $expected the check, but it did not" >&2
    failed=1
  fi
}

expect_readme_edit() {
  local name="$1" expected="$2" perl_edit="$3"
  copy_fixture
  perl -0pi -e "$perl_edit" "$copy/README.md"
  if cmp -s "$copy/README.md" README.md; then
    echo "check-readme-selftest: the plant '$name' changed nothing" >&2
    failed=1
    return
  fi
  expect_outcome "$name" "$expected"
}

expect_asset_flip() {
  local name="$1" asset="$2"
  copy_fixture
  perl -0pi -e 's/(.)\z/chr(ord($1) ^ 1)/se' "$copy/assets/$asset"
  expect_outcome "$name" fail
}

copy_fixture
expect_outcome "the unchanged README" pass
expect_readme_edit "a broken link inside a code block" pass \
  's/\n```sh\n/\n```sh\n[x](no-such-file.md)\n/'
expect_readme_edit "a link to a missing file" fail \
  's{\(docs/manual-qa\.md\)}{(docs/no-such-file.md)}'
expect_readme_edit "a missing image" fail \
  's{src="docs/readme/cat\.png"}{src="docs/readme/no-such-image.png"}'
expect_readme_edit "an anchor with no heading" fail \
  's{href="#requirements"}{href="#no-such-heading"}'
expect_readme_edit "a link to a file git ignores" fail "s{\\(CLAUDE\\.md\\)}{($git_ignored_file)}"
expect_asset_flip "a changed banner" banner.svg
expect_asset_flip "a changed header image" cat.png
exit "$failed"
