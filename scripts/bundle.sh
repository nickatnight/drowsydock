#!/usr/bin/env bash
# Builds a universal release binary, assembles build/DrowsyDock.app and signs it.
#
# SIGN_IDENTITY picks the codesign identity. The default "-" signs ad hoc, which needs no
# certificate but makes macOS forget the Accessibility grant on every rebuild.
#
# SIGN_TIMESTAMP=1 adds Apple's secure timestamp (--timestamp), which notarization requires and
# which needs the network; scripts/release.sh sets it. Unset or 0 signs with --timestamp=none, so a
# dev build never needs the network.
set -euo pipefail
cd "$(dirname "$0")/.."

sign_identity="${SIGN_IDENTITY:--}"
case "${SIGN_TIMESTAMP:-0}" in
  1) timestamp_flag=--timestamp ;;
  0) timestamp_flag=--timestamp=none ;;
  *)
    echo "bundle.sh: SIGN_TIMESTAMP is '$SIGN_TIMESTAMP'; set it to 1 or 0, or leave it unset" >&2
    exit 2
    ;;
esac
app="build/DrowsyDock.app"
build_flags=(-c release --arch arm64 --arch x86_64 --product DrowsyDock)

swift build "${build_flags[@]}"
bin_dir="$(swift build "${build_flags[@]}" --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/DrowsyDock" "$app/Contents/MacOS/DrowsyDock"
cp Resources/Info.plist "$app/Contents/Info.plist"

# The app icon: Resources/AppIcon.svg, rendered at every size an .icns holds.
icon_dir="$(mktemp -d)"
trap 'rm -rf "$icon_dir"' EXIT
swift scripts/icon/render-icon.swift Resources/AppIcon.svg "$icon_dir/AppIcon.iconset"
iconutil --convert icns --output "$app/Contents/Resources/AppIcon.icns" "$icon_dir/AppIcon.iconset"

# The hardened runtime makes dyld ignore DYLD_* variables, so no other process can inject code
# into an app that holds the Accessibility grant.
codesign --force --options runtime "$timestamp_flag" --sign "$sign_identity" "$app"
echo "Built $app (signed with identity '$sign_identity')"
