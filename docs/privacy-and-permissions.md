# Chronicle Privacy & Permissions

Chronicle is designed to be offline-first. Your activity database stays local on your Mac.

This page explains what Chronicle stores, what permissions it may ask for, and how to remove your data.

## What Chronicle stores (locally)

- App sessions (app name + optional bundle ID)
- Idle sessions (when idle detection is enabled)
- Tags, tag rules, and app mappings
- Markers and marker spans (notes you enter)
- Optional window titles (only if you enable window-title capture)
- Export settings (folder bookmarks, templates, last export status)

Data lives under Application Support:

- Folder: `~/Library/Application Support/Chronicle`
- Main DB: `activity.sqlite` (+ WAL/SHM side files)

## Network behavior

- Chronicle does not sync or upload your database.
- The app can open GitHub release pages when you click "Check for Updates" or "Open Releases Page".

## Permissions

## Accessibility

Used for:

- Window-title capture (optional, off by default)

If you do not enable window-title capture, Chronicle should work without Accessibility permission.

## Window titles and privacy modes

When window-title capture is enabled, you can choose a privacy mode:

- Raw: store the full title text
- Length: store only `length:N`
- Hash: store only `sha256:...`

Exports and diagnostics follow your chosen policy, and titles can be dropped entirely for selected apps via the blocklist.

## Optional local telemetry (off by default)

Chronicle can track anonymous usage counters locally (no content, no text).

- Default: disabled
- When enabled: counters are stored in local user defaults
- Export: you can export a local JSON snapshot at any time from Preferences -> Privacy

## Remove all data

In-app path:

- Preferences -> Privacy -> Wipe Data

This deletes the local Chronicle database files. This action is irreversible.

