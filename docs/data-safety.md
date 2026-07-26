# Chronicle Data Safety Guide

This guide explains where your data lives, how to back it up, and how to validate upgrades safely.

## Where data is stored

- Current unsandboxed app data folder: `~/Library/Application Support/Chronicle`
- v1.0.5 sandbox-era app data folder: `~/Library/Containers/com.Chronicle.Chronicle/Data/Library/Application Support/Chronicle`
- v1.0.5 sandbox-era preferences: `~/Library/Containers/com.Chronicle.Chronicle/Data/Library/Preferences/com.Chronicle.Chronicle.plist`
- Current unsandboxed preferences: `~/Library/Preferences/com.Chronicle.Chronicle.plist`
- Current main DB file: SQLCipher-encrypted `activity.sqlite`; the v1.0.5 sandbox-era database is the plaintext migration source
- SQLite side files (normal): encrypted database pages in `activity.sqlite-wal` and coordination metadata in `activity.sqlite-shm`
- Encryption key: a random 256-bit Keychain item marked `AfterFirstUnlockThisDeviceOnly`; it is not synchronized to other devices
- Chronicle is offline-first and does not sync your database to cloud services.
- Chronicle has no remote telemetry transport. Optional local usage counters leave the app only when you explicitly export a JSON snapshot.
- The active foreground session is checkpointed every 30 seconds and flushed on normal quit. A forced process or system termination can omit only the uncheckpointed tail, rather than the full active session.

## What may contain sensitive context

- App names and bundle IDs
- Window titles for applications explicitly placed on the allowlist (if enabled)
- Markers and marker spans entered by you
- Work blocks, immutable review snapshots, review notes, and checkpoints
- Export-history destination paths and failure details
- Diagnostics package snapshots (settings and runtime metadata)
- Markdown, CSV, diagnostics, and telemetry exports are plaintext ordinary files outside Chronicle and may be synced by the folder or app you choose. Diagnostics contain health/configuration metadata but omit app names, bundle IDs, window titles, notes, and work-block titles.

## Backup recommendations

Quit every Chronicle version before copying data. For a v1.0.5 → current-version upgrade, make one dated backup set containing every item below that exists:

1. The complete current folder: `~/Library/Application Support/Chronicle`
2. The complete v1.0.5 sandbox folder: `~/Library/Containers/com.Chronicle.Chronicle/Data/Library/Application Support/Chronicle`
3. The v1.0.5 sandbox preferences file: `~/Library/Containers/com.Chronicle.Chronicle/Data/Library/Preferences/com.Chronicle.Chronicle.plist`
4. The current preferences file: `~/Library/Preferences/com.Chronicle.Chronicle.plist`

Use Finder or another metadata-preserving copy tool and retain the directory structure. Copy whole directories; an `activity.sqlite` file without its matching side files and migration metadata is not a complete safety backup. Keep the untouched backup until the candidate has passed launch, relaunch, historical-data, bookmark, last-run, and export checks.

These copies do not contain the Keychain key. An encrypted current-version backup can be restored only for the same macOS user on the same Mac while Chronicle's matching Keychain item remains present. Copying only Application Support to another Mac, or restoring after the device-only key is lost, will leave the encrypted database unreadable. Chronicle currently has no portable encrypted-archive export/import path. For cross-device access, export the reviewed content you need as Markdown or CSV and protect those plaintext files separately; those exports cannot be imported as a full Chronicle archive.

## Legacy plaintext migration

On first launch with a recognized plaintext SQLite database, Chronicle:

1. Checkpoints committed WAL contents and takes an exclusive migration lock.
2. Creates unique temporary and backup files with owner-only (`0600`) permissions.
3. Uses `sqlcipher_export` to build a separately encrypted database.
4. Runs SQLCipher and SQLite integrity checks and confirms the replacement no longer has a plaintext header.
5. Atomically installs the verified encrypted database and immediately removes the temporary plaintext backup before normal schema initialization continues.

If conversion fails before the verified replacement is installed, Chronicle leaves a recoverable source or backup and fails closed. After installation, the encrypted replacement itself is the recoverable source. A corrupt, unknown, or wrongly keyed file is not silently treated as plaintext and is not replaced with an empty database.

The sandbox-to-unsandboxed move also fails closed if a canonical destination side file already exists before installation: `activity.sqlite-wal`, `activity.sqlite-shm`, or `activity.sqlite-journal`. Chronicle does not assume such a file is stale and does not delete or overwrite it. The source, destination, side files, and any authenticated cross-directory migration receipt are preserved for recovery.

## Validate an upgrade (quick path)

1. Confirm app launches normally.
2. Open Pending Review, Timeline, Notes, Insights, and Export & Integrations; verify historical work blocks and review snapshots appear.
3. Complete a disposable review range and confirm the immutable snapshot is available without exporting.
4. Export one reviewed Markdown snapshot and one CSV file; confirm the Markdown attempt appears in export history.
5. Confirm applications outside the window-title allowlist have app-level evidence only. If the privacy mode is not `Raw`, confirm ad-hoc activity exports do not contain raw titles; separately inspect reviewed Markdown because it intentionally preserves the exact title text confirmed in the immutable snapshot.
6. Run Health Check from Debug panel (if available).

## Deleting reviewed raw evidence

After a review is complete, Export & Integrations can permanently remove RawEvents and Activity evidence inside that reviewed time range. The immutable review snapshot, its titles, tags, boundaries, notes, and any ordinary exported files remain available.

If one Activity crosses both the deleted range and an adjacent retained range, Chronicle keeps the outside segment and records a small structural lineage edge (opaque source/child IDs plus the split timestamp). That edge contains no app name or window-title text; it exists only so raw evidence belonging to an adjacent, non-deleted snapshot can still be expanded. Deleting the middle review does not rewrite frozen snapshot JSON or erase evidence outside the selected half-open range.

## Validate on a safe copy

Before testing a beta build or release candidate against real data:

1. Quit every Chronicle version.
2. Create the complete backup set described above, including both the current and v1.0.5 sandbox locations and the legacy preferences file when present.
3. Keep the original backup untouched until the candidate passes launch, relaunch, data, bookmark, last-run, and export checks.
4. When running automated UI smoke, prefer the repo script `./script/run_ui_smoke.sh`, which uses isolated temporary app-support and export directories instead of your live data.

## If something looks wrong

1. Quit every Chronicle version, including any menu-bar instance, and confirm no Chronicle process is still running.
2. Preserve the complete current state before attempting recovery: copy both the current and v1.0.5 sandbox Application Support directories plus the legacy and current preferences files when present.
3. Do not separately delete, move, rename, or splice `activity.sqlite`, its canonical `-wal`, `-shm`, or `-journal` side files, a cross-directory migration receipt, or migration marker data. A side file may contain committed work, and a receipt/marker pair establishes which files belong to one verified migration.
4. On the same user account and Mac, restore one complete, known-good backup set to its original paths. For a current encrypted backup, retain the matching Chronicle Keychain item. For a v1.0.5 rollback, restore the complete pre-upgrade sandbox folder and legacy preferences together and launch v1.0.5; never give v1.0.5 the current SQLCipher archive.
5. If you cannot identify a complete known-good set, keep both the old and new sets unchanged for manual forensic recovery instead of experimenting with individual files. Report the startup error and provide an exported diagnostics package if the app can create one without modifying the archive.

## Release artifact safety

- Chronicle release artifacts are distributed through GitHub Releases.
- Development builds may ship as unsigned or notarization-free DMGs for internal testing.
- Public beta builds should include a checksum, and signed builds should also be notarized and stapled before distribution.

## Data removal

- In-app path: Preferences -> Privacy -> Wipe Data
- This removes current and known legacy Chronicle database files, sidecars, migration remnants, the matching Keychain database key, Chronicle's persisted local settings (including folder bookmarks and local usage counters), and support packages stored in Chronicle's current or legacy Application Support folder. The key is removed only after the database and other app-owned local files have been removed.
- If a filesystem or Keychain step fails, Chronicle keeps ordinary archive access disabled in that process but leaves the wipe action available for a safe retry.
- This does not remove or retract ordinary files previously exported outside Chronicle, support packages moved elsewhere, macOS-managed permissions, or Chronicle's Login Item registration.
- Operation is irreversible. Always backup first if unsure.
