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

`Scripts/build-app.sh` builds the Release arm64 `.app` for macOS 26 and assembles `build/releases/<version>/Clipboard History.app`. It refuses an existing output, preserving the running v0.2.0 app at `build/Clipboard History.app`. Move an obsolete candidate aside explicitly before rebuilding; never move/delete a running or accepted installation. This Command Line Tools-only setup needs SwiftPM's deprecated native build backend; the script selects it. The manifest requires Swift tools 6.0 and uses Swift 5 language mode. v0.3.0 was validated with Apple Swift 6.4 on macOS 27.0.1. Run `Scripts/test-core.sh` and `Scripts/test-representations.sh`. Representation tests use unique named pasteboards, temporary stores, synthetic fixtures, and exact byte comparison. They never read `NSPasteboard.general`.

Product version follows Semantic Versioning in `CFBundleShortVersionString`; `CFBundleVersion` is an independent incrementing macOS build number. Current candidate is 0.3.1 (build 4); publicly released baseline remains 0.3.0/build 3 until publication approval. `Resources/Info.plist` is the only product version source. Sparkle compares build numbers, not SemVer labels. Increment the build for every published update. Never replace a published DMG with different bytes under the same version/URL.

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
- This local Apple Development signature is for repeatable development/TCC testing only. v0.3.0 adds an experimental DMG/update workflow, not trusted public distribution. Developer ID, notarization, and App Store distribution remain unconfigured.

Expected: an Apple Development signature and stable bundle identifier should produce a stable designated requirement across rebuilds. iomz empirically verified TCC persistence for the current development setup as described above; repeat validation if signing identity, Team, bundle identifier, distribution signing, or Mac changes.

## Sparkle 2 integration

Official [Sparkle](https://sparkle-project.org/documentation/) **2.10.0** is pinned exactly in `Package.swift`; commit `Package.resolved` with source changes after HAT approval. SwiftPM verifies the binary artifact checksum from Sparkle's pinned package manifest. No Xcode project was added. Framework and signing tools come from `.build/artifacts/sparkle/Sparkle/` after `swift package resolve`.

The executable links Sparkle with `@executable_path/../Frameworks` runpath. `build-app.sh` embeds the official framework using `ditto`, preserving symlinks and executable permissions, and includes the upstream license/third-party notices as `Contents/Resources/Sparkle-LICENSE.txt`. It signs Autoupdate, Updater.app, both XPC services, the framework, then the outer app, inside-out. Nested identifiers, entitlements, and runtime flags are preserved. The outer app keeps its existing signing policy (no newly added hardened runtime or sandbox). Signing identity selection and ad-hoc fallback are unchanged. Do not use `codesign --deep` for signing; it is used only for verification. Preserve Sparkle's dSYMs from the resolved distribution for debugging.

`SPUStandardUpdaterController` owns standard update UI, download, installation and relaunch. **Check for Updates…** targets its supported action directly in both application and status menus, without opening the History Manager. v0.3.0 was manual-only; v0.3.1 supports native opt-in automatic checks and an **Automatically Check for Updates** checkbox in both menus. Background downloads and automatic installation remain disallowed by `SUAutomaticallyUpdate = false` and `SUAllowsAutomaticUpdates = false`; downloading/installing an available update remains a user-initiated Sparkle flow. HTTPS feed is fixed to:

```
https://iomz.github.io/ClipboardHistory/appcast.xml
```

`SUPublicEDKey` embeds only the public Ed25519 key. `SUVerifyUpdateBeforeExtraction` requires archive validation before extraction. The appcast itself is ordinary HTTPS XML, not a cryptographically signed feed; DMG enclosures carry EdDSA signatures. No verification bypass, alternate localhost feed or custom installer is used.

### v0.3.1 automatic-check consent and scheduling

The actual Sparkle 2.10.0 `SPUUpdater.h`, `SPUUpdater.m` and `SPUUpdaterSettings.m` were inspected before this change. `SUEnableAutomaticChecks` is deliberately **absent** from candidate Info.plist: defining it there suppresses Sparkle's native permission prompt. Updater startup no longer writes `automaticallyChecksForUpdates` or `automaticallyDownloadsUpdates`. No preference migration or separate consent flag is introduced.

- **Fresh defaults:** Sparkle starts with checks off, records that it has launched, then normally asks for permission on the second launch. Existing `SUHasLaunchedBefore` can make the first v0.3.1 launch eligible for that prompt. No `SUPromptUserOnFirstLaunch` override is used. Consent response is persisted by Sparkle. There is no background-download option because the bundle disallows automatic updates.
- **Existing choice:** a persisted `SUEnableAutomaticChecks` YES/NO suppresses the prompt and wins over bundle defaults. v0.3.0 itself wrote NO at launch, so its upgrades remain opted out. That value cannot be distinguished reliably from an explicit user refusal; v0.3.1 must not silently turn it on. Owner can explicitly opt in with **Automatically Check for Updates**, without a Settings window. Turning the checkbox off persists NO and cancels/resets the native schedule; relaunch must not re-enable it. Checkbox is disabled during an in-progress Sparkle session.
- **Interval:** `SUScheduledCheckInterval = 86400` in Info.plist supplies the 24-hour default through Sparkle's supported setting. Existing explicit interval preferences remain respected; no setter runs on launch. Sparkle manages its own scheduling, minimum interval/leeway, recorded last-check timestamp and overdue-on-start handling. Delay may be less than 24 hours because elapsed time since last check is subtracted; an overdue enabled updater may check soon after startup. It does not mean a custom periodic timer or check on every activation.
- **Lifecycle:** picker show, Manager show, app activation and reopen never call an update-check API. Only explicit menu checks or Sparkle's native scheduler do. Delegate callbacks log `Updates` messages such as `Sparkle scheduled check in … seconds; interval 86400.0 seconds` or `Sparkle automatic checks disabled; no scheduled check`. They observe scheduling only; they do not start checks or activate Manager.
- **Tests:** actual Sparkle API tests use unique fixture bundle IDs and never start fixture updaters. They cover unset/NO/YES preferences, 86400 default, automatic-download prohibition even with a stale YES preference, and persisted explicit opt-in/out. Distribution smoke uses non-persistent `-SUEnableAutomaticChecks NO/YES -SUScheduledCheckInterval 86400` argument overrides, with no run loop, network requests or production preference writes. Native consent UI and real 24-hour firing still require human observation; no defaults deletion is part of testing.

### v0.3.1 picker handoff and favorites

Shift-Command-Space is a **local picker keyDown action**, accepted only while the picker is key and with exactly Command+Shift among Command/Shift/Control/Option modifiers. Caps Lock does not prevent recognition. It removes the picker monitor, dismisses picker/hover preview without restoring or activating the paste destination, then calls the existing Manager path with explicit search-field keyboard focus. It never restores the pasteboard or posts paste events. No new global shortcut is registered; Option-Command-V, Ctrl-N/P, arrows, Return/Shift-Return, Escape and search are otherwise unchanged.

macOS input-source shortcuts or user-customized system shortcuts can consume Shift-Command-Space before AppKit delivers it. If that happens, inspect Keyboard → Keyboard Shortcuts → Input Sources (and other shortcut tools) and resolve the conflicting binding manually. Do not register a global workaround or change system shortcuts automatically.

History Manager favorite rows render native `star.fill` through `NSImageView`; non-favorite row indicators are hidden. Selected rows use contrasting selected-control text tint; normal rows use secondary label tint. The existing Favorite/Unfavorite button also uses `star.fill`, keeps its action/text and exposes Add/Remove from favorites accessibility labeling. Row image has a Favorite accessibility label. Model toggling, persistence and duplicate favorite retention remain unchanged. Picker's existing marker and menu-bar clipboard icon are unchanged.

### Four separate mechanisms

1. **Apple application code signing:** signs app code/resources and nested helpers. Current Apple Development identity provides stable local identity for development/TCC; it is not Developer ID distribution signing or notarization.
2. **Sparkle EdDSA signing:** signs the exact DMG bytes. Sparkle checks the signature against the public key in the installed app. It does not make macOS trust the first installation.
3. **GitHub Releases:** hosts immutable, versioned DMGs; public download URLs are referenced in enclosure metadata.
4. **GitHub Pages:** hosts the small appcast announcing versions, minimum OS/arm64 requirements, download URL, byte length and signature. Publishing metadata does not upload the DMG.

### Sparkle key handling

Dedicated key was generated using Sparkle's official tool, with account `com.iomz.ClipboardHistory`:

```sh
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account com.iomz.ClipboardHistory
# Public-key-only lookup (safe to compare with SUPublicEDKey):
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account com.iomz.ClipboardHistory -p
```

Production private key stays in the user's **login Keychain**, item named **Private key for signing Sparkle updates**, account `com.iomz.ClipboardHistory`. Release builds use that item directly, never an environment secret or bundled key. Owner-authorized backup uses a short-lived restricted plaintext file outside the repository and Bitwarden's encrypted vault; no extra encrypted disk image is required. Permit official tooling's Keychain access if macOS requests it; do not disable Keychain protection or print the item's password. On a new machine/account, do not generate a replacement key for an already published baseline inadvertently.

Losing the keychain/key can break future updates. Same Apple Account is **not** a recovery guarantee. Sparkle 2.10.0 stores a generic-password item with service `https://sparkle-project.org` and account `com.iomz.ClipboardHistory`; its implementation does not request `kSecAttrSynchronizable`. Do not assume iCloud Keychain syncs it. Source: [pinned generate_keys implementation](https://github.com/sparkle-project/Sparkle/blob/2.10.0/generate_keys/main.swift). The existing key was exported for owner-authorized Bitwarden backup and imported into an isolated test account for recovery verification; no replacement keypair or rotation occurred. Do not assume Apple Development signing offers Sparkle's documented Developer ID key-rotation recovery path.

### Bitwarden backup (existing Mac)

**The official export is plaintext base64, not encrypted.** For this newly generated key it encodes the 32-byte private seed; anyone obtaining it can sign releases. `-x` exports only an existing key and refuses an existing destination. It does not generate a replacement. Never display the file, use `cat`, copy its contents to chat/clipboard, or put the secret in arguments, environment variables, shell logs or source control.

1. First verify the existing signing key against the trusted installed baseline:

   ```sh
   Scripts/verify-sparkle-key.sh "/Applications/Clipboard History.app"
   ```

   This uses `generate_keys -p` (lookup only), compares its public key with the bundle, then signs a random non-secret challenge through official `sign_update` and independently verifies it with CryptoKit. Only challenge bytes and public signature touch temporary disk. No private key export, import, generation or keychain-item modification. Stop on failure.
2. In an unrecorded local Terminal session, create a fresh private temporary directory outside the repository, with shell tracing disabled. The example uses macOS's per-user temporary directory; in the agent session use its approved `opencode` temporary parent. Export only the existing key:

   ```sh
   set +x
   umask 077
   BACKUP_DIR=$(mktemp -d "${TMPDIR:?}ClipboardHistory-key-backup.XXXXXX")
   chmod 700 "$BACKUP_DIR"
   .build/artifacts/sparkle/Sparkle/bin/generate_keys \
     --account com.iomz.ClipboardHistory \
     -x "$BACKUP_DIR/ClipboardHistory-Sparkle-private.key"
   chmod 600 "$BACKUP_DIR/ClipboardHistory-Sparkle-private.key"
   test -s "$BACKUP_DIR/ClipboardHistory-Sparkle-private.key"
   ```

   Allow official tool's Keychain access if requested. Do not run its default generation mode. The file and atomic-write staging are plaintext temporarily; permissions restrict access but are not encryption and do not protect against malware running as your user. Never read the file with agent tools or print its contents.
3. Owner creates a private Bitwarden item named `Clipboard History — Sparkle signing key`, attaches the exported file, saves it, and confirms it is available in the vault. [Bitwarden attachments](https://bitwarden.com/help/attachments/) are encrypted/decrypted locally before transport/storage; uploading requires Premium or a supported paid organization plan. No agent upload, public sharing or Send link. Record the non-secret account/service, Sparkle version and trusted baseline public key in the item's notes. Use strong vault authentication, 2FA and independently available recovery access.
4. If attachments are unavailable, a secure note can hold the base64 seed, but only the owner may handle that plaintext locally. Quit Clipboard History and other clipboard-history/sync tools before copying any secret; never paste it into agent chat, commands, logs or source files. Prefer file attachment to avoid creating clipboard history containing the key. Do not let the agent read the note/file. After saving, restore it to a file for the test below, outside the repository.
5. After owner confirms vault backup, download that attachment **back from Bitwarden** into a second fresh `0700` temporary directory; make the recovered file `0600`. Configure Save As to this directory, not default Downloads; if needed enable browser's ask-where-to-save setting. Do not use the original export as recovery-test input: that would not test the backup. Both directories must stay outside the repository and synced folders.
6. Run the isolated recovery test below, then explicitly remove only these two files and their now-empty directories:

   ```sh
   # Set RECOVERY_DIR to the private directory containing the Bitwarden download.
   Scripts/test-sparkle-key-recovery.sh "/Applications/Clipboard History.app" \
     "$RECOVERY_DIR/ClipboardHistory-Sparkle-private.key"
   # After successful recovery and owner confirms vault copy remains available:
   rm -- "$BACKUP_DIR/ClipboardHistory-Sparkle-private.key"
   rm -- "$RECOVERY_DIR/ClipboardHistory-Sparkle-private.key"
   rmdir -- "$BACKUP_DIR" "$RECOVERY_DIR"
   ```

   Substitute the trusted candidate path if appropriate. Cleanup removes ordinary filesystem references; **no secure deletion from SSD storage, snapshots or backups is claimed**. Keep temporary plaintext lifetime short. If test fails, do not publish; remove plaintext when no longer needed and retain production Keychain/vault item.
7. Maintain an independent encrypted backup and vault recovery/2FA recovery access. Do not assume a normal encrypted JSON vault export includes attachments. Bitwarden's [password-protected versus account-restricted exports](https://bitwarden.com/help/encrypted-export/) have different recovery constraints; verify attachment coverage and restore procedure before relying on a vault-wide export.

### Isolated recovery verification

Official Sparkle 2.10.0 `generate_keys --account <name> -f <file>` imports under the selected account; `sign_update --account <name>` selects that same account. Pinned source confirms both use generic-password service `https://sparkle-project.org` **and the supplied account**. `SecItemAdd` does not overwrite an existing item. This is supported account isolation within the existing Keychain, not a claim that Sparkle accepts an explicit temporary-Keychain path.

`Scripts/test-sparkle-key-recovery.sh` requires a nonempty recovered file with `0600` permissions in a `0700` directory. It checks production signing first, creates a UUID account name, proves it absent, imports with official tooling, compares restored public key with the trusted app, signs a random non-secret challenge and independently verifies it with CryptoKit. It deletes only that UUID account/service item, checks removal, and verifies production signing again. Failure triggers targeted cleanup; cleanup failure is reported rather than treated as PASS. The script never prints/exports private material or removes the original item. Allow official tooling's Keychain prompts locally if requested. If access is denied, stop and report the failure; do not bypass Keychain protection.

### Restore on replacement Mac

1. Obtain trusted source and an accepted signed baseline app/DMG with its known public key. Install Swift tools compatible with the manifest and run `swift package resolve` to obtain **pinned Sparkle 2.10.0** tooling. This resolves dependencies, not signing keys. Never run `generate_keys` without an explicit `-p`, `-x` or `-f` during recovery.
2. Check for an existing key with `generate_keys --account com.iomz.ClipboardHistory -p`. Missing key is expected on a fresh Mac. If present, run `verify-sparkle-key.sh` against the trusted baseline: if it matches, no import is needed; if different, **stop**. Do not delete, overwrite or rotate an existing item to force recovery.
3. Download the existing backup from Bitwarden into a fresh restricted temporary directory as above. After confirming no conflicting production account exists, import directly from that file:

   ```sh
   set +x
   umask 077
   .build/artifacts/sparkle/Sparkle/bin/generate_keys \
     --account com.iomz.ClipboardHistory \
     -f "$RECOVERY_DIR/ClipboardHistory-Sparkle-private.key"
   Scripts/verify-sparkle-key.sh "/Applications/Clipboard History.app"
   ```

   Substitute the actual **trusted baseline** app path if not installed. `-f` imports the same seed; it does not generate a new key or overwrite a conflicting item. Tool output contains public-key usage instructions only. Do not edit `SUPublicEDKey` to match a failed restore. Verification must pass both public-key equality and signing challenge proof.
4. Remove the temporary recovered file and empty directory explicitly after verification; retain Bitwarden backup. Future `generate_appcast --account com.iomz.ClipboardHistory` uses the restored Keychain item. Apple Development certificate/private-key migration is a separate task; restoring the Sparkle key alone does not restore application signing or TCC identity.

**Phase A PASS (2026-10-09):** owner confirmed the backup was saved in Bitwarden and downloaded. The downloaded file was imported with official Sparkle tooling into a fresh UUID account, its public key matched the v0.3.0 candidate's embedded key, and a random challenge signature verified independently with CryptoKit. The temporary item was deleted and absence confirmed; production signing was verified before and after the test. Both temporary plaintext files and their private directories were removed, with no claim of secure SSD erasure. Bitwarden backup was not modified. No production key replacement, rotation or removal occurred. This tests recovery of the actual vault download, not merely the original export. A full replacement-Mac/certificate migration is separate; retain vault recovery access and an independent protected backup.

**Publication gates satisfied (2026-10-09):** owner explicitly accepted the latest v0.3.0 candidate's launch/clipboard workflows, About 0.3.0/build 3, Sparkle menu UI without unexpected Manager activation, and Accessibility-backed automatic paste without reset/regrant, then authorized release and Pages publication. Phase A PASS alone is not HAT PASS; both were required. Never remove the original key during recovery testing.

## Local DMG and appcast preparation

Run from repository root:

```sh
Scripts/test-core.sh
Scripts/test-representations.sh
Scripts/test-about.sh
Scripts/test-interactions.sh # includes representation checks
Scripts/test-updater.sh
Scripts/build-app.sh
Scripts/compare-signatures.sh "/Applications/Clipboard History.app" "build/releases/0.3.1/Clipboard History.app"
Scripts/test-distribution.sh
Scripts/package-dmg.sh
Scripts/test-dmg.sh
Scripts/generate-appcast.sh build/releases/0.3.0/appcast.xml
Scripts/prepare-pages.sh
swift Tests/AppcastMergeChecks.swift Scripts/merge-appcast.swift build/releases/0.3.1/appcast.xml
git diff --check
```

For v0.3.1 the signature comparison baseline is the accepted v0.3.0 app in `/Applications` (verify metadata before assuming its version). v0.3.0 originally compared against the retained v0.2.0 app at `build/Clipboard History.app`. Compare before changing installations. Designated requirement equality supports identity continuity but does not prove TCC authorization; actual paste after the OTA update is the definitive human test. Never overwrite/relaunch the installed baseline during candidate preparation.

`package-dmg.sh` builds the default candidate if absent, or consumes one optional app path. It verifies signature, arm64 binary, framework, metadata and menu startup, stages only the app plus an `/Applications` symlink, and uses native `hdiutil` to produce compressed read-only UDZO. Filename is deterministic; filesystem timestamps/signatures/DMG bytes are not promised bit-for-bit reproducible. No artwork, third-party packaging tool, Developer ID or notarization. Output:

```
build/releases/0.3.1/ClipboardHistory-0.3.1-arm64.dmg
build/releases/0.3.1/appcast.xml
build/pages/0.3.1/appcast.xml
build/pages/0.3.1/.nojekyll
```

All build/package/feed/Pages preparation commands refuse existing final outputs rather than silently overwrite. Temporary staging directories are removed after use. `test-dmg.sh` mounts read-only, verifies payload and signatures, then ejects. Distribution checks use an outer-bundle allowlist: no clipboard store, private-key files or Sparkle signing tools are copied into the app/DMG. SwiftPM caches and all prepared artifacts remain untracked under `.build/` and `build/`.

`generate-appcast.sh` first compares the Keychain public key with the bundled one, then runs official `generate_appcast` on the actual DMG with the versioned GitHub Release download prefix. Full updates only; deltas/pruning are disabled. `Tests/DistributionChecks.swift` parses XML, checks URLs, versions, arm64/minimum OS and archive sizes, then independently verifies every enclosure signature with CryptoKit using the **bundled public key**. The private key is not needed for this verification.

For a subsequent release, retain earlier DMGs in `build/update-archives/` and pass the previous published feed explicitly:

```sh
# After updating Info.plist to 0.3.1/build 4 and building/packaging it:
Scripts/generate-appcast.sh build/releases/0.3.0/appcast.xml
Scripts/prepare-pages.sh
```

`merge-appcast.swift` appends older generated items without changing their signatures or release-specific URLs, rejects non-older build numbers, and final validation rejects duplicate builds. This avoids Sparkle's global download-prefix setting rewriting old items to the newest GitHub tag. Keep/download the exact old DMGs needed for validation; missing archives fail closed. No signature values are hand-written. Feed metadata is not signed, so this XML merge does not invalidate archive signatures.

`--distribution-check` is a launch smoke diagnostic: it initializes Sparkle and verifies both real menu targets, automatic preference preservation and download prohibition, then exits **before** clipboard/history initialization, hotkey registration or app event loop. It prints effective automatic-check preference and interval. It performs no update request and no TCC reset. This is not proof that an update was downloaded, installed or relaunched, nor a substitute for normal-launch HAT.

## Publication gate and manual hosting

**Do not commit, push, tag, create/upload a Release, publish the feed, enable Pages or change repository settings until HAT passes and iomz explicitly authorizes publication.** Local preparation scripts perform none of these actions. No GitHub Actions workflow is required.

Use a dedicated **`gh-pages` branch, root directory**, containing only generated `appcast.xml` and `.nojekyll`. This avoids exposing project/legacy docs through Pages or mixing generated feeds into source. Pre-release read-only Pages API inspection returned HTTP 404; first publication must enable branch deployment after the Release asset is verified.

After authorization, publication order is:

1. Review source diff and ensure no secrets/history/artifacts are staged. Commit approved changes, including `Package.resolved`; push `main` and create/push `v0.3.0` at the accepted commit.
2. Create GitHub Release and upload the **exact validated DMG**. Example (only after explicit authorization):

   ```sh
   gh release create v0.3.0 --repo iomz/ClipboardHistory \
     build/releases/0.3.0/ClipboardHistory-0.3.0-arm64.dmg \
     --verify-tag --title "Clipboard History v0.3.0" \
     --notes "Development-signed arm64 experiment for macOS 26+. Not notarized; not a generally trusted public installer. First Sparkle-enabled baseline."
   ```

3. Verify public asset download and compare SHA-256 with the local DMG before advertising it. GitHub's release redirect/CDN is expected; feed and asset URLs use HTTPS.
4. In a separate publishing clone (never the active source checkout), create `gh-pages` as an orphan branch for first publication. For later publication, check out the existing `gh-pages` branch and preserve its history. Copy only the prepared Pages payload:

   ```sh
   # Set SOURCE to the absolute repository path and PUBLISH to a NEW directory outside it.
   git clone --no-checkout git@github.com:iomz/ClipboardHistory.git "$PUBLISH"
   git -C "$PUBLISH" switch --orphan gh-pages  # first publication only
   cp "$SOURCE/build/pages/0.3.0/appcast.xml" "$PUBLISH/appcast.xml"
   cp "$SOURCE/build/pages/0.3.0/.nojekyll" "$PUBLISH/.nojekyll"
   git -C "$PUBLISH" add appcast.xml .nojekyll
   git -C "$PUBLISH" commit -m "Publish v0.3.0 appcast"
   git -C "$PUBLISH" push origin gh-pages
   ```

   Later releases use `git -C "$PUBLISH" switch --track origin/gh-pages` after cloning, and their new versioned payload. Never force-push or remove earlier feed items.
5. For first publication only, configure **Settings → Pages → Build and deployment → Deploy from a branch**, selecting **gh-pages / (root)**. The authorized release agent may also use GitHub's Pages API to create the site with `build_type: legacy` and `source: {branch: gh-pages, path: /}`. Require HTTPS. No custom domain needed. Wait for successful Pages deployment, then verify `https://iomz.github.io/ClipboardHistory/appcast.xml` returns XML with valid enclosure signatures, not a GitHub HTML/404 page.
6. Validate downloaded live feed against retained local artifacts before initiating any installation. A Release must exist before the feed advertises its DMG. Keep copies of published feeds and immutable DMGs for audit/rollback planning.

v0.2.0 contains no Sparkle and **cannot auto-update to v0.3.0**. v0.3.0 requires an explicitly approved manual baseline installation. v0.3.1/build 4 will be the first genuine OTA test: user checks, downloads, authorizes installation, verifies actual replacement/relaunch and clipboard/TCC continuity. Do not lower versions or publish a fake update to claim this test now.

### Release checklist

- Increment both version/build in `Resources/Info.plist`; keep bundle ID/name/storage/hotkeys unchanged.
- Run core, representation, build, signature comparison, distribution, DMG and signed-appcast checks; run `git diff --check`.
- Retain the accepted old app and immutable artifact/feed backups; do not overwrite a running installation.
- Complete human clipboard, menu, update-dialog and TCC tests below.
- Obtain explicit publication authorization before any Git/GitHub mutation.
- Publish artifact first, feed second; verify public bytes/HTTPS URLs/signatures.
- For v0.3.1+, separately record successful actual update installation **and relaunch**; otherwise report the exact Sparkle/macOS error and stop. Do not bypass Gatekeeper, SIP, TCC or signature verification.

### First-install/security limitations and future work

Apple Development signing is not Developer ID signing. `spctl --assess --type execute` rejected the locally prepared v0.3.0 candidate during automated validation. A locally built non-quarantined diagnostic could launch, but downloaded/quarantined copies may be blocked, translocated or unable to update. Do not strip quarantine, disable Gatekeeper or treat a local smoke launch as public-distribution trust. A read-only DMG is not an update installation location: copy to a separate writable test directory for initial HAT; an approved writable baseline installation is required for OTA testing.

Follow-up inspection reconciled local HAT with that assessment: installed `/Applications/Clipboard History.app` is 0.3.0/build 3, has a valid deep/strict code signature, but explicit `spctl --assess --type execute --verbose=4` still reports `rejected`. Neither the locally generated DMG nor installed app had a root `com.apple.quarantine` attribute. A locally built/copied non-quarantined app need not encounter the same Gatekeeper first-open path as a browser-downloaded quarantined artifact; explicit assessment evaluates distribution policy separately from signature integrity and local launch. No security setting or quarantine attribute was changed. Browser-download/quarantined first-install behavior has not been tested, so local success is not evidence of trusted public distribution. We cannot retrospectively identify every process involved in the user's earlier launch; their successful-launch report is retained as HAT evidence, not upgraded into public-distribution acceptance.

The diagnostic on the mounted DMG also emitted `sandbox_extension_issue_file_to_process failed ...: 1 (Operation not permitted)` while exiting successfully after Sparkle/menu startup. The writable candidate diagnostic did not emit it. Record this limitation rather than treating the read-only launch as installer proof. macOS 27 also warns that `hdiutil` commands and SwiftPM's native backend are deprecated; both completed successfully in this environment.

Future trusted public distribution requires Developer ID Application signing, appropriate hardened runtime/entitlements for all Sparkle helpers, notarization and stapling, plus fresh quarantine and identity/TCC migration testing. It is intentionally deferred. Development certificate validity/trust and installation permissions can also affect real updates; successful compilation/signature verification alone does not establish installer compatibility. No real Sparkle installation/relaunch was tested in v0.3.0 preparation.

### Mandatory next milestones

- **v0.3.1/build 4 OTA test:** implements picker handoff, Manager favorite symbols and native opt-in automatic checks. Owner accepted local HAT and explicitly authorized publication on 2026-10-09. Detection, artifact download, EdDSA verification, installation, relaunch, persisted history and Accessibility/TCC continuity still require an owner-performed real update after publication. Feed validation/no-update UI is not an OTA PASS.
- **Developer ID/notarization:** mandatory before trusted public distribution. Pre-release local inspection found one usable Apple Development identity but **no usable Developer ID Application signing identity**. Active Apple Developer Program membership was not verified; an Apple Development certificate does not prove current enrollment. No notarization profile/authentication is configured in this project or supplied for validation. `notarytool` is installed, but tool presence is not credential readiness. Required: confirmed active program membership, Developer ID Application certificate with accessible matching private key, and valid notarization authentication (approved Apple ID/app-specific password/team or App Store Connect API credentials, stored securely as a local profile), followed by hardened-runtime/notarization/stapling tests. No private certificate details are recorded, no secrets inspected, and existing development signing remains unchanged.

## v0.3.1 candidate HAT (accepted)

Owner reported PASS on 2026-10-09: 0.3.1/build 4 launch, existing clipboard functionality, picker Shift-Command-Space handoff, favorite `star.fill` UI/toggling, automatic-check preference persistence and manual Sparkle check. Candidate correctly reported published v0.3.0 as newest available while running v0.3.1. Publication explicitly authorized; actual OTA installation/relaunch and TCC continuity remain unverified. Checklist below records the pre-publication candidate procedure, not an OTA result.

Do not replace or relaunch installed `/Applications/Clipboard History.app` from tooling. Owner may quit it for testing; do not run two copies in the same account (shared shortcuts/defaults). For full consent/opt-in/out tests, use a separate macOS test account: same bundle ID in the same account means shared Sparkle preferences, even when the app path differs. Never delete/reset production defaults or TCC to simulate a fresh install. The public feed must continue advertising only v0.3.0 until explicit publication approval.

1. Mount candidate DMG and inspect app/Applications shortcut; **do not drag onto Applications**. Copy app into a new writable location, e.g. `build/hat/0.3.1/Clipboard History.app`, refusing an existing destination. Launch that exact copy with disposable history storage:

   ```sh
   mkdir -p build/hat/0.3.1
   test ! -e "build/hat/0.3.1/Clipboard History.app" && \
     ditto "/Volumes/Clipboard History 0.3.1/Clipboard History.app" "build/hat/0.3.1/Clipboard History.app"
   CLIPHISTORY_SUPPORT_DIRECTORY="$PWD/build/hat/0.3.1/support" \
     "$PWD/build/hat/0.3.1/Clipboard History.app/Contents/MacOS/ClipboardHistory"
   ```

   Ordinary launch opens Manager. Keep installed baseline untouched; do not bypass a security block. About must show **0.3.1 (4)**. A copy at a different path/test account is not definitive evidence of existing TCC continuity; do not regrant/reset production authorization to make candidate tests green.
2. Use disposable content to check capture, persistence across candidate quit/relaunch, rich Enter/plain Shift-Enter, Option-Command-V, Shift-Command-V, search, Ctrl-N/P, arrows, Escape and hover previews. When path/account permissions prevent synthetic paste, record that limitation; definitive existing-authorization paste test occurs after real OTA installation in `/Applications`.
3. With picker open and search focused, press **Shift-Command-Space**. Picker/hover dismiss; Manager opens/activates and typing goes into Manager search immediately. Clipboard contents must not change. Confirm shortcut does nothing special outside picker. Test with Caps Lock, and confirm additional Option/Control does not invoke it. If system input-source selection consumes the chord, inspect the conflicting OS shortcut manually; no new global binding is installed.
4. Toggle favorite using existing Favorite/Unfavorite button. Confirm native `star.fill` in favorite row and button, readable selected/unselected appearance, accessible Add/Remove/Favorite labels, Favorites filtering and persisted state after candidate restart. Non-favorite row has no star. Menu-bar icon must remain unchanged.
5. Close Manager, use **Check for Updates…** in status menu, and verify standard Sparkle UI without Manager reopening. Repeat via application menu. Candidate build 4 is newer than currently public build 3: no update offer is expected; exact standard alert wording may differ. This is not an installed-update test.
6. In clean test-account defaults, first launch has no automatic checks; normally second launch asks native permission. Reject once and relaunch: checkbox remains off. Explicitly enable **Automatically Check for Updates**, then relaunch: checkbox remains on. Use Console's `com.iomz.ClipboardHistory` / `Updates` logs to inspect native scheduled delay and 86400-second default. After manual check, next delay should reflect native scheduling rather than picker/activation. Disable checkbox, relaunch, and confirm no schedule. Do not force a short production interval or wait-loop. Actual 24-hour firing requires time/observation; diagnostics alone do not prove it.
7. On existing v0.3.0 preferences, expect automatic checkbox **off** without a repeat consent prompt; upgrade must not erase that stored NO. Opt-in is an explicit owner action after real OTA, not an automatic migration. Background downloading/installing stays disabled regardless of automatic-check choice.
8. Quit candidate. Verify installed bundle remains 0.3.0/build 3 and unchanged; eject DMG. Report candidate HAT and any input-source/TCC limits. No commit, push, tag, Release, upload or Pages modification until explicit approval.

After approval, a separate publication/OTA task must use installed v0.3.0 to detect build 4, download/verify the published DMG, install/relaunch through Sparkle, then verify About, history/favorites persistence and Accessibility paste without regrant. v0.3.1 auto-check preference must be inspected explicitly; no actual OTA PASS is claimed during preparation.

## v0.3.1 publication validation and owner OTA procedure

Final publication preparation on 2026-10-09 passed core, representation, About, interaction/favorite-state, Sparkle preference, Release arm64, outer/nested signature, v0.3.0 designated-requirement comparison, read-only DMG, EdDSA/tamper and multi-release appcast merge checks. Accepted candidate artifacts were preserved before rebuilding. Final DMG SHA-256: `ce4faee77923190fa20b62db0f7820851d2370afdfb680b9b94f530fa6e11bd3`. Production key recovery was previously accepted; signing capability/public-key equality was reverified without exporting private material. Installed v0.3.0 must remain unchanged during publication.

After public release/feed validation, owner performs the real OTA:

1. Quit any isolated candidate copy. Use installed `/Applications/Clipboard History.app`; verify About 0.3.0/build 3 and record a few existing history/favorite entries. Keep normal history backup; do not clear history or reset Accessibility permissions.
2. Close Manager; choose status-menu **Check for Updates…**. Confirm Sparkle offers 0.3.1/build 4 without reopening Manager.
3. Choose Sparkle's download/install action. Observe successful download and no signature/security error. Automated verification of public DMG EdDSA is separate from observing the installed updater's successful validation; capture errors rather than bypassing them.
4. Use Sparkle's install/relaunch action. Do not manually copy an app, replace `/Applications`, disable Gatekeeper or regrant/reset TCC. If installation or relaunch fails, stop and report the exact message.
5. After Sparkle relaunch, verify installed path and About 0.3.1/build 4. Confirm recorded history/favorites remain, new capture works, rich/plain paste into another app works with existing Accessibility authorization, and picker-to-Manager handoff/favorite symbols work.
6. Inspect **Automatically Check for Updates**. Stored NO from v0.3.0 must remain NO unless owner previously explicitly enabled checks during same-account candidate HAT. Explicitly opt in if desired; confirm choice survives normal relaunch and `Updates` logs report native scheduling with 86400-second default (remaining delay may be shorter). Background download/automatic install remain disabled.
7. Report detection, download/verification, installation, relaunch, version, history/favorites and TCC results separately. No real OTA success is recorded until owner confirms them.

## v0.3.0 human acceptance history

### Final candidate acceptance

Owner confirmed **ALL PASS** before publication: launch/normal clipboard workflows; About 0.3.0/build 3; manual Sparkle check without History Manager reopening; Accessibility-backed paste without permission reset/regrant. Backup/recovery also passed. After publication, owner must still check the installed v0.3.0 app against the live HTTPS feed: check succeeds, v0.3.0 is current, no update offered. This public-feed HAT and the later v0.3.1 install/relaunch are not claimed complete by automated validation.

### First-round feedback and About discrepancy

Owner reports DMG mounted, app dragged to `/Applications`, successful launch and existing workflows operational; installed metadata confirmed 0.3.0/build 3. **Check for Updates…** UI and Accessibility/TCC continuity have not been explicitly tested; no updater installation/relaunch was tested.

At follow-up inspection, the only observed running executable was still `build/Clipboard History.app/Contents/MacOS/ClipboardHistory` (v0.2.0), while installed `/Applications` bundle was v0.3.0. Original About menu called AppKit's standard panel and contained no hard-coded version; it displayed the running process's old bundle, not the newly copied bundle. Launch Services can reopen an already running app with the same bundle identifier rather than replace its process. Copying a new app does not update an old process. The observed stale process explains the discrepancy; the exact earlier click was not instrumented.

About now explicitly passes `CFBundleShortVersionString` and `CFBundleVersion` from **`Bundle.main` of the running process** to the standard panel, with no separate version constants. Fixture regression checks verify two different bundle versions/builds; distribution smoke verifies actual About menu target and prints running bundle path/version/build. A v0.2.0 process must continue to report v0.2.0 honestly. No bundle-ID change, forced process termination or altered reopen policy is used to hide this issue.

For follow-up HAT, quit the current copy using its menu first. Confirm no old copy remains via `pgrep -fl ClipboardHistory`, then launch the exact desired app path. Do not use `open -n` while another copy is active, since two copies share store and hotkey bindings. The newly regenerated candidate must be tested separately: this work does not overwrite the installed `/Applications` app. Verify About displays **0.3.0 (3)**, then test the update-menu UI with Manager closed/open, and explicitly verify automatic paste still works with existing Accessibility grant. Unpublished feed failure is expected. Actual update installation/relaunch remains deferred to a later authorized release.

### Original first-round procedure

1. **While the existing v0.2.0 app is still running**, copy disposable text, invoke Option-Command-V, and paste into a scratch document. Check Manager/history/favorites and plain-text paste. Quit/reopen the existing app at `build/Clipboard History.app` if checking persistence. Confirm it still works before testing the candidate. Do not change Accessibility settings or replace `/Applications` contents.
2. Mount `build/releases/0.3.0/ClipboardHistory-0.3.0-arm64.dmg` in Finder. Confirm `Clipboard History.app` and `Applications` shortcut. **Do not drag onto Applications.** Inspect bundle Info.plist (0.3.0/build 3, unchanged `com.iomz.ClipboardHistory`), and verify signatures with `codesign --verify --deep --strict` if desired.
3. Quit v0.2.0 using its menu. Do not run two copies together (shared store/hotkey conflicts). Optionally back up existing history to a protected location outside the repository while both copies are stopped; do not delete/reset it. Copy the mounted app into a new writable test directory without replacing anything:

   ```sh
   mkdir -p build/hat/0.3.0
   test ! -e "build/hat/0.3.0/Clipboard History.app" && \
     ditto "/Volumes/Clipboard History 0.3.0/Clipboard History.app" "build/hat/0.3.0/Clipboard History.app"
   ```

4. Launch that **exact copy** with `open -n "$PWD/build/hat/0.3.0/Clipboard History.app"`. Ordinary launch should show Manager as before. If macOS blocks it, record the exact dialog/error and stop; do not weaken security. No automatic-check permission prompt/background check should occur.
5. Close Manager; choose status-menu **Check for Updates…**. Sparkle's standard checking/error UI should appear **without reopening Manager**. Also check the application-menu item while Manager is open. Before publication, an HTTPS feed error/404 is expected—not a successful update/no-update result. Dismiss it. Do not publish anything to make this HAT pass.
6. Check capture, persistence, rich Enter/plain Shift-Enter, Option-Command-V, Shift-Command-V, picker navigation/hover previews, Manager and favorites with disposable content. Existing history should remain available. Automatic paste should retain existing Accessibility authorization under the same stable signing identity. If denied, report it; do not reset TCC or silently grant new permission.
7. Quit candidate, reopen the retained v0.2.0 app, confirm history/paste still work, and eject DMG. Report results and request any needed installation/publication authorization separately. Nothing is automatically installed over the original app.

## Deferred / not planned

- No legacy-history importer.
- No Clear History on Exit.
- No retention controls or Save As UI currently required.
- Do not implement Settings yet. Next milestone should design only useful exclusions, pause/resume capture, launch-at-login, and shortcut configuration needs, then ask iomz before adding settings scope.

## Open product question

If real source apps advertise both file-reference and image representations for a copied image, should the manager/picker ultimately show `MIX`, `IMG`, or `FILE`? Current implementation uses neutral `MIX`; gather the metadata report first, then ask iomz if a non-neutral preference is needed.
