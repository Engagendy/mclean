# MClean

MClean is a native SwiftUI macOS app for finding cleanup candidates on a Mac. It scans common cache, temporary, Downloads, large-file, and old-file locations, then lets the user review and move selected items to Trash.

## Features

- Native macOS sidebar, toolbar, sortable table, and multi-selection.
- Quick, Deep, and Custom scan modes.
- Live streaming scan results so files appear while scanning continues.
- Previous scan results are restored on launch and refreshed on the next scan.
- Full Disk Access guidance for protected macOS locations.
- Review-before-delete sheet with high-risk and missing-file warnings.

## Build

```bash
./scripts/package.sh --version 1.0.0
```

The packaged DMG is written to `build/MClean-<version>-<arch>.dmg`.

## Distribution

Releases follow the same pattern as the MPP Viewer project:

- push a `v*` tag
- GitHub Actions builds the DMG
- the release asset is attached to the GitHub release
- the Homebrew tap cask is updated with the new version and SHA256

Repository: https://github.com/Engagendy/mclean

## Safety Model

MClean does not permanently delete files. Cleanup actions move selected items to the macOS Trash so the user can restore them if needed.
