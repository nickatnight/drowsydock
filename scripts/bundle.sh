#!/usr/bin/env bash
# Builds a universal release binary, assembles build/SleepyBattery.app and signs it.
#
# SIGN_IDENTITY picks the codesign identity. The default "-" signs ad hoc, which needs no
# certificate but makes macOS forget the Accessibility grant on every rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."

sign_identity="${SIGN_IDENTITY:--}"
app="build/SleepyBattery.app"
build_flags=(-c release --arch arm64 --arch x86_64 --product SleepyBattery)

swift build "${build_flags[@]}"
bin_dir="$(swift build "${build_flags[@]}" --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/SleepyBattery" "$app/Contents/MacOS/SleepyBattery"
cp Resources/Info.plist "$app/Contents/Info.plist"

codesign --force --sign "$sign_identity" "$app"
echo "Built $app (signed with identity '$sign_identity')"
