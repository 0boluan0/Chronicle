# Stable Release Checklist (Non-Breaking Upgrade)

This checklist is for preparing a stable `v0.x` release with low upgrade risk.

## 1. Preflight

- Confirm target release tag and branch are frozen.
- Ensure CI passes on `main` and release branch (if used).
- Verify no unplanned schema migration is included.

## 2. Database Safety

- Validate migrations with real-world sample DB snapshots.
- Run upgrade test from previous public version to candidate build.
- Run rollback test by restoring DB backup and relaunching previous version.
- Confirm app handles migration failure with clear user-facing error.

## 3. Export Compatibility

- Verify daily/weekly Markdown export on upgraded data.
- Verify CSV export with default and custom columns.
- Validate timezone boundaries on day/week range exports.

## 4. Privacy and Telemetry

- Confirm window-title privacy policy is consistently applied:
  - storage
  - exports
  - diagnostics
- Confirm telemetry remains opt-in and disabled by default.
- Verify diagnostics and feedback bundle generation still works locally.

## 5. Release Artifacts

- Build DMG from clean source state.
- Verify app signing and notarization status.
- Publish checksums and file sizes in release notes.
- Smoke-test install on a clean macOS user account.

## 6. Rollout and Recovery

- Publish release notes with:
  - user-visible changes
  - migration behavior
  - known issues
- Prepare rollback note with previous stable build link.
- Monitor first 48h feedback and triage:
  - startup failures
  - migration failures
  - export regressions

