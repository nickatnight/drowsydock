#!/usr/bin/env bash
# Builds a DrowsyDock release: signed with Developer ID, notarized, stapled and zipped into dist/.
#
#   scripts/release.sh            the owner's release; needs DEVELOPER_ID and NOTARY_PROFILE
#   scripts/release.sh --dry-run  the same build signed ad hoc, with every Apple step skipped
#   scripts/release.sh --help     this text
#
# DEVELOPER_ID is the certificate's name: "Developer ID Application: Emgee Labs LLC (TEAMID)".
# NOTARY_PROFILE names a keychain profile saved by `xcrun notarytool store-credentials`. Neither
# is a secret, and the script takes no Apple ID, password or API key. docs/release.md has the
# setup and the whole release sequence. Agents run only --dry-run.
#
# A release needs a clean tree and the tag v<CFBundleShortVersionString> at HEAD. A dry run warns
# about both instead, and needs no variables, network or keychain.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  sed -n '3,5p' "$0" | sed 's/^# \{0,1\}//'
}

dry_run=false
while (($#)); do
  case "$1" in
    --dry-run) dry_run=true ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
  shift
done

die() {
  echo "release.sh: $*" >&2
  exit 1
}

warn() {
  echo "release.sh: warning: $*" >&2
}

step() { printf '\n==> %s\n' "$*"; }

identity_prefix="Developer ID Application:"
version_pattern='^[0-9]+(\.[0-9]+){0,2}$'

step "Preflight"
if $dry_run; then
  echo "Dry run: signed ad hoc; the Developer ID, notarization, stapling and Gatekeeper steps are skipped."
else
  if [[ -z ${DEVELOPER_ID:-} ]]; then
    die "DEVELOPER_ID is not set. Set it to your certificate's name, such as" \
      "\"$identity_prefix Emgee Labs LLC (TEAMID)\"; docs/release.md explains."
  fi
  if [[ -z ${NOTARY_PROFILE:-} ]]; then
    die "NOTARY_PROFILE is not set. Set it to the keychain profile you saved with" \
      "\`xcrun notarytool store-credentials\`; docs/release.md explains."
  fi
  if [[ $DEVELOPER_ID != "$identity_prefix"* ]]; then
    die "DEVELOPER_ID is \"$DEVELOPER_ID\"; a release is signed by a certificate whose name" \
      "starts with \"$identity_prefix\" (docs/release.md)."
  fi
fi

if ! command -v ditto >/dev/null; then die "ditto is missing; it zips the app."; fi
if ! $dry_run; then
  for tool in notarytool stapler; do
    if ! xcrun --find "$tool" >/dev/null 2>&1; then
      die "xcrun can't find $tool; install Xcode and select it with xcode-select."
    fi
  done
  if ! command -v spctl >/dev/null; then die "spctl is missing; it runs the Gatekeeper check."; fi

  identities="$(security find-identity -v -p codesigning)" ||
    die "security find-identity -v -p codesigning failed."
  if ! grep -qF -- "\"$DEVELOPER_ID\"" <<<"$identities"; then
    die "no valid signing identity named \"$DEVELOPER_ID\" in your keychain" \
      "(security find-identity -v -p codesigning); docs/release.md explains how to create it."
  fi
fi

version="$(plutil -extract CFBundleShortVersionString raw -o - Resources/Info.plist)" ||
  die "can't read CFBundleShortVersionString from Resources/Info.plist."
if [[ ! $version =~ $version_pattern ]]; then
  die "CFBundleShortVersionString in Resources/Info.plist is \"$version\"; a release needs one to" \
    "three numbers separated by dots, such as 1.2.0."
fi
tag="v$version"

# Untracked files count, because SwiftPM compiles any Swift file under Sources.
changes="$(git status --porcelain --untracked-files=all)" || die "git status failed."
if [[ -n $changes ]]; then
  message="the working tree has uncommitted changes:"$'\n'"$changes"
  if $dry_run; then warn "$message"; else die "$message"$'\n'"Commit or stash them first."; fi
fi
head_commit="$(git rev-parse HEAD)" || die "git rev-parse HEAD failed."
tag_commit="$(git rev-parse -q --verify "refs/tags/$tag^{commit}" || true)"
if [[ $tag_commit != "$head_commit" ]]; then
  if [[ -z $tag_commit ]]; then
    message="there is no tag $tag for version $version."
  else
    message="the tag $tag is not at HEAD."
  fi
  if $dry_run; then
    warn "$message"
  else
    die "$message Tag the release commit with \`git tag -a $tag\` (docs/release.md)."
  fi
fi
echo "Preflight passed for version $version."

if ! $dry_run; then
  die "the build, notarization and packaging steps are not written yet."
fi
