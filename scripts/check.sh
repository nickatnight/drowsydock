#!/usr/bin/env bash
# Runs the checks from CONSTRAINTS.md.
#
#   scripts/check.sh fast   compile, format, the live QA script's checks (dry run, Dock restore,
#                           log reads), the release script's syntax, floor rules, the QA row
#                           mapping, the README (links, images, banner), secrets (every edit)
#   scripts/check.sh task   fast + tests, coverage gate, bundle, and the release dry run with the
#                           app in its zip checked (run before every commit)
#
# The release dry run runs with shims that refuse security, spctl, notarytool and stapler, and
# `fast` fails if release.sh, bundle.sh or verify-signature.sh names a command by its full path,
# which would get past them. Nothing runs the real release's Apple steps.
#
# The coverage gate compares against the merge base with $CHECK_BASE (default: main). It also
# writes the gated files' coverage to .build/coverage/lcov.info, which CI uploads to Codecov.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

mode="${1:-}"
case "$mode" in
  fast | task) ;;
  *)
    echo "usage: scripts/check.sh fast|task" >&2
    exit 2
    ;;
esac

coverage_minimum=80
coverage_report=.build/coverage/lcov.info
gated_targets=(Sources/DrowsyDockCore Sources/DockOverlayKit Sources/LiveQAKit)
# An import may carry attributes (`@preconcurrency`, `@_exported`, `@_spi(Name)`), an access level
# (`internal import`) and a kind (`import class AppKit.NSColor`). HIServices holds the AX API, and
# Carbon and Quartz re-export AX and AppKit.
coverage_exempt_imports='^[[:space:]]*(@[[:alnum:]_]+(\([^)]*\))?[[:space:]]+)*((public|package|internal|fileprivate|private)[[:space:]]+)?import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?(AppKit|ApplicationServices|Carbon|Cocoa|HIServices|IOKit|Quartz|ServiceManagement|SpriteKit|SwiftUI)([.[:space:]]|$)'

unified_log_imports='^[[:space:]]*(@[[:alnum:]_]+(\([^)]*\))?[[:space:]]+)*((public|package|internal|fileprivate|private)[[:space:]]+)?import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?(os|OSLog)([.[:space:]]|$)'

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# Exiting from these traps runs the EXIT trap, so a killed run still deletes the working-tree copy.
trap 'exit 129' HUP
trap 'exit 143' TERM

# NUL-delimited, so names with blanks, quotes or backslashes survive. Listed once at the top
# level, where `set -e` stops the run if git fails.
git ls-files --cached --others --exclude-standard -z >"$work/files"

swift_files_under() {
  local dir file
  for dir in "$@"; do
    while IFS= read -r -d '' file; do
      if [[ $file == "$dir"/*.swift && -f $file ]]; then printf '%s\0' "$file"; fi
    done <"$work/files"
  done
}

is_gated() {
  local target
  for target in "${gated_targets[@]}"; do
    if [[ $1 == "$target"/* ]]; then
      ! found_or_abort grep -Eq "$coverage_exempt_imports" "$1"
      return
    fi
  done
  return 1
}

gated_files() {
  local file
  while IFS= read -r -d '' file; do
    if is_gated "$file"; then printf '%s\0' "$file"; fi
  done < <(swift_files_under Sources)
}

coverage_exempt_files_are_in_manual_qa() {
  local file name failed=0
  while IFS= read -r -d '' file; do
    if is_gated "$file"; then continue; fi
    name="$(basename "$file" .swift)"
    if ! found_or_abort grep -qF "\`$name\`" docs/manual-qa.md; then
      echo "Manual QA: $file is exempt from coverage but docs/manual-qa.md never names \`$name\`" >&2
      failed=1
    fi
  done < <(swift_files_under Sources)
  return "$failed"
}

scan_swift_files() {
  local file files=()
  while IFS= read -r -d '' file; do files+=("$file"); done < <(swift_files_under Sources Tests)
  if ((${#files[@]} == 0)); then return 1; fi
  found_or_abort awk "$1" "${files[@]}"
}

unexplained_suppressions='
  function suppresses_a_check(line) {
    return line ~ /@preconcurrency|nonisolated\(unsafe\)|@unchecked Sendable/
  }
  function is_comment(line) { return line ~ /^[[:space:]]*\/\// }
  function is_format_directive(line) {
    return line ~ /^[[:space:]]*\/\/[[:space:]]*swift-format-ignore/
  }
  # A plain // comment with words in it. A /// doc comment, a directive or a MARK is not a reason.
  function is_reason(line) {
    return line ~ /^[[:space:]]*\/\/[^\/]/ && line !~ /swift-format-ignore/ &&
      line !~ /^[[:space:]]*\/\/[[:space:]]*MARK:/ && line ~ /[[:alpha:]]/
  }
  function has_trailing_reason(line) { return line ~ /(^|[^\/])\/\/[^\/]*[[:alpha:]]/ }
  function report() { print FILENAME ":" FNR ": " $0; found = 1 }
  FNR == 1 { previous = "" }
  is_format_directive($0) && !is_reason(previous) { report() }
  !is_comment($0) && suppresses_a_check($0) && !has_trailing_reason($0) && !is_reason(previous) {
    report()
  }
  { previous = $0 }
  END { exit !found }'

empty_catches='
  function is_empty_catch(line) {
    return line ~ /(^|[^[:alnum:]_])catch([[:space:]][^{]*)?\{[[:space:]]*\}/
  }
  function opens_catch_block(line) {
    return line ~ /(^|[^[:alnum:]_])catch([[:space:]][^{]*)?\{[[:space:]]*$/
  }
  function is_blank(line) { return line ~ /^[[:space:]]*$/ }
  function closes_block(line) { return line ~ /^[[:space:]]*\}/ }
  function report(line, text) { print FILENAME ":" line ": " text; found = 1 }
  FNR == 1 { catch_line = 0 }
  catch_line && is_blank($0) { next }
  catch_line && closes_block($0) { report(catch_line, catch_text) }
  { catch_line = 0 }
  is_empty_catch($0) { report(FNR, $0) }
  opens_catch_block($0) { catch_line = FNR; catch_text = $0 }
  END { exit !found }'

floor_rules() {
  local failed=0
  if found_or_abort grep -rnF 'try!' Sources; then
    echo "Floor: try! outside tests" >&2
    failed=1
  fi
  if found_or_abort grep -rnE 'fatalError\("(TODO|not implemented)' Sources Tests; then
    echo "Floor: unimplemented stub" >&2
    failed=1
  fi
  if scan_swift_files "$empty_catches"; then
    echo "Floor: empty catch" >&2
    failed=1
  fi
  if scan_swift_files "$unexplained_suppressions"; then
    echo "Floor: suppression without an explaining comment" >&2
    failed=1
  fi
  if found_or_abort grep -rnE "$unified_log_imports" Sources --exclude=MirroredLogger.swift ||
    found_or_abort grep -rnF 'NSLog(' Sources; then
    echo "Logging: log through MirroredLogger, so a --qa-log run mirrors every line (ADR 0020)" >&2
    failed=1
  fi
  if found_or_abort grep -rnE "$coverage_exempt_imports" Sources/DrowsyDockCore; then
    echo "Boundary: DrowsyDockCore must not import system UI or hardware frameworks" >&2
    failed=1
  fi
  if ! found_or_abort grep -Eq '^  dependencies: \[\],?$' Package.swift; then
    echo "Floor: Package.swift must declare empty package dependencies" >&2
    failed=1
  fi
  return "$failed"
}

# The name goes to awk through the environment, because `awk -v` expands backslash escapes.
changed_lines() {
  local merge_base="$1" file
  while IFS= read -r -d '' file; do
    if git --literal-pathspecs ls-files --error-unmatch -- "$file" >/dev/null 2>&1; then
      git --literal-pathspecs diff -U0 --no-color "$merge_base" -- "$file" | FILE="$file" awk '
        /^@@/ {
          split(substr($3, 2), range, ",")
          count = (range[2] == "" ? 1 : range[2])
          for (i = 0; i < count; i++) print ENVIRON["FILE"] "\t" (range[1] + i)
        }'
    else
      FILE="$file" awk '{ print ENVIRON["FILE"] "\t" NR }' "$file"
    fi
  done
}

# lcov paths may use the logical or the physical (symlink-resolved) checkout path. Callers pass
# both through the environment, because `awk -v` expands backslash escapes.
repo_relative_path='
  function repo_relative(file, logical, physical) {
    if (index(file, physical) == 1) return substr(file, length(physical) + 1)
    if (index(file, logical) == 1) return substr(file, length(logical) + 1)
    return ""
  }'

write_coverage_report() {
  local gated="$1" lcov="$2"
  mkdir -p "$(dirname "$coverage_report")"
  tr '\0' '\n' <"$gated" >"$work/gated-list"
  LOGICAL="$PWD/" PHYSICAL="$(pwd -P)/" awk "$repo_relative_path"'
    BEGIN { logical = ENVIRON["LOGICAL"]; physical = ENVIRON["PHYSICAL"] }
    FILENAME == ARGV[1] { gated[$0] = 1; next }
    /^SF:/ {
      file = repo_relative(substr($0, 4), logical, physical)
      keep = (file in gated)
      if (keep) print "SF:" file
      next
    }
    keep { print }
    /^end_of_record$/ { keep = 0 }' "$work/gated-list" "$lcov" >"$coverage_report"
}

coverage_gate() {
  local merge_base bin_path lcov changed gated
  merge_base="$(git merge-base "${CHECK_BASE:-main}" HEAD)"
  bin_path="$(swift build --show-bin-path)"
  lcov="$work/coverage.lcov"
  changed="$work/changed-lines.txt"
  gated="$work/gated-files"

  gated_files >"$gated"
  if [[ ! -s $gated ]]; then
    echo "No gated files yet."
    return 0
  fi

  # The native build system links every test target into one DrowsyDockPackageTests bundle;
  # Swift Build (the default from Swift 6.4) builds a bundle per test target. Take them all.
  local bundle objects=()
  for bundle in "$bin_path"/*.xctest; do
    [[ -d $bundle ]] || continue
    if ((${#objects[@]} > 0)); then objects+=(-object); fi
    objects+=("$bundle/Contents/MacOS/$(basename "$bundle" .xctest)")
  done
  if ((${#objects[@]} == 0)); then
    echo "Coverage gate: no test bundle under $bin_path."
    return 1
  fi

  xcrun llvm-cov export -format=lcov \
    -instr-profile "$bin_path/codecov/default.profdata" \
    "${objects[@]}" \
    >"$lcov"
  write_coverage_report "$gated" "$lcov"
  changed_lines "$merge_base" <"$gated" >"$changed"

  # The changed lines come first; `FILENAME == ARGV[1]` still holds when that file is empty, unlike
  # NR == FNR.
  LOGICAL="$PWD/" PHYSICAL="$(pwd -P)/" MINIMUM="$coverage_minimum" \
    awk -F '\t' "$repo_relative_path"'
    BEGIN { logical = ENVIRON["LOGICAL"]; physical = ENVIRON["PHYSICAL"]; minimum = ENVIRON["MINIMUM"] }
    FILENAME == ARGV[1] { changed[$1 SUBSEP $2] = 1; changed_files[$1] = 1; next }
    /^SF:/ {
      file = repo_relative(substr($0, 4), logical, physical)
      if (file == "") next
      under_root++
      recorded[file] = 1
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
      if (under_root == 0) {
        print "Coverage gate: no lcov file lies under " physical "; the path mapping is broken."
        exit 2
      }
      for (f in changed_files) {
        if (f in recorded) continue
        print "Coverage gate: " f " has changed lines but no lcov record. Link its target into a test target, or give it executable code."
        unrecorded = 1
      }
      if (unrecorded) exit 1
      if (total == 0) { print "No executable changed lines in gated files."; exit 0 }
      percent = hit * 100 / total
      printf "Changed-line coverage: %d/%d = %.1f%% (minimum %d%%)\n", hit, total, percent, minimum
      for (f in missed) print "  uncovered " f ":" missed[f]
      exit (percent < minimum)
    }' "$changed" "$lcov" || return

  if ! found_or_abort grep -q '^SF:' "$coverage_report"; then
    echo "Coverage gate: $coverage_report holds no gated file, so CI would upload an empty report."
    return 2
  fi
}

# refuse_release_only_tools DIR LOG: writes security, spctl and xcrun shims into DIR. Each call
# to security, spctl, xcrun notarytool or xcrun stapler is appended to LOG and exits 1, so a
# `|| true` can't hide it; any other xcrun call runs the real one.
refuse_release_only_tools() {
  local dir="$1" log="$2"
  mkdir "$dir"
  cat >"$dir/security" <<EOF
#!/bin/sh
echo "\${0##*/} \$*" >>"$log"
exit 1
EOF
  cp "$dir/security" "$dir/spctl"
  cat >"$dir/xcrun" <<EOF
#!/bin/sh
for arg in "\$@"; do
  case "\$arg" in notarytool | stapler) echo "xcrun \$*" >>"$log"; exit 1 ;; esac
done
exec /usr/bin/xcrun "\$@"
EOF
  chmod +x "$dir"/*
}

step "Compile (Swift 6, warnings are errors)"
swift build --build-tests -Xswiftc -warnings-as-errors

step "Format"
swift format lint --strict --recursive Sources Tests

step "Live QA script (syntax, a dry run that must touch nothing, the Dock restore on a scratch domain, the log reads over a fixture QA log)"
bash -n scripts/qa-live.sh
scripts/qa/check-dry-run.sh
scripts/qa/check-dock-restore.sh
scripts/qa/check-app-log.sh

step "Release script (syntax, no command by full path, bundle.sh's refusals; task runs the dry run)"
bash -n scripts/release.sh
if calls_by_full_path scripts/release.sh scripts/bundle.sh scripts/verify-signature.sh scripts/lib.sh
then
  echo "Release script: a command named by its full path gets past the dry run's shims" >&2
  exit 1
fi
# Each refusal exits 2 before bundle.sh builds or deletes anything. If one regresses, the `swift`
# shim stops bundle.sh at its first build step with 97, so the check itself builds nothing.
mkdir "$work/no-swift"
printf '#!/bin/sh\nexit 97\n' >"$work/no-swift/swift"
chmod +x "$work/no-swift/swift"
for setting in SIGN_TIMESTAMP=yes BUNDLE_DIR=../outside BUNDLE_DIR=build/../outside; do
  status=0
  PATH="$work/no-swift:$PATH" env SIGN_IDENTITY=- SIGN_TIMESTAMP=0 "$setting" scripts/bundle.sh \
    >/dev/null 2>&1 || status=$?
  if ((status != 2)); then
    echo "Release script: scripts/bundle.sh with $setting exits $status, not 2" >&2
    exit 1
  fi
done

step "Floor rules"
floor_rules
coverage_exempt_files_are_in_manual_qa
scripts/qa/check-qa-mapping.sh

step "README (every relative link and image resolves, the banner matches the snapshot references and the app)"
scripts/readme/check-readme.sh

step "Secrets"
# gitleaks matches text, so binary signing material needs its own check.
signing_files="$(git ls-files --cached --others --exclude-standard -- \
  ':(icase)*.p12' ':(icase)*.pfx' ':(icase)*.cer' ':(icase)*.der' ':(icase)*.p8' \
  ':(icase)*.pem' ':(icase)*.key' ':(icase)*.keychain' ':(icase)*.keychain-db' \
  ':(icase)*.mobileprovision' ':(icase)*.provisionprofile')"
if [[ -n $signing_files ]]; then
  echo "Secrets: signing material must never be committed:" >&2
  echo "$signing_files" >&2
  exit 1
fi
gitleaks detect --redact --no-banner -v
# `detect` reads only commits, so also scan a copy of the uncommitted and untracked working-tree
# files. One `gitleaks dir` run over the copy skips build output and ignored files. A finding's
# path starts with the deleted temp copy (`…/tree/`); drop that prefix to get the path in the repo.
mkdir "$work/tree"
while IFS= read -r -d '' file; do
  if [[ -f $file ]]; then printf '%s\0' "$file"; fi
done <"$work/files" |
  tar -cf - --null -T - | tar -xf - -C "$work/tree"
gitleaks dir --redact --no-banner --log-level warn -v "$work/tree"

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
scripts/verify-signature.sh build/DrowsyDock.app
# An in-place ad-hoc rebuild keeps the CDHash, so the dry run is checked against the binary's inode
# and modification time instead.
dev_binary=build/DrowsyDock.app/Contents/MacOS/DrowsyDock
dev_binary_stat="$(stat -f '%i %m' "$dev_binary")"
plutil -lint Resources/Info.plist

step "Release dry run (scripts/release.sh --dry-run with Apple's services and the keychain refused, then the app in its zip)"
refuse_release_only_tools "$work/refuse" "$work/refused"
# A Developer ID in the environment must not reach the dry run's codesign.
developer_id='Developer ID Application: Example (TEAMID)'
release_status=0
DEVELOPER_ID="$developer_id" SIGN_IDENTITY="$developer_id" PATH="$work/refuse:$PATH" \
  scripts/release.sh --dry-run || release_status=$?
if [[ -s $work/refused ]]; then
  echo "Release dry run: it called tools that only a real release may call:" >&2
  cat "$work/refused" >&2
  exit 1
fi
((release_status == 0)) || exit "$release_status"
if [[ $(stat -f '%i %m' "$dev_binary") != "$dev_binary_stat" ]]; then
  echo "Release dry run: it rebuilt build/DrowsyDock.app; it must build only in build/release" >&2
  exit 1
fi
release_version="$(plutil -extract CFBundleShortVersionString raw -o - Resources/Info.plist)"
release_zip="dist/DrowsyDock-$release_version-dryrun.zip"
(cd dist && shasum -a 256 -s -c "${release_zip#dist/}.sha256")
mkdir "$work/release"
ditto -x -k "$release_zip" "$work/release"
scripts/verify-signature.sh "$work/release/DrowsyDock.app"
dry_run_signature="$(codesign -dv "$work/release/DrowsyDock.app" 2>&1)"
if ! grep -qx 'Signature=adhoc' <<<"$dry_run_signature" ||
  grep -q '^Timestamp=' <<<"$dry_run_signature"; then
  echo "Release dry run: the zipped app must be signed ad hoc with no timestamp" >&2
  exit 1
fi

step "task checks passed"
