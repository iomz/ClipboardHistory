#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")
APP=${1:-"$ROOT/build/releases/$VERSION/Clipboard History.app"}
codesign --verify --deep --strict "$APP"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
for NESTED in "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app" \
  "$SPARKLE/Versions/B/XPCServices/Downloader.xpc" \
  "$SPARKLE/Versions/B/XPCServices/Installer.xpc" "$SPARKLE"; do
  codesign --verify --strict "$NESTED"
done
test "$(lipo -archs "$APP/Contents/MacOS/ClipboardHistory")" = arm64
otool -L "$APP/Contents/MacOS/ClipboardHistory" | grep -q '@rpath/Sparkle.framework/Versions/B/Sparkle'
mkdir -p "$ROOT/build/tests"
swiftc "$ROOT/Tests/DistributionChecks.swift" -o "$ROOT/build/tests/distribution-checks"
"$ROOT/build/tests/distribution-checks" "$ROOT/Resources/Info.plist" "$APP" "${2:-}" "${3:-}"
# This explicit diagnostic exits before capture, history, hotkeys or event loop.
# Argument-domain overrides are non-persistent and do not change installed app
# preferences. Test both choices without starting the run loop/network schedule.
"$APP/Contents/MacOS/ClipboardHistory" --distribution-check -SUEnableAutomaticChecks NO -SUScheduledCheckInterval 86400 -ApplicationIconSelection dustlight
"$APP/Contents/MacOS/ClipboardHistory" --distribution-check -SUEnableAutomaticChecks YES -SUScheduledCheckInterval 86400 -ApplicationIconSelection lagoon
