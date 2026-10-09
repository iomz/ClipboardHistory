#!/bin/sh
set -eu
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 baseline.app candidate.app" >&2
  exit 1
fi
codesign --verify --deep --strict "$1"
codesign --verify --deep --strict "$2"
BASELINE=$(codesign -d -r- "$1" 2>/dev/null | grep '^designated => ')
CANDIDATE=$(codesign -d -r- "$2" 2>/dev/null | grep '^designated => ')
if [ "$BASELINE" != "$CANDIDATE" ]; then
  echo "Designated requirements differ. Do not assume Accessibility authorization will persist." >&2
  exit 1
fi
echo "Baseline and candidate designated requirements match exactly. TCC behavior still requires HAT."
