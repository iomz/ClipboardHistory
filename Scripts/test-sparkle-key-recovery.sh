#!/bin/sh
set -eu
set +x
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 trusted-baseline.app downloaded-backup.key" >&2
  exit 1
fi
APP=$1
BACKUP=$2
test -f "$BACKUP" && test -s "$BACKUP" && test ! -L "$BACKUP"
test "$(stat -f '%Lp' "$BACKUP")" = 600
test "$(stat -f '%Lp' "$(dirname "$BACKUP")")" = 700
TOOLS="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
SERVICE=https://sparkle-project.org
ACCOUNT="com.iomz.ClipboardHistory.recovery-test.$(uuidgen)"
umask 077
WORK=$(mktemp -d "${TMPDIR:-/tmp}/opencode-sparkle-recovery.XXXXXX")
ARMED=false
cleanup() {
  STATUS=$?
  trap - EXIT HUP INT TERM
  if [ "$ARMED" = true ]; then
    # Import may fail before creating an item. Missing item is already clean;
    # every other lookup result must block PASS rather than hide cleanup failure.
    security delete-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1 || true
    set +e
    security find-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1
    LOOKUP=$?
    set -e
    if [ "$LOOKUP" -ne 44 ]; then
      echo "Cleanup not confirmed; remove only account $ACCOUNT, service $SERVICE manually." >&2
      STATUS=1
    fi
  fi
  rm -rf "$WORK"
  exit "$STATUS"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
"$ROOT/Scripts/verify-sparkle-key.sh" "$APP"
# Official tools select items by BOTH service and account. Check absence before
# importing into a fresh UUID account; never change the production selector.
set +e
security find-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1
LOOKUP=$?
set -e
test "$LOOKUP" -eq 44
ARMED=true
"$TOOLS/generate_keys" --account "$ACCOUNT" -f "$BACKUP" > "$WORK/import-public-output.txt"
RESTORED_PUBLIC_KEY=$("$TOOLS/generate_keys" --account "$ACCOUNT" -p)
EXPECTED_PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")
test "$RESTORED_PUBLIC_KEY" = "$EXPECTED_PUBLIC_KEY"
dd if=/dev/urandom of="$WORK/challenge.bin" bs=32 count=1 2>/dev/null
"$TOOLS/sign_update" --account "$ACCOUNT" -p "$WORK/challenge.bin" > "$WORK/signature.txt"
swift "$ROOT/Scripts/verify-sparkle-signature.swift" "$APP/Contents/Info.plist" "$WORK/challenge.bin" "$WORK/signature.txt"
security delete-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null
ARMED=false
set +e
security find-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1
LOOKUP=$?
set -e
test "$LOOKUP" -eq 44
"$ROOT/Scripts/verify-sparkle-key.sh" "$APP"
echo "Recovery import, public-key match, challenge and temporary-item cleanup passed; production key preserved."
# Downloaded secret remains in its private directory for explicit owner cleanup.
