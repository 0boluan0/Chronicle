# Chronicle DB Migrations and Upgrade Policy

This document defines how Chronicle changes schema safely across versions.

## Principles

- Prefer additive changes first (new columns/tables, nullable fields).
- Keep migrations idempotent and guarded by runtime schema checks.
- Avoid destructive migrations in normal upgrades.
- Make old data readable before making new writes rely on new schema.

## Current storage

- Primary database: SQLCipher-encrypted `~/Library/Application Support/Chronicle/activity.sqlite`
- SQLite side files may also exist:
  - `activity.sqlite-wal`
  - `activity.sqlite-shm`
  - `activity.sqlite-journal`
- SQLCipher encrypts database pages, including pages written to WAL. The SHM file contains coordination metadata.
- Chronicle generates a random 256-bit database key and stores it in Keychain with `AfterFirstUnlockThisDeviceOnly` accessibility. There is no plaintext-key fallback and the key is not synchronized to another device.
- `ActivitySplitAliases` is additive lineage metadata used when deleting a reviewed interval splits an Activity that also contributes to an adjacent retained interval. It stores opaque source/child row IDs and the split timestamp, not app names or window-title text, so surviving snapshot evidence remains resolvable after the original row is removed.

## Plaintext-to-SQLCipher transition

Chronicle recognizes a legacy database only by the exact SQLite plaintext header. Before schema work begins, it checkpoints committed WAL contents, switches away from WAL, and holds an exclusive migration lock. It then:

1. Copies an owner-only (`0600`) recoverable plaintext backup with a unique name.
2. Runs `sqlcipher_export` into a separate temporary database keyed with the Keychain key.
3. Preserves SQLite `user_version` and `application_id`, then runs SQLCipher and logical integrity checks.
4. Confirms that the replacement no longer has a plaintext SQLite header.
5. Atomically renames the verified encrypted file over the source.
6. Removes the plaintext recovery copy immediately after the verified encrypted database is atomically installed, before normal schema migrations and initialization continue.

Conversion failures before installation leave the original database or a recoverable backup intact. After installation, the verified encrypted database is the recoverable source even if a later schema migration fails. Files with an unknown header, corrupt ciphertext, or the wrong key fail closed; Chronicle does not retry them as plaintext and does not silently create an empty replacement.

For the one-time sandbox-to-unsandboxed location move, Chronicle deletes the old plaintext `activity.sqlite` and its sidecars only after the new Application Support SQLCipher database passes integrity verification. If cleanup is interrupted, later launches verify the encrypted destination again before retrying removal; Chronicle never resumes recording into the stale plaintext source once a verified destination exists. A pre-existing canonical destination `-wal`, `-shm`, or `-journal` file is not assumed to be stale: migration fails closed and preserves the source, destination, side files, and receipt for manual recovery.

## Previous-release Release-source safety drill

Run `./script/run_previous_release_upgrade_drill.sh` before promoting a schema/encryption release. For an already resolved package cache, set `UPGRADE_DRILL_CLONED_SOURCE_PACKAGES_DIR=/absolute/path/to/SourcePackages` so candidate dependency resolution stays offline.

The drill performs this bounded sequence using an exact-tag Release-source safety build:

1. Extracts the exact local `v1.0.5` tag, builds that source in Release configuration with App Sandbox disabled and unique bundle/product identities, and launches the safety build under a unique temporary `CFFIXED_USER_HOME` to create the previous release's production schema.
2. Writes non-sensitive representative sentinels across Activities, Markers, MarkerSpans, Tags, Rules, AppMappings, and RawEvents; checkpoints them and freezes an owner-only plaintext rollback backup.
3. Builds and actually launches the current Debug candidate with `CHRONICLE_UI_TEST_APP_SUPPORT_DIR` pointing at a copy of that archive. An independent C inspector links the SQLCipher framework inside the built candidate app and requires a non-plaintext header, SQLCipher `cipher_version`, `integrity_check=ok`, all eleven schema migrations, all eight candidate-only tables, all seven preserved sentinels, and a projected Work Block linked to the legacy Activity.
4. Confirms the untouched rollback backup did not change, restores it into the temporary previous-release home, relaunches the exact-`v1.0.5`-tag Release-source safety build, and verifies that build can read the restored sentinels with its five-migration schema intact.
5. Stops only the exact drill app PIDs with `SIGTERM`, removes the unique temporary home/build/data root, and retains a text log under ignored `build/release-evidence/`.

The drill never uses the production Chronicle bundle/container paths or Keychain. It provides executable coverage of `v1.0.5` schema → in-place SQLCipher/current-schema projection → plaintext-backup rollback from source at the exact tag. It does not run or claim binary identity with the published v1.0.5 executable, and it is not executable coverage of the production sandbox-to-unsandboxed location or preferences move. Cross-directory exclusive locking, verified-destination cleanup retry, artifact cleanup, and fail-closed behavior are covered separately by `SQLCipherDatabaseTests`; the actual published-binary transition remains a clean-account release gate.

## Migration workflow

1. Add a numbered migration in `DatabaseService`; schema migrations run only after SQLCipher has been keyed and validated.
2. Ensure migration can run safely on:
   - fresh install
   - already migrated DB
   - partially migrated state after interrupted run
3. Run local validation:
   - app launch with existing DB
   - `./script/run_unit_tests.sh`
   - health checks in Debug panel
4. Ship migration with release notes that include:
   - schema impact
   - user-visible behavior changes
   - rollback notes

## Compatibility rules

- New app versions must open previous stable DB layouts.
- Compatibility must never bypass database keying or treat unknown data as plaintext.
- Queries should tolerate missing optional columns when practical.
- The encrypted Chronicle archive remains the source of truth. Reviewed work blocks are frozen into immutable snapshots; revisions require an explicit re-review path rather than a silent rebuild.
- Deleting reviewed raw evidence subtracts only the selected half-open time range. Surviving Activity segments and their work-block links remain valid, frozen snapshot JSON is never rewritten, and additive split-lineage metadata preserves provenance for adjacent snapshots.

## Rollback strategy

Chronicle does not auto-downgrade schema or encryption in place. If rollback is required:

1. Quit Chronicle.
2. On the same user account and Mac, restore an encrypted backup copy of `activity.sqlite` (+ `-wal`/`-shm` when present) while retaining the matching Keychain key.
3. Launch the older app build.

An older build without SQLCipher cannot read the current encrypted archive; it requires a separate pre-encryption plaintext backup made before upgrade. An Application Support copy does not include the Keychain key and cannot be moved to another Mac as a portable restore. Chronicle does not yet provide encrypted-archive export/import. If no compatible backup exists, rollback may lose newly written data.

## Release checklist (schema changes)

- [x] Migration is guarded by schema introspection.
- [x] Migration is idempotent.
- [x] SQLCipher is keyed first and `cipher_version` is validated before any schema access.
- [x] Fresh, correct-key reopen, wrong-key fail-closed, plaintext migration, WAL preservation, and corrupt-file behavior are covered by tests.
- [x] Launch succeeds with a copied archive created by the exact-tag `v1.0.5` Release-source safety build and representative production schema.
- [ ] Pending Review, immutable snapshots, Timeline, Notes, Insights, and Export & Integrations still work.
- [x] Reviewed Markdown success/failure attempts persist in encrypted export history; plaintext exports remain clearly outside the archive boundary.
- [ ] Health checks show no new critical issue.
- [x] Release notes include migration and rollback notes.

The remaining unchecked items require the final bilingual runtime UI/clean-account smoke pass; a successful UI test build alone does not close them.
