#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 trusted-baseline.app" >&2
  exit 1
fi
INFO="$1/Contents/Info.plist"
TOOLS="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
codesign --verify --deep --strict "$1"
PUBLIC_KEY=$("$TOOLS/generate_keys" --account com.iomz.ClipboardHistory -p)
EMBEDDED_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO")
if [ "$PUBLIC_KEY" != "$EMBEDDED_KEY" ]; then
  echo "Keychain public key does not match trusted baseline. Stop; do not replace or rotate keys." >&2
  exit 1
fi
umask 077
WORK=$(mktemp -d "${TMPDIR:-/tmp}/opencode-sparkle-proof.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
# Only random non-secret challenge and public signature are written to disk.
dd if=/dev/urandom of="$WORK/challenge.bin" bs=32 count=1 2>/dev/null
"$TOOLS/sign_update" --account com.iomz.ClipboardHistory -p "$WORK/challenge.bin" > "$WORK/signature.txt"
swift "$ROOT/Scripts/verify-sparkle-signature.swift" "$INFO" "$WORK/challenge.bin" "$WORK/signature.txt"
