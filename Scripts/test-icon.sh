#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")
APP=${1:-"$ROOT/build/releases/TheClipboard/$VERSION/The Clipboard.app"}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/TheClipboard-icon-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
for DESIGN in Dustlight Lagoon; do
  RESOURCE=Dustlight
  if [ "$DESIGN" = Lagoon ]; then RESOURCE=Lagoon; fi
  "$ROOT/Scripts/generate-icon.sh" "$WORK/$DESIGN-first.icns" "$DESIGN"
  "$ROOT/Scripts/generate-icon.sh" "$WORK/$DESIGN-second.icns" "$DESIGN"
  cmp "$WORK/$DESIGN-first.icns" "$WORK/$DESIGN-second.icns"
  cmp "$WORK/$DESIGN-first.icns" "$APP/Contents/Resources/$RESOURCE.icns"
  iconutil --convert iconset --output "$WORK/$DESIGN.iconset" "$WORK/$DESIGN-first.icns"
  swift "$ROOT/Tests/IconChecks.swift" "$ROOT" "$WORK/$DESIGN.iconset" "$APP" "$DESIGN"
done
echo "Repeated icon generation matches byte-for-byte, including signed bundle resource."
