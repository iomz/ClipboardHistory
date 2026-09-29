#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
swift build --build-system native -c release --arch arm64
APP="$ROOT/build/Clipboard History.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/arm64-apple-macosx/release/ClipboardHistory "$APP/Contents/MacOS/ClipboardHistory"
cp Resources/Info.plist "$APP/Contents/Info.plist"
echo "Built $APP"
