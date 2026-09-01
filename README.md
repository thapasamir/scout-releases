# Scout — Screenshot Search for macOS

> Find any screenshot instantly — by the text inside it, by what you remember seeing, or both at once.

Scout lives in your menu bar and watches your screenshot folders. Every image is automatically read, indexed, and made searchable in seconds. No cloud. No subscriptions. Everything stays on your Mac.

---

## Features

**🔍 Three ways to search**
- **Exact** — find screenshots containing specific words or phrases (fast full-text search with stemming)
- **Meaning** — describe what you remember and Scout finds it, even if those words aren't in the image
- **Both** — runs both at once; results matching both float to the top

**⚡ Always up to date**
Screenshots land in your folder and are indexed instantly — no manual importing, no syncing.

**🤖 Auto-categories**
Scout classifies every screenshot into categories — Code, Terminal, Chat, Design, Meeting, Media, Error — so you can browse without searching.

**🏷️ Manual tags**
Tag screenshots yourself and find them later by tag from the sidebar.

**🧠 Smart clusters**
After indexing, Scout groups your screenshots into topic clusters automatically using AI — no tagging required.

**👁️ Quick Look**
Press Space on any screenshot to preview it full-size. Use arrow keys to step through results while previewing.

**⌥⇧Space — hotkey palette**
Open a floating search palette from any app, any time, without switching windows.

**🔦 Spotlight integration**
Every indexed screenshot appears in macOS Spotlight. Click a result and Scout opens it directly.

**🔒 Completely private**
OCR, AI search, and classification all run locally on your Mac. Scout makes zero network requests. Your screenshots never leave your device.

---

## Screenshots

<!-- Add screenshots here after first release -->

---

## Install

### Requirements
- macOS 13.0 (Ventura) or later
- Apple Silicon or Intel Mac

### Steps

1. **Download** `Scout.pkg` from the [latest release](../../releases/latest)
2. **Open** the downloaded file — macOS Installer will launch
3. **Click through** the installer (Introduction → License → Install)
4. **Open Scout** from your Applications folder — it appears in the menu bar and Dock

> **Note:** Scout is currently unsigned. On first open, right-click `Scout.app` → **Open** → **Open** to bypass the Gatekeeper warning. This is a one-time step.

---

## Getting started

1. Click **Choose Screenshots Folder…** on the welcome screen
2. Wait for indexing to finish (progress bar at the bottom)
3. Search for anything — a word you saw, a URL, an error message, or describe what you remember

**Tip:** macOS saves screenshots to `~/Desktop` by default — that's a good first folder to add.

---

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| `⌥ ⇧ Space` | Open / close floating palette (from any app) |
| `Space` | Quick Look preview |
| `↑ ↓ ← →` | Navigate the grid |
| `↵` | Open detail view |
| `⌫` | Delete selected (in select mode) |
| `Esc` | Exit select mode / close preview |
| `⌘ ,` | Settings |

---

## Privacy

Scout processes everything locally:

| What | Where |
|------|-------|
| Screenshot index | `~/Library/Application Support/Scout/screenshots.db` |
| Thumbnails | `~/Library/Application Support/Scout/Thumbnails/` |
| Settings | `~/Library/Preferences/com.samirthapa.scout.plist` |

No analytics. No crash reporting. No network requests during normal use.

---

## Uninstall

Open Scout → menu bar icon → **Uninstall Scout…**

Or manually:
```bash
sudo rm -rf /Applications/Scout.app
rm -rf ~/Library/Application\ Support/Scout
```

---

## License

Copyright © 2026 Samir Thapa. All rights reserved.

Scout is free to use. The developer reserves the right to introduce paid plans in the future. See [LICENSE](LICENSE) for full terms.
