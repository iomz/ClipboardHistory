#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")
APP=${1:-"$ROOT/build/releases/$VERSION/Clipboard History.app"}
if [ "$#" -eq 0 ] && [ ! -d "$APP" ]; then
  "$ROOT/Scripts/build-app.sh"
fi
test -d "$APP/Contents/MacOS"
"$ROOT/Scripts/test-distribution.sh" "$APP"
APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
test "$APP_VERSION" = "$VERSION"
OUT="$ROOT/build/releases/$VERSION/ClipboardHistory-$VERSION-arm64.dmg"
if [ -e "$OUT" ]; then
  echo "Refusing to overwrite $OUT." >&2
  exit 1
fi
mkdir -p "$(dirname "$OUT")"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ClipboardHistory-dmg.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
mkdir "$WORK/staging"
ditto "$APP" "$WORK/staging/Clipboard History.app"
ln -s /Applications "$WORK/staging/Applications"
hdiutil create -volname "Clipboard History $VERSION" -srcfolder "$WORK/staging" \
  -format UDZO -fs HFS+ "$WORK/candidate.dmg"
hdiutil verify "$WORK/candidate.dmg"
# Publish locally only after success; -n prevents replacement of an existing file.
cp -n "$WORK/candidate.dmg" "$OUT"
cmp "$WORK/candidate.dmg" "$OUT"
echo "Packaged $OUT"
