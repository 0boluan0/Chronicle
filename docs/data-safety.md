# Chronicle Data Safety Guide

This guide explains where your data lives, how to back it up, and how to validate upgrades safely.

## Where data is stored

- App data folder: `~/Library/Application Support/Chronicle`
- Main DB file: `activity.sqlite`
- SQLite side files (normal): `activity.sqlite-wal`, `activity.sqlite-shm`
- Chronicle is offline-first and does not sync your database to cloud services.

## What may contain sensitive context

- App names and bundle IDs
- Window titles (if enabled)
- Markers and marker spans entered by you
- Diagnostics package snapshots (settings and runtime metadata)

## Backup recommendations

Use one of these before app upgrades or large data edits:

1. Finder copy
   - Quit Chronicle first.
   - Copy the entire `~/Library/Application Support/Chronicle` folder.
2. Terminal archive
   - `tar -czf chronicle-backup-$(date +%Y%m%d-%H%M%S).tar.gz ~/Library/Application\\ Support/Chronicle`

## Validate an upgrade (quick path)

1. Confirm app launches normally.
2. Open Timeline/Stats and verify historical data appears.
3. Export one Markdown report and one CSV file.
4. If window-title privacy mode is not `Raw`, confirm exports do not contain raw titles.
5. Run Health Check from Debug panel (if available).

## Validate on a safe copy

Before testing a beta build or release candidate against real data:

1. Quit Chronicle.
2. Copy `~/Library/Application Support/Chronicle` to a disposable validation folder.
3. Keep your original backup untouched until the candidate passes launch and export checks.
4. When running automated UI smoke, prefer the repo script `./script/run_ui_smoke.sh`, which uses isolated temporary app-support and export directories instead of your live data.

## If something looks wrong

1. Quit Chronicle.
2. Backup current broken state folder.
3. Restore your previous backup.
4. Relaunch Chronicle.
5. Export diagnostics package and attach it when reporting an issue.

## Release artifact safety

- Chronicle release artifacts are distributed through GitHub Releases.
- Development builds may ship as unsigned or notarization-free DMGs for internal testing.
- Public beta builds should include a checksum, and signed builds should also be notarized and stapled before distribution.

## Data removal

- In-app path: Preferences -> Privacy -> Wipe Data
- This removes local Chronicle database files.
- Operation is irreversible. Always backup first if unsure.
