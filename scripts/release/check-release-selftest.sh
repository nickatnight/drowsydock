#!/usr/bin/env bash
# Runs scripts/release.sh against stub tools, with no network, certificate, keychain or real build.
#
# Each case copies release.sh, bundle.sh, Resources/Info.plist and .gitignore into a fresh scratch
# git repository tagged v1.2.3, so the run's build/ and dist/ land there. The run starts from an
# empty environment (env -i), so DEVELOPER_ID or NOTARY_PROFILE in your shell can't leak in. Its
# PATH holds the stubs in scripts/release/stubs, then links to /usr/bin, /bin, /usr/sbin and /sbin
# without the real codesign, xcrun, security, spctl, lipo, swift, iconutil and ditto. ditto, which
# only zips, comes back through its own folder, so a case can leave it out; so can spctl's stub.
# Each stub appends its call to calls.log and refuses any call it doesn't know.
#
# It can't check that the stubs answer as Apple's tools do; docs/release.md asks the owner to
# report any difference on the first real run.
set -uo pipefail
cd "$(dirname "$0")/../.."
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

failed=0
fail() {
  echo "check-release-selftest: $1" >&2
  failed=1
}

# A command named by its full path would skip the stubs.
if grep -nE '(^|[[:space:];|&(`])/(usr/)?(s)?bin/' scripts/release.sh scripts/bundle.sh |
  grep -v '^[^:]*:1:#!'; then
  fail "release.sh or bundle.sh names a command by its full path; call it by name so the stubs apply"
fi

system="$scratch/system"
mkdir -p "$system" "$scratch/stubs" "$scratch/spctl" "$scratch/ditto" "$scratch/home" "$scratch/tmp"
for dir in /usr/bin /bin /usr/sbin /sbin; do
  ln -s "$dir"/* "$system/" 2>/dev/null
done
for tool in codesign xcrun security spctl lipo swift iconutil ditto notarytool stapler; do
  rm -f "$system/$tool"
done
ln -s /usr/bin/ditto "$scratch/ditto/ditto"
for stub in scripts/release/stubs/*; do
  if [[ ${stub##*/} == spctl ]]; then
    cp "$stub" "$scratch/spctl/"
  else
    cp "$stub" "$scratch/stubs/"
  fi
done
chmod +x "$scratch"/stubs/* "$scratch/spctl/spctl"

scratch_git() {
  HOME="$scratch/home" GIT_CONFIG_NOSYSTEM=1 git -c user.name=selftest \
    -c user.email=selftest@example.invalid -c commit.gpgsign=false -c tag.gpgsign=false "$@"
}

template="$scratch/template"
{
  mkdir -p "$template/scripts" "$template/Resources" &&
    cp -p scripts/release.sh scripts/bundle.sh "$template/scripts/" &&
    cp Resources/Info.plist "$template/Resources/" &&
    cp .gitignore "$template/" &&
    plutil -replace CFBundleShortVersionString -string 1.2.3 "$template/Resources/Info.plist" &&
    scratch_git -C "$template" init -q &&
    scratch_git -C "$template" add -A &&
    scratch_git -C "$template" commit -qm "Release 1.2.3" &&
    scratch_git -C "$template" tag -a v1.2.3 -m "DrowsyDock 1.2.3"
} || exit 1

identity="Developer ID Application: Emgee Labs LLC (TEAMID)"
release_env=("DEVELOPER_ID=$identity" NOTARY_PROFILE=drowsydock-notary)

cases=0
repo=""
calls=""
output=""
status=0

# new_repo: a fresh copy of the tagged scratch repository in $repo, for a case to change first.
new_repo() {
  cases=$((cases + 1))
  repo="$scratch/case-$cases"
  cp -R "$template" "$repo"
  calls="$repo.calls"
  : >"$calls"
}

# run_release [VAR=VALUE...] [-- ARG...]: runs $repo's release.sh. NO_DITTO=1 and NO_SPCTL=1 leave
# those tools off PATH; any other VAR=VALUE goes into the run's environment. Sets $status and
# $output (stdout and stderr together).
run_release() {
  local vars=() path
  local with_ditto=true with_spctl=true
  while (($#)) && [[ $1 != -- ]]; do
    case "$1" in
      NO_DITTO=1) with_ditto=false ;;
      NO_SPCTL=1) with_spctl=false ;;
      *) vars+=("$1") ;;
    esac
    shift
  done
  if (($#)); then shift; fi
  path="$scratch/stubs"
  if $with_spctl; then path="$path:$scratch/spctl"; fi
  if $with_ditto; then path="$path:$scratch/ditto"; fi
  path="$path:$system"
  status=0
  output="$(cd "$repo" && env -i HOME="$scratch/home" TMPDIR="$scratch/tmp" PATH="$path" \
    GIT_CONFIG_NOSYSTEM=1 STUB_LOG="$calls" STUB_IDENTITY="$identity" \
    ${vars[@]+"${vars[@]}"} scripts/release.sh "$@" 2>&1)" || status=$?
  if grep -q '^refused:' "$calls"; then
    fail "case $cases called a stub with arguments it doesn't know: $(grep '^refused:' "$calls")"
  fi
}

report() {
  printf '%s (exit %s)\n--- output\n%s\n--- calls\n%s\n' "$1" "$status" "$output" "$(cat "$calls")"
}

has_output() { grep -qF -- "$1" <<<"$output"; }
called() { grep -qE -- "$1" "$calls"; }

# expect_preflight_failure NAME TEXT...: the run failed before building, and its output names
# every TEXT.
expect_preflight_failure() {
  local name="$1" text
  shift
  if ((status == 0)); then
    fail "$(report "$name passes")"
    return
  fi
  for text in "$@"; do
    has_output "$text" || fail "$(report "$name fails without naming $text")"
  done
  if called '^(swift|codesign) '; then
    fail "$(report "$name still builds or signs")"
  fi
}

# MARK: - Arguments

new_repo
run_release -- --help
((status == 0)) && has_output "--dry-run" || fail "$(report "--help doesn't print the usage")"

new_repo
run_release -- --sign-later
((status == 2)) && has_output "--dry-run" ||
  fail "$(report "an unknown argument isn't a usage error with exit 2")"

# MARK: - Preflight of a real run

new_repo
run_release NOTARY_PROFILE=drowsydock-notary
expect_preflight_failure "a run without DEVELOPER_ID" DEVELOPER_ID docs/release.md

new_repo
run_release DEVELOPER_ID= NOTARY_PROFILE=drowsydock-notary
expect_preflight_failure "a run with an empty DEVELOPER_ID" DEVELOPER_ID docs/release.md

new_repo
run_release "DEVELOPER_ID=$identity"
expect_preflight_failure "a run without NOTARY_PROFILE" NOTARY_PROFILE docs/release.md

new_repo
run_release "DEVELOPER_ID=Apple Development: Emgee Labs LLC (TEAMID)" \
  NOTARY_PROFILE=drowsydock-notary
expect_preflight_failure "a run with an Apple Development identity" "Developer ID Application:"

new_repo
run_release "${release_env[@]}" "STUB_IDENTITY=Developer ID Application: Someone Else (OTHERID)"
expect_preflight_failure "a run whose identity isn't in the keychain" "$identity" find-identity

new_repo
echo "changed" >>"$repo/Resources/Info.plist"
run_release "${release_env[@]}"
expect_preflight_failure "a run with a modified file" "Resources/Info.plist"

new_repo
touch "$repo/Untracked.swift"
run_release "${release_env[@]}"
expect_preflight_failure "a run with an untracked file" "Untracked.swift"

new_repo
scratch_git -C "$repo" tag -d v1.2.3 >/dev/null
run_release "${release_env[@]}"
expect_preflight_failure "a run without the tag" v1.2.3

new_repo
scratch_git -C "$repo" commit -q --allow-empty -m "After the tag"
run_release "${release_env[@]}"
expect_preflight_failure "a run whose tag isn't at HEAD" v1.2.3

new_repo
run_release "${release_env[@]}" STUB_MISSING=notarytool
expect_preflight_failure "a run without notarytool" notarytool

new_repo
run_release "${release_env[@]}" STUB_MISSING=stapler
expect_preflight_failure "a run without stapler" stapler

new_repo
run_release "${release_env[@]}" NO_DITTO=1
expect_preflight_failure "a run without ditto" ditto

new_repo
run_release "${release_env[@]}" NO_SPCTL=1
expect_preflight_failure "a run without spctl" spctl

new_repo
plutil -replace CFBundleShortVersionString -string "1.2/../../x" "$repo/Resources/Info.plist"
scratch_git -C "$repo" commit -qam "A version that isn't one"
run_release "${release_env[@]}"
expect_preflight_failure "a run with a version that isn't numbers" CFBundleShortVersionString

new_repo
run_release "${release_env[@]}"
has_output "Preflight passed" || fail "$(report "a run with everything in place fails its preflight")"

# MARK: - Preflight of a dry run

new_repo
echo "changed" >>"$repo/Resources/Info.plist"
scratch_git -C "$repo" tag -d v1.2.3 >/dev/null
run_release "DEVELOPER_ID=not an identity" STUB_MISSING="notarytool stapler" NO_SPCTL=1 -- \
  --dry-run
if ! has_output "Preflight passed" || ! has_output "Resources/Info.plist" ||
  ! has_output "v1.2.3"; then
  fail "$(report "a dry run with a dirty tree, no tag, no Apple tools and a junk DEVELOPER_ID \
doesn't pass its preflight with a warning for the tree and the tag")"
fi
if called '^security '; then
  fail "$(report "a dry run reads the keychain")"
fi

new_repo
run_release NO_DITTO=1 -- --dry-run
expect_preflight_failure "a dry run without ditto" ditto

exit "$failed"
