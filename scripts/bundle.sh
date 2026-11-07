#!/usr/bin/env bash
# Builds a universal release binary, assembles build/DrowsyDock.app and signs it.
#
# SIGN_IDENTITY picks the codesign identity. The default "-" signs ad hoc, which needs no
# certificate but makes macOS forget the Accessibility grant on every rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."

sign_identity="${SIGN_IDENTITY:--}"
app="build/DrowsyDock.app"
build_flags=(-c release --arch arm64 --arch x86_64 --product DrowsyDock)

swift build "${build_flags[@]}"
bin_dir="$(swift build "${build_flags[@]}" --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/DrowsyDock" "$app/Contents/MacOS/DrowsyDock"
cp Resources/Info.plist "$app/Contents/Info.plist"

# The hardened runtime makes dyld ignore DYLD_* variables, so no other process can inject code
# into an app that holds the Accessibility grant.
codesign --force --options runtime --sign "$sign_identity" "$app"
echo "Built $app (signed with identity '$sign_identity')"
