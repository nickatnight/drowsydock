#!/usr/bin/env bash
# Proves that scripts/readme/check-readme.sh catches what it is for: each plant breaks one thing
# in a scratch copy of the README or of docs/readme/, and the check must fail on it. The unchanged
# copies, and a broken link inside a code block, must pass.
set -uo pipefail
cd "$(dirname "$0")/../.."
scratch="$(mktemp -d)"
# A file that exists but that git ignores, as docs/adr/ is on the owner's Mac.
ignored="build/readme-selftest-$$.md"
trap 'rm -rf "$scratch"; rm -f "$ignored"' EXIT
mkdir -p build
: >"$ignored"

failed=0
index=0

# check NAME EXPECTED README_EDIT [ASSET_FILE]: copies README.md and docs/readme/, applies the perl
# README_EDIT to the README copy, flips the last byte of ASSET_FILE in the docs/readme/ copy if
# one is given, and checks that the README check exits as EXPECTED (pass or fail).
check() {
  local name="$1" expected="$2" edit="$3" asset="${4:-}" copy outcome=pass
  index=$((index + 1))
  copy="$scratch/$index"
  mkdir -p "$copy/assets"
  cp README.md "$copy/README.md"
  cp docs/readme/* "$copy/assets/"
  if [[ -n $edit ]]; then
    perl -0pi -e "$edit" "$copy/README.md"
    if cmp -s "$copy/README.md" README.md; then
      echo "check-readme-selftest: the plant '$name' changed nothing" >&2
      failed=1
      return
    fi
  fi
  if [[ -n $asset ]]; then
    perl -0pi -e 's/(.)\z/chr(ord($1) ^ 1)/se' "$copy/assets/$asset"
  fi
  if ! README_ASSETS="$copy/assets" scripts/readme/check-readme.sh "$copy/README.md" \
    >/dev/null 2>&1; then
    outcome=fail
  fi
  if [[ $outcome != "$expected" ]]; then
    echo "check-readme-selftest: expected $name to $expected the check, but it did not" >&2
    failed=1
  fi
}

check "the unchanged README" pass ""
check "a broken link inside a code block" pass 's/\n```sh\n/\n```sh\n[x](no-such-file.md)\n/'
check "a link to a missing file" fail 's{\(docs/manual-qa\.md\)}{(docs/no-such-file.md)}'
check "a missing image" fail 's{src="docs/readme/cat\.png"}{src="docs/readme/no-such-image.png"}'
check "an anchor with no heading" fail 's{href="#requirements"}{href="#no-such-heading"}'
check "a link to a file git ignores" fail "s{\\(CLAUDE\\.md\\)}{($ignored)}"
check "a changed banner" fail "" banner.svg
check "a changed header image" fail "" cat.png
exit "$failed"
