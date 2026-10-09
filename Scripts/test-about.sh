#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$ROOT/build/tests"
swiftc "$ROOT/Sources/TheClipboard/AboutInformation.swift" "$ROOT/Tests/AboutChecks.swift" \
  -o "$ROOT/build/tests/about-checks"
"$ROOT/build/tests/about-checks"
