#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${1:-"$ROOT/build/icons/Dustlight.icns"}
DESIGN=${2:-Dustlight}
case "$DESIGN" in Dustlight|Lagoon) ;; *) echo "Unknown icon design: $DESIGN" >&2; exit 1 ;; esac
if [ -e "$OUT" ]; then
  echo "Refusing to overwrite $OUT." >&2
  exit 1
fi
mkdir -p "$(dirname -- "$OUT")"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/TheClipboard-icon.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
swift "$ROOT/Scripts/generate-icon.swift" "$ROOT/Resources/Artwork/$DESIGN.png" "$WORK/$DESIGN.iconset"
iconutil --convert icns --output "$WORK/$DESIGN.icns" "$WORK/$DESIGN.iconset"
cp -n "$WORK/$DESIGN.icns" "$OUT"
cmp "$WORK/$DESIGN.icns" "$OUT"
echo "Generated $OUT from approved sRGB/alpha master."
