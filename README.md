# Clipboard History

Native macOS clipboard history utility. Requires macOS 26 or later; builds arm64 without Rosetta.

```sh
Scripts/build-app.sh
Scripts/test-core.sh
Scripts/test-representations.sh
open "build/Clipboard History.app"
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for product invariants, architecture, signing/TCC caveats, and safe non-text fidelity diagnostics.
