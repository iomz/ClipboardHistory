# Development notes

## Product invariant: preserve intent, not legacy accidents

Classify behavior as **PRESERVE / IMPROVE / DROP / ASK**. Legacy behavior is evidence, not a specification. If a material product choice is genuinely ambiguous, ask iomz; do not silently invent an assumption.

Current facts to preserve:

- Local menu-bar utility when manager closed; normal Dock/Cmd-Tab app while History Manager is open.
- Distinct UI roles: transient pointer-relative fast picker and normal persistent History Manager.
- Fast-picker row hover waits 400 ms, then shows a focus-neutral read-only preview using shared Manager preview content; hover never changes keyboard selection.
- Option-Command-V opens picker. Search remains first-class; arrows and Ctrl-N/Ctrl-P navigate without wrapping.
- Enter restores rich/default representations and pastes; Shift-Enter restores plain text and pastes. Holding Shift previews TXT badges only for entries eligible for that same plain-text restore; Escape dismisses.
- One history event groups multiple pasteboard items, each with multiple original typed representations. Do not flatten rich content to text.
- Content-equivalent recapture promotes existing entry, retains identity/favorite, updates recency and latest source metadata.
- Picker omits source text for density; manager shows source metadata and owns management actions. Both use one repository/search implementation.
- No legacy import is planned. Retention is not currently required. Clear on Exit is dropped. Save As is deferred/not currently required.
- Do not add settings merely because legacy had them. Next product area: exclusions/privacy settings, designed before implementation.

## Architecture

- `Sources/ClipboardCore`: domain model, deterministic versioned SHA-256 identity, shared history repository, per-entry persistence.
- `Sources/ClipboardPlatform`: AppKit pasteboard snapshot/restoration, fast picker, History Manager, global shortcut and event paste.
- `Sources/ClipboardHistory`: menu-bar app and lifecycle/activation policy.
- Core model writes one metadata plist plus binary representation files per entry. `PasteboardSnapshotter` is shared by live capture, metadata diagnostics, and synthetic tests. Diagnostics contain type IDs/status/byte counts only—never payload values.
- Content classification is deterministic and type-set based. Plain + RTF + HTML uses the richest text cue; URLs/files/images retain semantic cues. A representation set containing both `public.file-url` and image data reports `MIX` rather than guessing FILE vs IMG.

## Build and tests

`Scripts/build-app.sh` builds the Release arm64 `.app` for macOS 26 and assembles `build/Clipboard History.app`. This Command Line Tools-only setup needs SwiftPM's deprecated native build backend; the script selects it. Run `Scripts/test-core.sh` and `Scripts/test-representations.sh`. Representation tests use unique named pasteboards, temporary stores, synthetic fixtures, and exact byte comparison. They never read `NSPasteboard.general`.

Product version follows Semantic Versioning in `CFBundleShortVersionString`; `CFBundleVersion` is an independent incrementing macOS build number. Current product version is 0.2.0 (build 2).

Ordinary launch opens History Manager. A future background/login launcher may pass `--background` to start capture silently; no login item is configured. When already running, AppKit reopen events show the existing Manager instance.

The app status menu includes **Clipboard Representation Report…**. For manual interoperability tests, use only disposable content:

1. Copy a disposable text file, then a multi-selection of disposable files in Finder.
2. In Notes, create a throwaway note and paste/insert a generated or disposable image; copy the image.
3. In Brave, use **Copy Image** on a public non-private test image.
4. After each source copy, open the Clipboard History status menu and choose **Clipboard Representation Report…**. It reports advertised/retained/dropped type IDs, item grouping, byte sizes, and classification; it never displays/logs payloads.
5. Use Option-Command-V and Enter to restore into a safe target. Run the report again to compare restored types. Confirm actual image/file paste in the target app; a badge alone is not evidence of fidelity.

For an image item advertising both a file URL and image data, report shows `MIX`; do not reinterpret it as FILE or IMG without reviewing source representation evidence with iomz.

## Development signing / Accessibility TCC

Observed on macOS 26.6.2: an earlier ad-hoc rebuild lost effective Accessibility authorization. On iomz's current development setup, a stably Apple Development-signed build then retained the existing grant across a source change and rebuild; synthetic paste succeeded without touching Accessibility settings. This is an empirical result only for the current certificate/team, bundle identifier, and Mac—not a guarantee across identity, signing, bundle, or machine changes. Do not weaken automatic paste to avoid the permission.

Signing inspection of the current development app found:

- Bundle identifier in `Info.plist`: `com.iomz.ClipboardHistory`.
- The build script signs the completed app bundle with the sole installed Apple Development identity when exactly one exists. If none exists, it explicitly falls back to ad-hoc signing. If multiple exist, it refuses ambiguous selection unless `CLIPHISTORY_SIGNING_IDENTITY` is set to the intended local identity SHA-1. Keep that value local/untracked; never add certificate/key material, Team ID, or identity hashes to the repository.
- This local Apple Development signature is for repeatable development/TCC testing only. No distribution, notarization, or App Store workflow is configured.

Expected: an Apple Development signature and stable bundle identifier should produce a stable designated requirement across rebuilds. iomz empirically verified TCC persistence for the current development setup as described above; repeat validation if signing identity, Team, bundle identifier, distribution signing, or Mac changes.

## Deferred / not planned

- No legacy-history importer.
- No Clear History on Exit.
- No retention controls or Save As UI currently required.
- Do not implement Settings yet. Next milestone should design only useful exclusions, pause/resume capture, launch-at-login, and shortcut configuration needs, then ask iomz before adding settings scope.

## Open product question

If real source apps advertise both file-reference and image representations for a copied image, should the manager/picker ultimately show `MIX`, `IMG`, or `FILE`? Current implementation uses neutral `MIX`; gather the metadata report first, then ask iomz if a non-neutral preference is needed.
