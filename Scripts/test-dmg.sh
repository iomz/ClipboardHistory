#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")
DMG=${1:-"$ROOT/build/releases/$VERSION/ClipboardHistory-$VERSION-arm64.dmg"}
hdiutil verify "$DMG"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ClipboardHistory-inspect.XXXXXX")
MOUNTED=false
cleanup() {
  if [ "$MOUNTED" = true ]; then
    if ! hdiutil detach "$WORK/mount"; then
      echo "Detach failed; retaining $WORK. Eject manually before removing it." >&2
      return
    fi
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT HUP INT TERM
mkdir "$WORK/mount"
hdiutil attach -readonly -nobrowse -mountpoint "$WORK/mount" "$DMG"
MOUNTED=true
diskutil info -plist "$WORK/mount" > "$WORK/volume.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :WritableVolume' "$WORK/volume.plist")" = false
test -d "$WORK/mount/Clipboard History.app"
test -L "$WORK/mount/Applications"
test "$(readlink "$WORK/mount/Applications")" = /Applications
# hdiutil may add standard hidden filesystem metadata, but nothing else.
find "$WORK/mount" -mindepth 1 -maxdepth 1 ! -name 'Clipboard History.app' \
  ! -name Applications ! -name '.HFS+ Private Directory Data*' \
  ! -name '.fseventsd' ! -name '.Trashes' ! -name '.DS_Store' \
  ! -name '.VolumeIcon.icns' > "$WORK/unexpected.txt"
test ! -s "$WORK/unexpected.txt"
"$ROOT/Scripts/test-distribution.sh" "$WORK/mount/Clipboard History.app"
"$ROOT/Scripts/test-icon.sh" "$WORK/mount/Clipboard History.app"
echo "DMG is read-only; app and Applications symlink verified; no extra payloads."
