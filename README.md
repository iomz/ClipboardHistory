<p align="center">
  <img src="Resources/Artwork/Dustlight.png" width="128" height="128" alt="The Clipboard — Dustlight icon">
</p>
<h1 align="center">The Clipboard</h1>
<p align="center">📋 Copy now. Find it later. A little clipboard companion for macOS.</p>
<p align="center">
  <a href="https://github.com/iomz/TheClipboard/releases"><img src="https://img.shields.io/badge/release-unpublished-8b5cf6?style=flat" alt="Release — unpublished"></a>
  <a href="#-download"><img src="https://img.shields.io/badge/macOS-26%2B-007AFF?style=flat" alt="macOS 26 or later"></a>
  <a href="#-download"><img src="https://img.shields.io/badge/Apple_Silicon-arm64-14b8a6?style=flat" alt="Apple Silicon — arm64"></a>
</p>

## ✨ Little things, kept handy

- 📋 Native macOS clip collection, saved locally.
- ⚡ A compact, keyboard-driven picker for quick pasting.
- 📝 Keep rich formatting—or paste plain text instead.
- 🔎 Search past clips and browse them in History Manager.
- ⭐ Favorite the things you reach for most.
- 🦋 Sparkle updates, right from the menu bar.
- 🌈 Switch between Dustlight and Lagoon application icons from the menu bar. Your choice sticks across launches.

## ⌨️ Your shortcuts

| Shortcut         | Action                                                    |
| ---------------- | --------------------------------------------------------- |
| ⌥⌘V              | Open the picker                                           |
| ⌃N / ⌃P or ↓ / ↑ | Move through picker results                               |
| Return           | Paste the selected clip                                   |
| ⇧Return          | Paste the selected clip as plain text, when available     |
| ⇧⌘V              | Paste the current clipboard as plain text, when available |
| ⇧⌘Space          | Open History Manager from the picker                      |
| Esc              | Dismiss the picker                                        |

Type in the picker to search. If macOS input-source shortcuts intercept ⇧⌘Space, use **Open History Manager…** from the menu bar.

## 📦 Download

Requires **macOS 26+ and Apple Silicon**. **The Clipboard v0.4.0 is in development, not released yet.** Future DMGs will appear under [Releases](https://github.com/iomz/TheClipboard/releases). For now, see the [build instructions](DEVELOPMENT.md).

🪴 A fresh application identity with its own clips, favorites and settings. No data or preferences are imported from another app. Allow Accessibility for **The Clipboard** when prompted to paste into other apps.

⚠️ Builds are **development-signed, not Developer ID signed or Apple-notarized**. Gatekeeper may block launch. If blocked, stop rather than bypassing macOS security.

## 🦋 Updating

Sparkle is ready for The Clipboard's own future updates. Choose **Check for Updates…** from the menu bar; until the new feed is published, a feed error is expected. Automatic checks are opt-in; downloads and installation remain manual.

## 🛠️ Make yourself at home

Built with SwiftPM and AppKit. See [DEVELOPMENT.md](DEVELOPMENT.md) for building, testing and contributing. Small fixes and thoughtful ideas welcome! 💛

## 🪪 Author & License

**Iori Mizutani** ([@iomz](https://github.com/iomz))

MIT License. See [LICENSE](LICENSE).
