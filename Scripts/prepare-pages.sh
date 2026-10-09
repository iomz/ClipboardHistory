#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")
APP="$ROOT/build/releases/$VERSION/Clipboard History.app"
FEED="$ROOT/build/releases/$VERSION/appcast.xml"
OUT="$ROOT/build/pages/$VERSION"
if [ -e "$OUT" ]; then
  echo "Refusing to overwrite $OUT." >&2
  exit 1
fi
"$ROOT/Scripts/test-distribution.sh" "$APP" "$FEED" "$ROOT/build/update-archives"
mkdir -p "$OUT"
cp "$FEED" "$OUT/appcast.xml"
touch "$OUT/.nojekyll"
echo "Pages payload prepared at $OUT. No commit, push, settings change or publication performed."
