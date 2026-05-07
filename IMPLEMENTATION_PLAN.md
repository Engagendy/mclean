# MClean Implementation Plan

This plan tracks the next feature set by implementation area. Status values:

- `[ ]` Not started
- `[~]` Partial or foundation exists
- `[x]` Complete

## Milestone 1: Cleanup Coverage

### App Leftovers Detection

Status: `[~]`

Current foundation:

- Existing scanner detects probable bundle-ID leftovers in user caches, application support, containers, HTTPStorages, and WebKit.
- Existing findings can carry `relatedBundleID`.

Implementation tasks:

- `[ ]` Expand installed-app inventory to include `/System/Applications`, Setapp-style app locations, and nested app bundles.
- `[ ]` Detect package receipts from `/Library/Receipts`, `/private/var/db/receipts`, and user-visible install metadata where readable.
- `[ ]` Detect launch agents and launch daemons related to removed apps.
- `[ ]` Detect preferences in `~/Library/Preferences`.
- `[ ]` Detect logs in `~/Library/Logs` and related diagnostic locations.
- `[ ]` Group leftovers by bundle ID in the UI.
- `[ ]` Add confidence labels for leftovers: exact bundle ID, probable bundle ID, weak name match.
- `[ ]` Add tests for bundle-ID parsing and installed-app exclusion behavior.

Acceptance criteria:

- App leftovers show the related bundle ID and source type.
- Installed apps are not flagged as leftovers.
- Launch agents, preferences, containers, caches, logs, and receipts are grouped under the same app when possible.
- Weak matches require review and are never recommended for automatic cleanup.

### Browser Cleanup Modules

Status: `[ ]`

Implementation tasks:

- `[ ]` Add browser categories or source metadata for Chrome, Edge, Firefox, and Safari.
- `[ ]` Detect browser cache folders per profile without scanning browsing history content.
- `[ ]` Add clear profile warnings before selecting browser data.
- `[ ]` Keep cookies, passwords, bookmarks, history, sessions, and profile databases protected by default.
- `[ ]` Add browser-specific scan toggles in settings and scan profiles.
- `[ ]` Add tests for protected browser paths.

Acceptance criteria:

- Browser cache findings identify browser name and profile path.
- The UI warns when an item belongs to a named browser profile.
- Sensitive browser data is blocked or marked never-delete.

### Developer Cleanup Presets

Status: `[~]`

Current foundation:

- Existing scanner includes Xcode, simulator, SwiftPM, Homebrew, npm, yarn, pnpm, Gradle, Maven, Go, Cargo, Rustup, and Docker paths.

Implementation tasks:

- `[ ]` Split developer data into named source types: Xcode, Docker, JavaScript, Python, Rust, Go, Gradle, Maven, Homebrew.
- `[ ]` Add a Developer scan profile that enables developer cleanup without unrelated categories.
- `[ ]` Add Xcode-specific coverage for DerivedData, Archives, DeviceSupport, Products, Previews, XCTestDevices, and simulator caches.
- `[ ]` Add Docker preview for caches, images, volumes, and VM storage without deleting Docker resources blindly.
- `[ ]` Add npm, pnpm, and yarn cache modules.
- `[ ]` Add Python cache modules for pip, virtualenv, Poetry, Pipenv, pyenv build caches, and common `__pycache__` handling.
- `[ ]` Add Rust, Go, and Gradle cache modules with source-specific explanations.
- `[ ]` Add source-specific tests for developer roots.

Acceptance criteria:

- Developer findings explain which tool owns the data.
- Docker findings are review-only and explain whether Docker should be running or stopped.
- The Developer profile can be selected independently from Quick and Deep.

### Large Duplicate Review

Status: `[~]`

Current foundation:

- Existing duplicate scanner groups files by size and SHA-256 hash.
- Existing items include duplicate group ID and count.

Implementation tasks:

- `[ ]` Add duplicate group view with one group per hash.
- `[ ]` Add preview support for duplicate files.
- `[ ]` Add helper selection actions: keep newest, keep oldest, keep file in original folder, keep shortest path.
- `[ ]` Prevent selecting all files in a duplicate group.
- `[ ]` Add per-group restore/stage/delete workflow compatibility.
- `[ ]` Add tests for duplicate grouping and keep-helper selection rules.

Acceptance criteria:

- Duplicate review makes it obvious which files are identical.
- Bulk helpers never select every item in a duplicate group.
- Duplicate cleanup remains review-only by default.

## Milestone 2: User Experience

### Settings Screen

Status: `[ ]`

Implementation tasks:

- `[ ]` Add a macOS Settings scene or in-app settings sheet.
- `[ ]` Move scan options into Settings where they persist between app launches.
- `[ ]` Add exclusions management.
- `[ ]` Add Stage preferences such as reminder age and default action visibility.
- `[ ]` Add browser and developer module toggles.

Acceptance criteria:

- Settings are discoverable from the app menu and toolbar/menu actions.
- User choices persist across launches.

### Saved Scan Profiles

Status: `[~]`

Current foundation:

- Quick, Deep, and Custom scan modes exist.

Implementation tasks:

- `[ ]` Add Developer profile.
- `[ ]` Add Downloads Review profile.
- `[ ]` Persist last selected profile.
- `[ ]` Support user-created custom profiles.
- `[ ]` Show which categories each profile includes.

Acceptance criteria:

- Selecting a profile changes scan options predictably.
- Custom profile edits do not mutate built-in profiles.

### Search And Advanced Filters

Status: `[ ]`

Implementation tasks:

- `[ ]` Add search field for name and path.
- `[ ]` Add filters for size range, modified date, category, risk, protection, source type, and path contains.
- `[ ]` Add filter chips or a compact filter summary.
- `[ ]` Make selection actions operate only on visible filtered results.

Acceptance criteria:

- Search and filters combine predictably.
- Result counts and selected bytes reflect the active filter.

### File Preview

Status: `[ ]`

Implementation tasks:

- `[ ]` Add preview panel for selected or detail item.
- `[ ]` Support images, text, PDFs, and video metadata.
- `[ ]` Use Quick Look where appropriate.
- `[ ]` Fall back to metadata-only preview for unsupported files.

Acceptance criteria:

- Preview never requires moving or modifying the file.
- Unsupported files show useful metadata instead of an empty panel.

### Progress Estimates And Per-Category Cancellation

Status: `[~]`

Current foundation:

- Scans stream progress messages and can be cancelled globally.

Implementation tasks:

- `[ ]` Track current scan phase and category.
- `[ ]` Add per-category progress counts where enumerable.
- `[ ]` Allow skipping the current category while continuing the scan.
- `[ ]` Estimate remaining phases without claiming exact time.

Acceptance criteria:

- Users can see which category is scanning.
- Users can skip a slow category without losing completed results.

## Milestone 3: Power Features

### Scheduled Scans

Status: `[ ]`

Implementation tasks:

- `[ ]` Add manual opt-in scheduled scan settings.
- `[ ]` Use macOS notifications for scan summaries.
- `[ ]` Keep cleanup manual: scheduled scans never delete, stage, or trash files.
- `[ ]` Add schedule pause and disable controls.

Acceptance criteria:

- Scheduled scans only report findings.
- Notifications open the app to the latest results.

### Stage Age Reminders

Status: `[~]`

Current foundation:

- Stage entries persist `stagedAt`.

Implementation tasks:

- `[ ]` Add configurable Stage reminder age.
- `[ ]` Show staged item age in Stage view.
- `[ ]` Notify or badge when staged items exceed the reminder age.
- `[ ]` Add "Move old staged items to Trash" bulk action with confirmation.

Acceptance criteria:

- Users can identify stale staged files quickly.
- Reminders never delete files automatically.

### Finder Context Actions

Status: `[~]`

Current foundation:

- Existing rows can reveal files in Finder.

Implementation tasks:

- `[ ]` Add context menu actions to result rows.
- `[ ]` Add copy path action.
- `[ ]` Add exclude parent folder action.
- `[ ]` Add reveal original path for staged entries.
- `[ ]` Add reveal staged file action.

Acceptance criteria:

- Context actions are available without opening details.
- Excluding a parent folder persists and removes matching findings on the next scan.

### Command-Line Mode

Status: `[ ]`

Implementation tasks:

- `[ ]` Define a minimal CLI contract for scan/report only.
- `[ ]` Add JSON output for automation.
- `[ ]` Add profile selection flags.
- `[ ]` Keep destructive operations out of the first CLI version.
- `[ ]` Document examples.

Acceptance criteria:

- CLI can run a scan and output JSON without launching the full UI.
- CLI does not delete, stage, or trash files in the first version.

## Execution Order

1. Settings, persisted options, and exclusions.
2. Search and advanced filters.
3. Source metadata model for browser, developer, and app leftover findings.
4. Developer profile and source-specific developer modules.
5. Browser cleanup modules with protected sensitive paths.
6. App leftovers grouping and confidence labels.
7. Duplicate group review and helper selection actions.
8. Stage age reminders and Finder context actions.
9. Progress estimates and category skipping.
10. Scheduled scan notifications.
11. CLI scan/report mode.

## Tracking Rules

- Mark a task `[~]` when production code exists but the acceptance criteria are not fully met.
- Mark a task `[x]` only after the feature builds, has basic verification, and the README or in-app copy is updated when user-facing behavior changes.
- Prefer small commits by milestone or feature slice.
- Keep destructive actions behind explicit confirmation.
