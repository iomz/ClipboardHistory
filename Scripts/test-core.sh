#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
SDK=$(xcrun --sdk macosx --show-sdk-path)
mkdir -p build/tests
swiftc -target arm64-apple-macosx26.0 -sdk "$SDK" \
  Sources/ClipboardCore/ClipboardEntry.swift \
  Sources/ClipboardCore/FileEntryStore.swift \
  Tests/CoreChecks.swift \
  -o build/tests/core-checks
build/tests/core-checks
