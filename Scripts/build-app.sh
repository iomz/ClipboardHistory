#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
swift build --build-system native -c release --arch arm64
APP="$ROOT/build/Clipboard History.app"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Resources/Info.plist)
mkdir -p "$APP/Contents/MacOS"
cp .build/arm64-apple-macosx/release/ClipboardHistory "$APP/Contents/MacOS/ClipboardHistory"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Prefer a stable local Apple Development identity when one is unambiguous.
# An optional local selector accepts only its SHA-1 identity hash; never commit it.
IDENTITIES=$(security find-identity -v -p codesigning 2>/dev/null || true)
APPLE_DEV_HASHES=$(printf '%s\n' "$IDENTITIES" | awk '/^[[:space:]]*[0-9]+\)/ && /"Apple Development:/ {print tolower($2)}')
IDENTITY_COUNT=$(printf '%s\n' "$APPLE_DEV_HASHES" | awk 'NF {count++} END {print count+0}')
SELECTED_IDENTITY=${CLIPHISTORY_SIGNING_IDENTITY:-}

if [ -n "$SELECTED_IDENTITY" ]; then
  SELECTED_IDENTITY=$(printf '%s' "$SELECTED_IDENTITY" | tr '[:upper:]' '[:lower:]')
  MATCH_COUNT=$(printf '%s\n' "$APPLE_DEV_HASHES" | awk -v selected="$SELECTED_IDENTITY" '$0 == selected {count++} END {print count+0}')
  if [ "$MATCH_COUNT" -ne 1 ]; then
    echo "CLIPHISTORY_SIGNING_IDENTITY must match exactly one installed Apple Development identity." >&2
    exit 1
  fi
  codesign --force --sign "$SELECTED_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
  echo "Signed app with locally selected Apple Development identity."
elif [ "$IDENTITY_COUNT" -eq 1 ]; then
  codesign --force --sign "$APPLE_DEV_HASHES" --identifier "$BUNDLE_ID" "$APP"
  echo "Signed app with the sole installed Apple Development identity."
elif [ "$IDENTITY_COUNT" -eq 0 ]; then
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
  echo "No Apple Development identity found; explicitly using ad-hoc signing."
else
  echo "Multiple Apple Development identities found; refusing ambiguous selection." >&2
  echo "Set CLIPHISTORY_SIGNING_IDENTITY to the intended local identity SHA-1." >&2
  exit 1
fi

codesign --verify --deep --strict "$APP"
echo "Built $APP"
