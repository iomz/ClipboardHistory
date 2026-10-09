#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")
APP=${1:-"$ROOT/build/releases/TheClipboard/$VERSION/The Clipboard.app"}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/TheClipboard-finder-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
/usr/bin/assetutil --info "$APP/Contents/Resources/Assets.car" > "$WORK/catalog.json"
swift "$ROOT/Tests/FinderIconChecks.swift" "$ROOT" "$APP" "$WORK/catalog.json"
# Existing alpha/determinism tests cover unchanged ICNS resources; the catalog
# must also remain sealed and unchanged by runtime alternate-icon switching.
codesign --verify --deep --strict "$APP"
