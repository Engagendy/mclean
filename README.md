<p align="center">
  <img src="MClean/MClean/Assets.xcassets/AppIcon.appiconset/icon-256.png" width="128" height="128" alt="MClean Icon">
</p>

<h1 align="center">MClean</h1>

<p align="center">
  <strong>A native macOS cleanup scanner for finding cache, temporary, old, and large files</strong><br>
  Native SwiftUI &bull; Safe review workflow &bull; Stage or Trash cleanup
</p>

<p align="center">
  <a href="https://github.com/Engagendy/mclean/releases"><img src="https://img.shields.io/github/v/release/Engagendy/mclean?style=flat-square&label=download" alt="Release"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5-orange?style=flat-square" alt="Swift">
  <img src="https://img.shields.io/badge/price-free-brightgreen?style=flat-square" alt="Free">
</p>

---

MClean is a native SwiftUI macOS app for finding cleanup candidates on a Mac. It scans common cache, temporary, Downloads, large-file, and old-file locations, then lets the user review selected items, move them to Stage for testing, or move them to Trash.

## Quick Start

1. Install with Homebrew or download the latest DMG from [GitHub Releases](https://github.com/Engagendy/mclean/releases).
2. Open MClean and press **Scan**. The app does not scan automatically on launch.
3. Review the streamed results, sort by size, select the files you want, then move them to Stage for testing or move them to Trash.

## Installation

### Homebrew (recommended)

```bash
brew tap Engagendy/tap
brew install --cask mclean
```

### Direct Download

1. Download the latest `.dmg` from [GitHub Releases](https://github.com/Engagendy/mclean/releases).
2. Open the DMG and drag **MClean** to your Applications folder.
3. On first launch, right-click the app, choose **Open**, then confirm **Open**.

### Gatekeeper Bypass

MClean is not signed with an Apple Developer certificate yet, so macOS may show an "unidentified developer" warning.

**Option A - Right-click Open (recommended):** right-click or Control-click the app, choose **Open**, then click **Open**.

**Option B - Remove quarantine attribute:**

```bash
xattr -cr /Applications/MClean.app
```

**Option C - System Settings:** go to **System Settings -> Privacy & Security**, scroll down, and click **Open Anyway** next to the MClean message.

### Full Disk Access

MClean can scan normal user folders without Full Disk Access. macOS blocks some protected locations unless you grant access.

1. Open MClean.
2. Click **Open Full Disk Access** in the banner, or open **System Settings -> Privacy & Security -> Full Disk Access**.
3. Add **MClean** from `/Applications`.
4. Turn the switch on for MClean.
5. Quit and reopen MClean, then scan again.

## Features

- Native macOS sidebar, toolbar, sortable table, and multi-selection.
- Quick, Deep, and Custom scan modes.
- Live streaming scan results with phase progress, remaining-phase estimates, and category skipping.
- Previous scan results are restored on launch and refreshed on the next scan.
- Full Disk Access guidance for protected macOS locations.
- Review-before-delete sheet with high-risk and missing-file warnings.
- Stage workflow for testing after files are moved out of their original locations, with stale-item reminders.
- Settings with persisted scan options and folder exclusions.
- Search and advanced filters for size, modified date, risk, protection, source, and path.
- Browser cache scanning for Safari, Chrome, Edge, and Firefox with profile warnings.
- Duplicate review with grouped identical files and keep-helper selection actions.
- Never-delete protection for sensitive macOS and user-library locations.
- File details panel with risk, protection, duplicate, and app-leftover metadata.
- Trash history with restore support for recently moved items.
- Duplicate file grouping and app-leftover detection.
- Developer cleanup coverage for Xcode, simulators, npm, pnpm, Gradle, Docker, Go, Cargo, and related caches.

## Roadmap

The tracked implementation plan lives in [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md). It covers cleanup coverage, user experience, and power features with task status and acceptance criteria.

## Safety Model

MClean defaults to reversible cleanup paths. Selected items can be moved to Stage first, then restored, moved to Trash, or permanently deleted from the Stage view after confirmation. The direct cleanup action still moves selected items to the macOS Trash so the user can restore them if needed.

## Build

### Requirements

| Requirement | Version |
|-------------|---------|
| macOS | 14.0 Sonoma or later |
| Xcode | 16.0+ recommended |
| Homebrew | Optional, for cask installation |

### Development Setup

```bash
git clone https://github.com/Engagendy/mclean.git
cd mclean
open MClean.xcodeproj
```

Select the **MClean** scheme, choose **My Mac** as the destination, and run the app.

### Building a DMG for Distribution

```bash
./scripts/package.sh --version 1.0.0
```

The packaged DMG is written to `build/MClean-<version>-<arch>.dmg`.

Options: `--arch arm64|x86_64`, `--version X.Y.Z`

## Release

Releases follow the same pattern as the MPP Viewer project:

```bash
git tag v1.0.0
git push origin v1.0.0
```

On tag push, GitHub Actions:

- builds the DMG on macOS
- creates the GitHub release
- attaches the DMG release asset
- updates `Engagendy/homebrew-tap` with the new cask version and SHA256

The automatic tap update requires a `HOMEBREW_TAP_TOKEN` repository secret on `Engagendy/mclean`. Use a fine-grained GitHub token with Contents read/write access to `Engagendy/homebrew-tap`.

Repository: https://github.com/Engagendy/mclean
