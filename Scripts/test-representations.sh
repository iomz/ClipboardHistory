#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
SDK=$(xcrun --sdk macosx --show-sdk-path)
mkdir -p build/tests
swiftc -emit-module -emit-library -module-name ClipboardCore -target arm64-apple-macosx26.0 -sdk "$SDK" \
  Sources/ClipboardCore/ClipboardEntry.swift \
  Sources/ClipboardCore/FileEntryStore.swift \
  -emit-module-path build/tests/ClipboardCore.swiftmodule \
  -o build/tests/libClipboardCore.dylib
swiftc -emit-module -emit-library -enable-testing -module-name ClipboardPlatform -target arm64-apple-macosx26.0 -sdk "$SDK" \
  -I build/tests -L build/tests -lClipboardCore \
  Sources/ClipboardPlatform/PasteboardCapture.swift \
  Sources/ClipboardPlatform/ClipboardEntryPreview.swift \
  Sources/ClipboardPlatform/GlobalHotkey.swift \
  Sources/ClipboardPlatform/PickerWindowController.swift \
  Sources/ClipboardPlatform/HistoryManagerWindowController.swift \
  -emit-module-path build/tests/ClipboardPlatform.swiftmodule \
  -o build/tests/libClipboardPlatform.dylib
swiftc -parse-as-library -target arm64-apple-macosx26.0 -sdk "$SDK" -I build/tests -L build/tests \
  -lClipboardPlatform -lClipboardCore -Xlinker -rpath -Xlinker "$ROOT/build/tests" \
  Tests/RepresentationChecks.swift \
  -o build/tests/representation-checks
build/tests/representation-checks
