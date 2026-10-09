#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")
APP="$ROOT/build/releases/$VERSION/Clipboard History.app"
DMG="$ROOT/build/releases/$VERSION/ClipboardHistory-$VERSION-arm64.dmg"
PREVIOUS=${1:-}
TOOLS="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
OUT="$ROOT/build/releases/$VERSION/appcast.xml"
ARCHIVES="$ROOT/build/update-archives"
test -f "$DMG"
test -d "$APP"
if [ -e "$OUT" ]; then
  echo "Refusing to overwrite $OUT." >&2
  exit 1
fi
PUBLIC_KEY=$("$TOOLS/generate_keys" --account com.iomz.ClipboardHistory -p)
EMBEDDED_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")
if [ "$PUBLIC_KEY" != "$EMBEDDED_KEY" ]; then
  echo "Keychain public key differs from bundled SUPublicEDKey; refusing to sign." >&2
  exit 1
fi
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ClipboardHistory-appcast.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
ditto "$DMG" "$WORK/$(basename "$DMG")"
# Generate only the current archive so Sparkle's URL prefix cannot rewrite old
# GitHub Release URLs. Then merge old generated items without editing signatures.
"$TOOLS/generate_appcast" --account com.iomz.ClipboardHistory \
  --download-url-prefix "https://github.com/iomz/ClipboardHistory/releases/download/v$VERSION/" \
  --maximum-deltas 0 --maximum-versions 0 "$WORK"
if [ -n "$PREVIOUS" ]; then
  test -f "$PREVIOUS"
  swift "$ROOT/Scripts/merge-appcast.swift" "$WORK/appcast.xml" "$PREVIOUS"
fi
mkdir -p "$ARCHIVES"
if [ -f "$ARCHIVES/$(basename "$DMG")" ]; then
  cmp "$DMG" "$ARCHIVES/$(basename "$DMG")"
else
  cp -n "$DMG" "$ARCHIVES/$(basename "$DMG")"
fi
"$ROOT/Scripts/test-distribution.sh" "$APP" "$WORK/appcast.xml" "$ARCHIVES"
cp -n "$WORK/appcast.xml" "$OUT"
cmp "$WORK/appcast.xml" "$OUT"
echo "Prepared $OUT (not published). Retain build/update-archives for later feed validation."
