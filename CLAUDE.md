# Chronicle Repository Guide

Chronicle is a fully offline native macOS automatic work log. It converts local Activity Evidence into editable Work Blocks, then freezes user-confirmed ranges as immutable Review Snapshots. The encrypted Chronicle archive is authoritative; Markdown and CSV exports are optional, one way, and plaintext outside the archive.

## Sources of truth

Read these before changing product behavior:

- [docs/product-constitution.md](docs/product-constitution.md) — binding product scope and five-page information architecture.
- [CONTEXT.md](CONTEXT.md) — canonical domain language.
- [docs/adr/0001-separate-evidence-work-blocks-and-review-snapshots.md](docs/adr/0001-separate-evidence-work-blocks-and-review-snapshots.md) — evidence/review model.
- [docs/adr/0002-local-archive-with-one-way-managed-markdown-export.md](docs/adr/0002-local-archive-with-one-way-managed-markdown-export.md) — archive and export ownership.
- [UI-design.md](UI-design.md) — implemented UI architecture.
- [docs/data-safety.md](docs/data-safety.md) and [docs/migrations-and-upgrades.md](docs/migrations-and-upgrades.md) — backup, migration, and rollback contracts.

The original PRD and old release notes are historical. If they conflict with the constitution, ADRs, or current code, use the current sources above.

## Development commands

Build and launch:

```sh
./script/build_and_run.sh
```

Run isolated unit tests through the repository wrapper:

```sh
./script/run_unit_tests.sh
```

Run UI automation separately on a prepared macOS UI runner:

```sh
./script/run_ui_smoke.sh all
./script/run_ui_smoke.sh full
```

Run release checks and rehearsals:

```sh
./script/run_release_preflight.sh
./script/test_release_guards.sh
./script/run_previous_release_upgrade_drill.sh
./script/run_release_dry_run.sh
```

The unit and UI wrappers enforce isolated Application Support and preferences state and retain result bundles. Do not replace them with an ad-hoc `xcodebuild test` command when recording release evidence.

## Architecture map

- `Chronicle/App` — lifecycle, menu-bar controller, scene configuration, window routing, activation policy, and runtime storage/defaults migration.
- `Chronicle/Models` — evidence, review, export, history, and presentation models.
- `Chronicle/Services/Database` — SQLCipher keying, fail-closed archive opening, schema and cross-directory migrations, and domain persistence.
- `Chronicle/Services/Tracking` — foreground-app, idle, and explicitly allowlisted window-title evidence.
- `Chronicle/Services/Reports` — Markdown/CSV generation, managed blocks, coordinated writes, and export settings.
- `Chronicle/Views` — menu-bar controller, Pending Review, Timeline, Notes, Insights, Export & Integrations, Settings, onboarding, and recovery UI.
- `Chronicle/DesignSystem` — shared visual and interaction primitives.
- `ChronicleTests` and `ChronicleUITests` — unit, migration, privacy, export, and bilingual runtime UI coverage.
- `script` and `scripts` — verification, release policy, upgrade drill, and packaging entrypoints.

The main window destinations are Pending Review, Timeline, Notes, Insights, and Export & Integrations. The menu-bar popover stays a light controller. Settings contains General, Privacy, Tags, and Support. `DashboardView` and some legacy filenames remain implementation names, not the current product taxonomy.

## Non-negotiable implementation rules

- Keep the product single-user, local-only, and free of remote telemetry, account sync, team monitoring, and productivity scoring.
- Read window titles only for applications on the explicit allowlist. Accessibility permission is contextual to that feature.
- Keep Activity Evidence distinct from Work Blocks. Automatic grouping must remain transparent and correctable.
- Completing a review must not require a note, tag, or export. Completed snapshots are immutable; changes require explicit revision/re-review.
- Keep reviewed Markdown and template-report namespaces separate. Modify only Chronicle-managed blocks and preserve surrounding user text.
- Treat exported Markdown, CSV, diagnostics, and local-counter snapshots as plaintext ordinary files.
- Open and migrate the archive fail closed. Unknown, corrupt, wrongly keyed, or ambiguous primary/sidecar states must never be replaced with an empty database.
- During sandbox-to-unsandboxed migration, preserve the source, destination, canonical `-wal`/`-shm`/`-journal` side files, and receipt when ownership cannot be proven. Never repair a user archive by splicing individual files.
- Keep test preferences and storage isolated from production domains. Release evidence must come from the repository wrappers and their validated result bundles.
- Do not claim published-binary upgrade coverage from the exact-tag Release-source safety drill; the actual published v1.0.5 → candidate path remains a clean-account gate.

## Release boundary

GitHub Releases is the public artifact source of truth. A dry-run DMG is not a public release. Stable publication requires the full bilingual UI gate, a selected reviewed source license, Developer ID signing, notarization, stapling, and public asset verification. Do not invent a license or mark release notes final without maintainer authorization and completed evidence.
