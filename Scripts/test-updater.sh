#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FRAMEWORKS="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
test -d "$FRAMEWORKS/Sparkle.framework"
mkdir -p "$ROOT/build/tests"
swiftc -F "$FRAMEWORKS" -framework Sparkle -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  "$ROOT/Tests/UpdaterChecks.swift" -o "$ROOT/build/tests/updater-checks"
"$ROOT/build/tests/updater-checks" "$ROOT/Resources/Info.plist"
