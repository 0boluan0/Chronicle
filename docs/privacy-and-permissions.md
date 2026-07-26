# Chronicle Privacy & Permissions

Chronicle keeps activity data fully offline. Your activity database stays local on your Mac.

This page explains what Chronicle stores, what permissions it may ask for, and how to remove your data.

## What Chronicle stores (locally)

- App sessions (app name + optional bundle ID)
- Idle sessions (when idle detection is enabled)
- Proposed and reviewed work blocks
- Immutable review snapshots and review checkpoints
- Tags, tag rules, and app mappings
- Markers and marker spans (notes you enter)
- Optional window titles (only if you enable window-title capture)
- Export settings (folder bookmarks, templates, last export status)
- Reviewed Markdown export history, including destination paths, success/failure, file counts, and error details

Data lives under Application Support:

- Folder: `~/Library/Application Support/Chronicle`
- Main DB: SQLCipher-encrypted `activity.sqlite`; database pages in its WAL are encrypted, while the SHM side file contains coordination metadata
- Database key: a random 256-bit Keychain item marked `AfterFirstUnlockThisDeviceOnly`; it is cached only in app memory while Chronicle runs and is not synchronized to another device

The encrypted Chronicle archive is the in-app source of truth. An Application Support backup is readable only for the same user on the same Mac while the matching Keychain item is still present. Copying just `activity.sqlite` or the Application Support folder to another Mac is not a supported restore path, and Chronicle does not yet provide portable encrypted-archive export/import.

## Network behavior

- Chronicle does not sync or upload your database.
- The app can open GitHub release pages when you click "Check for Updates" or "Open Releases Page".
- Those actions hand the URL to your default browser; Chronicle does not fetch release metadata in the background.

## Permissions

## Accessibility

Used for:

- Window-title capture (optional, off by default)

If you do not enable window-title capture, Chronicle should work without Accessibility permission.

## Window titles and privacy modes

App-level evidence does not require Accessibility permission. When window-title capture is enabled, Chronicle reads a title only when the foreground application's bundle ID is on the explicit allowlist. For those applications, you can choose a privacy mode:

- Raw: store the full title text
- Length: store only `length:N`
- Hash: store only `sha256:...`

Applications outside the allowlist remain app-level evidence and never have a window title read or stored. New captures and ad-hoc activity exports follow the selected privacy mode. A completed review is an immutable, user-confirmed snapshot: its title text does not change when the capture mode changes, and reviewed Markdown exports that exact snapshot after an explicit plaintext acknowledgement. Diagnostics contain health/configuration metadata, not app names, bundle IDs, window titles, notes, or work-block titles.

## No remote telemetry

Chronicle has no remote telemetry endpoint or background analytics transport. It can track anonymous usage counters locally (no content, no text).

- Default: disabled
- When enabled: counters are stored in local user defaults
- Export: you can export a local JSON snapshot at any time from Preferences -> Privacy

## Export boundary

Markdown, CSV, diagnostics, and local telemetry snapshots are ordinary plaintext files outside Chronicle. They are written only to a location you select, but Chronicle cannot encrypt, protect, or retract them after export. Review their contents before sharing or syncing them with another app. Structured app names, titles, tags, and marker text are escaped as plain text in generated Markdown; review notes and custom template text remain deliberate user-authored Markdown. Chronicle records reviewed Markdown attempts in the encrypted archive; if the file write completes but the history entry cannot be saved, the app reports that partial success immediately. Managed Markdown uses coordinated writes and optimistic conflict checks, but arbitrary editors may not participate in macOS file coordination, so pause other editors while exporting to the same file.

## Plaintext database upgrades

When Chronicle first encounters an exact legacy SQLite plaintext header, it checkpoints committed WAL data, holds an exclusive migration lock, and exports into a separately encrypted SQLCipher database. The temporary database is integrity-checked before an atomic replacement. A unique owner-only (`0600`) plaintext recovery copy exists only during conversion and is removed immediately after the verified encrypted replacement is installed, before normal schema initialization continues. Unknown, corrupt, or wrongly keyed files fail closed and are never treated as plaintext or silently rebuilt.

## Remove Chronicle-owned local data

In-app path:

- Preferences -> Privacy -> Wipe Data

This deletes current and known legacy Chronicle database files, sidecars, migration remnants, the matching Keychain database key, Chronicle's persisted local settings (including export-folder bookmarks and local usage counters), and support packages in Chronicle's current or legacy Application Support folder. The database key is deleted last. If a step fails, normal archive access remains disabled in that process while the wipe action remains available for a safe retry.

Chronicle does not retract plaintext files you previously exported or support packages you moved elsewhere. macOS-managed permissions and Chronicle's Login Item registration also remain. This action is irreversible.
