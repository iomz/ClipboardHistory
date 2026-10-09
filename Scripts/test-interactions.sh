#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
"$ROOT/Scripts/test-representations.sh"
SDK=$(xcrun --sdk macosx --show-sdk-path)
swiftc -parse-as-library -target arm64-apple-macosx26.0 -sdk "$SDK" \
  -I "$ROOT/build/tests" -L "$ROOT/build/tests" -lClipboardPlatform -lClipboardCore \
  -Xlinker -rpath -Xlinker "$ROOT/build/tests" \
  "$ROOT/Tests/InteractionChecks.swift" -o "$ROOT/build/tests/interaction-checks"
"$ROOT/build/tests/interaction-checks"
