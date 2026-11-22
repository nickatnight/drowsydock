#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build || exit 1
git_ignored_file=""
scratch="$(mktemp -d)" || exit 1
trap 'rm -rf "$scratch"; rm -f "$git_ignored_file"' EXIT
git_ignored_file="$(mktemp build/readme-selftest-XXXXXX)" || exit 1

failed=0
plants=0

new_plant() {
  plants=$((plants + 1))
  copy="$scratch/$plants"
  mkdir -p "$copy/assets"
  cp README.md "$copy/README.md"
  cp docs/readme/* "$copy/assets/"
}

copy_references() {
  mkdir -p "$copy/references"
  cp Tests/DrowsyDockTests/Snapshots/pose-*-left.png "$copy/references/"
}

# run_plant NAME pass|fails MESSAGE|lacks MESSAGE [VAR=VALUE...]: runs the check on $copy in the
# background. A "fails" plant must fail and print MESSAGE; a "lacks" plant must not print MESSAGE.
run_plant() {
  local name="$1" mode="$2" message="" dir="$copy"
  shift 2
  if [[ $mode != pass ]]; then
    message="$1"
    shift
  fi
  printf '%s\n' "$name" >"$dir/name"
  printf '%s\n' "$mode" >"$dir/mode"
  printf '%s\n' "$message" >"$dir/message"
  (
    if env README_ASSETS="$dir/assets" "$@" scripts/readme/check-readme.sh "$dir/README.md" \
      >/dev/null 2>"$dir/stderr" </dev/null; then
      echo pass >"$dir/outcome"
    else
      echo fail >"$dir/outcome"
    fi
  ) &
}

# expect_readme_edit NAME MODE [MESSAGE] PERL_EDIT, with MODE and MESSAGE as run_plant takes them.
expect_readme_edit() {
  local name="$1" perl_edit="${!#}"
  new_plant
  perl -0pi -e "$perl_edit" "$copy/README.md"
  if cmp -s "$copy/README.md" README.md; then
    echo "check-readme-selftest: the plant '$name' changed nothing" >&2
    failed=1
    return
  fi
  run_plant "$name" "${@:2:$#-2}"
}

expect_banner_edit() {
  local name="$1" perl_edit="${!#}"
  new_plant
  perl -0pi -e "$perl_edit" "$copy/assets/banner.svg"
  if cmp -s "$copy/assets/banner.svg" docs/readme/banner.svg; then
    echo "check-readme-selftest: the plant '$name' changed nothing" >&2
    failed=1
    return
  fi
  run_plant "$name" "${@:2:$#-2}"
}

expect_asset_flip() {
  new_plant
  perl -0pi -e 's/(.)\z/chr(ord($1) ^ 1)/se' "$copy/assets/$2"
  run_plant "$1" fails "differs from"
}

# expect_source_edit NAME MODE [MESSAGE] FILE PERL_EDIT
expect_source_edit() {
  local name="$1" file="${@: -2:1}" perl_edit="${!#}" swift
  new_plant
  for swift in Sources/DrowsyDockCore/Thresholds.swift Sources/DrowsyDockCore/MascotPose.swift \
    Sources/DrowsyDockCore/CrowdWave.swift Sources/DrowsyDock/CrowdEffectNode.swift \
    Sources/DockOverlayKit/OverlayWindow.swift; do
    mkdir -p "$copy/sources/${swift%/*}"
    cp "$swift" "$copy/sources/$swift"
  done
  perl -0pi -e "$perl_edit" "$copy/sources/$file"
  if cmp -s "$copy/sources/$file" "$file"; then
    echo "check-readme-selftest: the plant '$name' changed nothing" >&2
    failed=1
    return
  fi
  run_plant "$name" "${@:2:$#-3}" README_SOURCES="$copy/sources"
}

export readme_selftest_dir="${PWD##*/}"

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
expect_readme_edit "a link to a missing file" fails "names no file" \
  's{\(docs/manual-qa\.md\)}{(docs/no-such-file.md)}'
expect_readme_edit "a missing image" fails "names no file" \
  's{src="docs/readme/cat\.png"}{src="docs/readme/no-such-image.png"}'
expect_readme_edit "a missing image in single quotes" fails "names no file" \
  "s{src=\"docs/readme/cat\\.png\"}{src='docs/readme/no-such-image.png'}"
expect_readme_edit "a missing reference-style target" fails "names no file" \
  's/\z/\n[ref]: docs\/no-such-file.md\n/'
expect_readme_edit "an anchor with no heading" fails "names no heading" \
  's{href="#requirements"}{href="#no-such-heading"}'
expect_readme_edit "a link to a file git ignores" fails "isn't in git's index" \
  "s{\\(CLAUDE\\.md\\)}{($git_ignored_file)}"
expect_readme_edit "a link that leaves the repo" fails "isn't in git's index" \
  's{\(CLAUDE\.md\)}{(../$ENV{readme_selftest_dir}/CLAUDE.md)}'
expect_readme_edit "a link in the wrong case" fails "isn't in git's index" \
  's{\(CLAUDE\.md\)}{(claude.md)}'
expect_asset_flip "a changed banner" banner.svg
expect_asset_flip "a changed header image" cat.png
expect_source_edit "a changed app value" fails "differs from" \
  Sources/DrowsyDock/CrowdEffectNode.swift \
  's/dimOpacity: CGFloat = 0\.35/dimOpacity: CGFloat = 0.4/'
expect_source_edit "a changed veil fade" fails "differs from" \
  Sources/DockOverlayKit/OverlayWindow.swift \
  's/fadeDuration: TimeInterval = 0\.2/fadeDuration: TimeInterval = 0.3/'
expect_source_edit "a threshold that leaves a banner level outside its pose" \
  fails "Thresholds.swift makes that band" Sources/DrowsyDockCore/Thresholds.swift \
  's/asleepBelow: 10/asleepBelow: 4/'
expect_readme_edit "an anchor that starts with a dash" fails "names no heading" \
  's{href="#requirements"}{href="#-vexyz"}'
expect_readme_edit "a link path that starts with a dash" fails "names no file" \
  's{\(CLAUDE\.md\)}{(--stdin)}'
expect_readme_edit "a broken link inside a plain fence" pass \
  's/\n## Docs\n/\n```\n[x](no-such-file.md)\n```\n\n## Docs\n/'
expect_readme_edit "headings GitHub slugs specially, a fragment on another file and a folder" pass \
  's/\n## Docs\n/\n## Debug ▸ Simulate (beta)\n\n## Requirements\n\n## See [docs](CLAUDE.md)\n\n## The `--qa-log` flag\n\n### DROWSYDOCK_SKIP_SNAPSHOTS\n\n## Docs ##\n\n[a](#debug--simulate-beta) [b](#requirements-1) [c](#see-docs) [d](#docs)\n[g](#the---qa-log-flag) [h](#drowsydock_skip_snapshots) [e](docs\/manual-qa.md#anything) [f](docs\/readme\/)\n/'
expect_readme_edit "headings with trailing spaces or a tab" pass \
  's/\n## Docs\n/\n## Spaced   \n\n## Tabbed\t\n\n[a](#spaced) [b](#tabbed)\n\n## Docs\n/'
expect_readme_edit "an anchor that keeps a heading's trailing spaces" fails "names no heading" \
  's/\n## Docs\n/\n## Spaced   \n\n[a](#spaced---)\n\n## Docs\n/'
expect_readme_edit "a footnote" pass \
  's/\n## Docs\n/\nA fact.[^1]\n\n[^1]: From Thresholds.swift.\n\n## Docs\n/'
new_plant
cp "$(git rev-parse --git-path index)" "$copy/index" || exit 1
GIT_INDEX_FILE="$copy/index" git rm --cached -q -- CLAUDE.md || exit 1
run_plant "a link to a file that is on disk but not in the index" fails "isn't in git's index" \
  GIT_INDEX_FILE="$copy/index"
expect_readme_edit "an anchor that is a prefix of a heading" fails "names no heading" \
  's{href="#requirements"}{href="#require"}'
expect_readme_edit "an anchor to a heading only inside a code block" fails "names no heading" \
  's/\n## Docs\n/\n```\n## Fake\n```\n\n[x](#fake)\n\n## Docs\n/'
expect_banner_edit "a banner with a script" fails "must not hold a script" \
  's{<style>}{<style><script>alert(1)</script>}'
expect_banner_edit "a banner that animates an href to javascript:" fails "must not hold a script" \
  's{</svg>}{<set attributeName="href" to="javascript:void(0)"/></svg>}'
expect_banner_edit "a banner that animates an href to a w3.org file" \
  fails "must not hold a script" \
  's{</svg>}{<set attributeName="href" to="http://www.w3.org/x.png"/></svg>}'
expect_banner_edit "a banner with an @import" fails "must not hold a script" \
  's{<style>}{<style>\@import "x.css";}'
expect_banner_edit "a banner with an empty image" fails "must not hold a script" \
  's{base64,[^"]*"}{base64,"}'
expect_banner_edit "a banner with an external url()" fails "must not hold a script" \
  's{<style>}{<style>.x { fill: url(x.svg#g) }}'
expect_banner_edit "a banner with an https reference" fails "must not hold a script" \
  's{</svg>}{<image href="https://example.com/x.png"/></svg>}'
expect_banner_edit "a banner with an uppercase HTTPS reference" fails "must not hold a script" \
  's{</svg>}{<image href="HTTPS://EXAMPLE.COM/X.PNG"/></svg>}'
expect_banner_edit "a banner with a protocol-relative reference" fails "must not hold a script" \
  's{</svg>}{<image href="//example.com/x.png"/></svg>}'
expect_banner_edit "a banner with an event handler" fails "must not hold a script" \
  's{<svg }{<svg onload="alert(1)" }'
expect_banner_edit "a banner with a foreignObject" fails "must not hold a script" \
  's{</svg>}{<foreignObject><p>x</p></foreignObject></svg>}'
expect_banner_edit "a banner with a relative image" fails "must not hold a script" \
  's{</svg>}{<image href="x.png"/></svg>}'
expect_banner_edit "a banner with a relative xlink:href" fails "must not hold a script" \
  's{</svg>}{<image xlink:href="../x.png"/></svg>}'
expect_banner_edit "a banner using a shape in another file" fails "must not hold a script" \
  's{</svg>}{<use href="other.svg#x"/></svg>}'
expect_banner_edit "a banner with a relative file name that starts with data" \
  fails "must not hold a script" 's{</svg>}{<image href="data.png"/></svg>}'
expect_banner_edit "a banner with an SVG data image" fails "must not hold a script" \
  's{</svg>}{<image href="data:image/svg+xml;base64,PHN2Zz4="/></svg>}'
expect_banner_edit "a banner with an empty href" fails "must not hold a script" \
  's{</svg>}{<use href=""/></svg>}'
expect_banner_edit "a banner with a url() into itself" lacks "must not hold a script" \
  's{<style>}{<style>.x { fill: url(#g) }}'
expect_banner_edit "a banner over 1 MB" fails "must stay under 1 MB" \
  's{</svg>}{"<!--" . ("x" x 1000000) . "-->\n</svg>"}e'
new_plant
copy_references
perl -0pi -e 's/(.)\z/chr(ord($1) ^ 1)/se' "$copy/references/pose-asleep-left.png"
run_plant "a changed pose reference" fails "differs from" README_REFERENCES="$copy/references"
new_plant
copy_references
ln -sf "$PWD/docs/readme/cat.png" "$copy/references/pose-yawning-left.png"
run_plant "a reference that is a symlink to a PNG" fails "must be a regular PNG file" \
  README_REFERENCES="$copy/references"
new_plant
copy_references
printf 'not a png\n' >"$copy/references/pose-yawning-left.png"
run_plant "a reference that isn't a PNG" fails "must be a regular PNG file" \
  README_REFERENCES="$copy/references"
expect_readme_edit "a link with a control character" fails "x?::error::hi names no file" \
  's{src="docs/readme/cat\.png"}{src="x\r::error::hi"}'
wait

checked=0
for dir in "$scratch"/*/; do
  [[ -e $dir/name ]] || continue
  checked=$((checked + 1))
  name="$(cat "$dir/name")"
  mode="$(cat "$dir/mode")"
  message="$(cat "$dir/message")"
  outcome="$(cat "$dir/outcome")"
  case "$mode" in
    pass)
      if [[ $outcome != pass ]]; then
        echo "check-readme-selftest: expected $name to pass the check, but it failed:" >&2
        cat "$dir/stderr" >&2
        failed=1
      fi
      ;;
    fails)
      if [[ $outcome != fail ]] || ! grep -qF -- "$message" "$dir/stderr"; then
        echo "check-readme-selftest: expected $name to fail the check with \"$message\";" \
          "it ${outcome}ed:" >&2
        cat "$dir/stderr" >&2
        failed=1
      fi
      ;;
    lacks)
      if grep -qF -- "$message" "$dir/stderr"; then
        echo "check-readme-selftest: expected $name not to print \"$message\"" >&2
        failed=1
      fi
      ;;
    *)
      echo "check-readme-selftest: $name has no mode pass, fails or lacks: \"$mode\"" >&2
      failed=1
      ;;
  esac
done
if ((checked != plants)); then
  echo "check-readme-selftest: checked $checked of $plants plants" >&2
  failed=1
fi
exit "$failed"
