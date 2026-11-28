#!/usr/bin/env bash
#   scripts/verify-signature.sh APP
#
# Exits 1 unless APP's signature verifies strictly, with --deep, has the hardened runtime and no
# entitlements (ADR 0007), and its binary holds arm64 and x86_64. scripts/check.sh runs it on the
# bundle and on the release dry run's zipped app, and scripts/release.sh runs it before notarizing.
# It checks no signing identity: release.sh checks the Developer ID itself.
set -euo pipefail
app="$1"

fail() {
  echo "verify-signature: $app: $*" >&2
  exit 1
}

codesign --verify --strict --deep "$app" || fail "codesign --verify --strict --deep rejects it."
signature="$(codesign -dv "$app" 2>&1)" || fail "codesign -dv can't read it."
if ! grep -Eq '^CodeDirectory .*flags=0x[0-9a-f]+\([^)]*runtime' <<<"$signature"; then
  fail "the signature lacks the hardened runtime (codesign --options runtime)."
fi
entitlements="$(codesign -d --entitlements - --xml "$app" 2>/dev/null)" ||
  fail "codesign can't read its entitlements."
if [[ -n $entitlements ]]; then
  fail "the signature carries entitlements; scripts/bundle.sh signs with none: $entitlements"
fi
archs=" $(lipo -archs "$app/Contents/MacOS/DrowsyDock") " || fail "lipo can't read the binary."
for arch in arm64 x86_64; do
  if [[ $archs != *" $arch "* ]]; then fail "the binary lacks $arch (lipo -archs:$archs)."; fi
done
