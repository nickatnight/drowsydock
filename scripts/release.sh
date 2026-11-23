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
#
# It can't tell in advance whether Apple accepts the upload, or whether Gatekeeper on another Mac
# opens the downloaded zip; the owner checks the first real release by hand (docs/manual-qa.md).
# scripts/release/check-release-selftest.sh runs it against stub tools.
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
  echo "Dry run: signed ad hoc, and the Developer ID, notarization, stapling and Gatekeeper" \
    "steps are skipped."
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

app="build/DrowsyDock.app"
if $dry_run; then
  artifact="dist/DrowsyDock-$version-dryrun.zip"
else
  artifact="dist/DrowsyDock-$version.zip"
fi
checksum="$artifact.sha256"
rm -f "$artifact" "$checksum" "$artifact.partial" "$checksum.partial"
work="$(mktemp -d)"
trap 'rm -rf "$work"; rm -f "$artifact.partial" "$checksum.partial"' EXIT

step "Build"
if $dry_run; then
  SIGN_IDENTITY=- SIGN_TIMESTAMP=0 scripts/bundle.sh
else
  SIGN_IDENTITY="$DEVELOPER_ID" SIGN_TIMESTAMP=1 scripts/bundle.sh
fi

step "Verify the signature"
codesign --verify --strict --deep "$app" ||
  die "codesign --verify --strict --deep rejects $app."
signature="$(codesign -dv --verbose=4 "$app" 2>&1)" || die "codesign -dv can't read $app."
if ! grep -Eq '^CodeDirectory .*flags=0x[0-9a-f]+\([^)]*runtime' <<<"$signature"; then
  die "the signature lacks the hardened runtime (codesign --options runtime)."
fi
entitlements="$(codesign -d --entitlements - --xml "$app" 2>/dev/null)" ||
  die "codesign can't read the entitlements of $app."
if [[ -n $entitlements ]]; then
  die "the signature carries entitlements; a release is signed with none (ADR 0007):" \
    "$entitlements"
fi
archs=" $(lipo -archs "$app/Contents/MacOS/DrowsyDock") " || die "lipo can't read the binary."
for arch in arm64 x86_64; do
  if [[ $archs != *" $arch "* ]]; then
    die "the binary lacks $arch (lipo -archs:$archs); a release is universal."
  fi
done
echo "Strict verification, the hardened runtime, no entitlements, arm64 and x86_64: passed."
if $dry_run; then
  echo "skipped (dry run): the Developer ID authority, TeamIdentifier and timestamp checks"
else
  # codesign lists the chain from the signing certificate up to Apple's root.
  authority="$(grep -m 1 '^Authority=' <<<"$signature" || true)"
  if [[ $authority != "Authority=$identity_prefix"* ]]; then
    die "the signature's first authority is \"${authority#Authority=}\", not a" \
      "$identity_prefix certificate."
  fi
  team="$(sed -n 's/^TeamIdentifier=//p' <<<"$signature")"
  if [[ -z $team || $team == "not set" ]]; then
    die "the signature has no TeamIdentifier."
  fi
  if ! grep -q '^Timestamp=' <<<"$signature"; then
    die "the signature has no secure timestamp, which notarization requires (bundle.sh" \
      "SIGN_TIMESTAMP=1)."
  fi
  echo "${authority#Authority=}, TeamIdentifier, secure timestamp: passed."
fi

step "Notarize"
if $dry_run; then
  echo "skipped (dry run): xcrun notarytool submit"
else
  ditto -c -k --keepParent "$app" "$work/DrowsyDock.zip"
  echo "Submitting to Apple's notary service and waiting for its answer, which can take minutes."
  submit_status=0
  submission="$(xcrun notarytool submit "$work/DrowsyDock.zip" \
    --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)" || submit_status=$?
  answer="$(grep '^{' <<<"$submission" | tail -n 1 || true)"
  notary_status="$(plutil -extract status raw -o - - <<<"$answer" 2>/dev/null || true)"
  submission_id="$(plutil -extract id raw -o - - <<<"$answer" 2>/dev/null || true)"
  if [[ -z $notary_status ]]; then
    die "notarytool submit exited $submit_status without a status:"$'\n'"$submission"
  fi
  if [[ $notary_status != Accepted ]]; then
    echo "release.sh: notarization ended with status $notary_status. Apple's log:" >&2
    if [[ $submission_id =~ ^[0-9A-Fa-f-]+$ ]]; then
      xcrun notarytool log "$submission_id" --keychain-profile "$NOTARY_PROFILE" >&2 ||
        echo "(notarytool log failed)" >&2
      die "fix what the log names and release again. To read the log again:" \
        "xcrun notarytool log $submission_id --keychain-profile $NOTARY_PROFILE"
    fi
    die "the answer names no submission id:"$'\n'"$submission"
  fi
  echo "Accepted (submission $submission_id)."
fi

step "Staple and assess"
if $dry_run; then
  echo "skipped (dry run): xcrun stapler staple"
  echo "skipped (dry run): xcrun stapler validate"
  echo "skipped (dry run): spctl --assess --type execute"
else
  xcrun stapler staple "$app" || die "xcrun stapler staple failed."
  xcrun stapler validate "$app" || die "xcrun stapler validate rejects the stapled ticket."
  assessment="$(spctl --assess --type execute -v "$app" 2>&1)" ||
    die "Gatekeeper rejected $app:"$'\n'"$assessment"
  if ! grep -qF 'source=Notarized Developer ID' <<<"$assessment"; then
    die "spctl doesn't report source=Notarized Developer ID:"$'\n'"$assessment"
  fi
  echo "Stapled, validated, and Gatekeeper reports source=Notarized Developer ID."
fi

step "Package"
mkdir -p dist
ditto -c -k --keepParent "$app" "$artifact.partial"
hash="$(shasum -a 256 <"$artifact.partial")"
printf '%s  %s\n' "${hash%% *}" "${artifact#dist/}" >"$checksum.partial"
mv -f "$checksum.partial" "$checksum"
mv -f "$artifact.partial" "$artifact"
echo "$artifact"
echo "$checksum"
if $dry_run; then
  echo "A dry run's zip is signed ad hoc and not notarized; it is not for distribution."
else
  echo "Publish it with the gh release create command in docs/release.md."
fi
