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
check "a link to a file git ignores" fail "s{\\(CLAUDE\\.md\\)}{($git_ignored_file)}"
check "a changed banner" fail "" banner.svg
check "a changed header image" fail "" cat.png
exit "$failed"
