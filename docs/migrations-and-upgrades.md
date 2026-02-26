# Chronicle DB Migrations and Upgrade Policy

This document defines how Chronicle changes schema safely across versions.

## Principles

- Prefer additive changes first (new columns/tables, nullable fields).
- Keep migrations idempotent and guarded by runtime schema checks.
- Avoid destructive migrations in normal upgrades.
- Make old data readable before making new writes rely on new schema.

## Current storage

- Primary database: `~/Library/Application Support/Chronicle/activity.sqlite`
- SQLite WAL files may also exist:
  - `activity.sqlite-wal`
  - `activity.sqlite-shm`

## Migration workflow

1. Add migration code in `DatabaseService` with explicit guard checks.
2. Ensure migration can run safely on:
   - fresh install
   - already migrated DB
   - partially migrated state after interrupted run
3. Run local validation:
   - app launch with existing DB
   - `xcodebuild ... test`
   - health checks in Debug panel
4. Ship migration with release notes that include:
   - schema impact
   - user-visible behavior changes
   - rollback notes

## Compatibility rules

- New app versions must open previous stable DB layouts.
- If a fallback path is needed, keep compatibility branches until at least one stable cycle.
- Queries should tolerate missing optional columns when practical.

## Rollback strategy

Chronicle does not auto-downgrade schema in place. If rollback is required:

1. Quit Chronicle.
2. Restore a backup copy of `activity.sqlite` (+ `-wal`/`-shm` when present).
3. Launch the older app build.

If no backup exists, rollback may lose newly written data.

## Release checklist (schema changes)

- [ ] Migration is guarded by schema introspection.
- [ ] Migration is idempotent.
- [ ] Launch succeeds with production-like historical DB.
- [ ] Existing reports and CSV exports still work.
- [ ] Health checks show no new critical issue.
- [ ] Release notes include migration and rollback notes.
