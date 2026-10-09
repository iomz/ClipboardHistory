#!/bin/sh
set -eu
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 candidate.app" >&2
  exit 1
fi
codesign --verify --deep --strict "$1"
codesign --verify --strict -R='identifier "com.iomz.TheClipboard" and anchor apple generic' "$1"
REQUIREMENT=$(codesign -d -r- "$1" 2>/dev/null | grep '^designated => ')
printf '%s\n' "$REQUIREMENT" | grep -q 'identifier "com.iomz.TheClipboard"'
echo "The Clipboard code signature and designated requirement verified. Accessibility authorization remains a human test."
