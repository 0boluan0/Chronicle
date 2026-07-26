<p align="center">
  <img src="Chronicle/Assets.xcassets/AppIcon.appiconset/appicon_128.png" width="96" height="96" alt="Chronicle app icon">
</p>

<h1 align="center">Chronicle</h1>

<p align="center">
  A fully offline macOS automatic work log for reconstructing a day or week without relying on memory.
</p>

<p align="center">
  <a href="https://github.com/0boluan0/Chronicle/releases">
    <img src="https://img.shields.io/github/v/release/0boluan0/Chronicle?display_name=tag&include_prereleases&style=flat-square" alt="Release">
  </a>
  <a href="https://github.com/0boluan0/Chronicle/actions/workflows/ci.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/0boluan0/Chronicle/ci.yml?branch=main&style=flat-square" alt="CI">
  </a>
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&style=flat-square" alt="macOS 14+">
  <img src="https://img.shields.io/badge/storage-local%20SQLCipher-2ea44f?style=flat-square" alt="Encrypted local SQLCipher storage">
</p>

<p align="center">
  <a href="#overview">Overview</a> ·
  <a href="#download">Download</a> ·
  <a href="#privacy-model">Privacy</a> ·
  <a href="#development">Development</a> ·
  <a href="#release-process">Release</a>
</p>

## Overview

Chronicle is a native macOS automatic work log. It turns foreground-app activity and explicitly permitted window-level context into auditable work blocks, then lets one person review a day or week without reconstructing it from memory. The encrypted in-app archive is the source of truth; export to tools such as Obsidian is optional and one way.

Current source version: `1.1.0` (build `8`).

Chronicle is not a cloud analytics platform, employee monitoring tool, screenshot recorder, or keylogger. It does not provide account sync, team dashboards, remote collection, or background upload of your timeline.

### Core Capabilities

| Area | What Chronicle Provides |
| --- | --- |
| Activity evidence | Foreground applications, idle periods, and window titles only for applications on the explicit allowlist. |
| Work blocks | Transparent local grouping plus manual blocks, notes, tags, boundary edits, split, and merge. |
| Review | A Pending Review inbox that creates immutable review snapshots and advances a durable checkpoint. |
| Archive | Timeline, Notes, and descriptive Insights backed by the encrypted local Chronicle archive. |
| Export & integrations | One-way managed Markdown and CSV output, with reviewed Markdown attempts recorded in encrypted export history or surfaced immediately if history recording fails. |
| Localization | English and Simplified Chinese UI strings. |

## Download

Get the current build from [GitHub Releases](https://github.com/0boluan0/Chronicle/releases).

The latest published stable build is [`v1.0.5`](https://github.com/0boluan0/Chronicle/releases/tag/v1.0.5):

- `Chronicle-v1.0.5.dmg`
- `Chronicle-v1.0.5.dmg.sha256`

Install it by opening the DMG and dragging `Chronicle.app` into `/Applications`.
The published DMG is 4,382,132 bytes and its SHA-256 checksum is `5264c7ffafe1f4c069081126ba959c5f4c13c629b45fb8f420c5ecfdf3da5164`.

Historical builds may be unsigned or not notarized. If macOS blocks first launch, use Finder to right-click `Chronicle.app`, choose **Open**, and confirm that you trust the downloaded build. Future public stable releases remain blocked until Developer ID signing and notarization are available.

## Privacy Model

Chronicle is designed around local ownership of activity data.

- Activity data is stored locally under `~/Library/Application Support/Chronicle`.
- The main `activity.sqlite` database and its WAL are encrypted by SQLCipher. Chronicle creates a random 256-bit key in Keychain using the `ThisDeviceOnly` accessibility class; the key is not synchronized to another Mac.
- Chronicle does not sync or upload the database.
- Network access is limited to user-initiated links such as opening the GitHub Releases page.
- Chronicle contains no remote telemetry; optional usage counters stay in local user defaults and are exported only when you explicitly save a JSON snapshot.
- Window-title capture is optional and off by default.
- Window titles are read only for applications you explicitly add to the allowlist. Accessibility permission is needed only when that allowlist-based capture is active.
- Exported Markdown, CSV, diagnostics, and telemetry snapshots are ordinary files outside Chronicle. Their storage and sharing are controlled by you.

An Application Support copy can be reopened only for the same user on the same Mac while its Keychain key remains available. Copying only that folder to another Mac, or restoring it after the device-only key has been lost, does not produce a readable archive. Chronicle does not yet provide portable encrypted-archive export/import; use ordinary Markdown or CSV exports when portability is required, remembering that those files are plaintext.

For allowlisted applications, Chronicle supports privacy modes for title storage:

- `Raw`: store the full title text.
- `Length`: store only `length:N`.
- `Hash`: store only a SHA-256 value.

See [docs/privacy-and-permissions.md](docs/privacy-and-permissions.md) and [docs/data-safety.md](docs/data-safety.md) for data locations, backup guidance, and removal steps.

## Day-To-Day Use

Chronicle runs from the macOS menu bar. The popover is a light controller for quick capture and navigation; review and history live in the main window.

Typical workflow:

1. Let Chronicle collect app-level evidence in the background; optionally allow window titles for selected applications.
2. Add notes or manual work blocks when context matters or work happened away from the Mac.
3. Open Pending Review, correct proposed work-block titles, tags, and boundaries if needed, then complete the review.
4. Revisit immutable review snapshots through Timeline, Notes, and descriptive Insights. Raw activity remains expandable evidence, not a claim about intent or productivity.
5. Optionally export managed Markdown or CSV into notes and analysis tools. Review completion never depends on export.

Reviewed work logs use the canonical daily note `YYYY-MM-DD.md` and update only the
`daily-YYYY-MM-DD` managed block, making that file suitable for one-way Obsidian integration.
The legacy template-based daily report is intentionally separate at `YYYY-MM-DD-report.md`
with a `report-daily-YYYY-MM-DD` managed block, so it cannot overwrite the reviewed projection.
Chronicle coordinates writes with compatible document editors and rejects file types or changes
it can detect. Because arbitrary editors may not participate in macOS file coordination, pause
other editors while Chronicle exports to the same file.

## Development

### Requirements

- macOS 14 or newer
- Xcode with macOS SDK support
- Swift and Xcode command line tools

### Build Locally

Open `Chronicle.xcodeproj` in Xcode, select the `Chronicle` scheme, and run the app.

Shell entrypoint:

```sh
./script/build_and_run.sh
```

### Unit Tests

The default unit-test entrypoint builds the app and unit-test target only. It does not build or run the UI automation target.

```sh
./script/run_unit_tests.sh
```

### UI Smoke Tests

UI smoke tests are intentionally separate from normal unit tests because macOS UI automation requires machine-level setup.

```sh
./script/run_ui_smoke.sh all
```

Each smoke run has a 30-minute watchdog by default. Override it for slower dedicated runners when needed:

```sh
UI_SMOKE_TIMEOUT_SECONDS=2700 ./script/run_ui_smoke.sh full
```

To reuse a previously verified SwiftPM checkout without any automatic package resolution:

```sh
UI_SMOKE_CLONED_SOURCE_PACKAGES_DIR=/absolute/path/to/SourcePackages \
  ./script/run_ui_smoke.sh full
```

Dedicated UI runners may need Automation Mode enabled once by an administrator:

```sh
sudo automationmodetool enable-automationmode-without-authentication
```

The smoke runner uses a unique app-support and export workspace for each test, a test-only database key, and a unique defaults suite, so it does not touch your live Chronicle database or Keychain key. New workspaces are removed during test teardown.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `Chronicle/App` | App startup, window routing, app state, and controllers. |
| `Chronicle/Services` | Tracking, database persistence, reports, tagging, maintenance, and permissions. |
| `Chronicle/Services/Database` | SQLCipher context, encryption migration, schema migrations, and domain persistence behind `DatabaseService`. |
| `Chronicle/Views` | SwiftUI views for the light popover controller, Pending Review, Timeline, Notes, Insights, Export & Integrations, preferences, and onboarding. |
| `ChronicleTests` | Unit tests and fixtures. |
| `ChronicleUITests` | UI smoke coverage. |
| `script` | Local build/run and UI smoke scripts. |
| `scripts` | Release packaging and CSV analysis utilities. |
| `docs` | Release, privacy, migration, update, and safety documentation. |

## CSV Analysis

Chronicle CSV exports include stable technical fields such as `start_time`, `end_time`, `duration`, `app_name`, `is_idle`, and tag fields. The repository includes small offline analysis scripts:

```sh
python3 scripts/csv-analysis/tag_time_report.py --csv /path/to/export.csv
python3 scripts/csv-analysis/switch_transition_report.py --csv /path/to/export.csv
python3 scripts/csv-analysis/focus_block_report.py --csv /path/to/export.csv --min-minutes 25
```

See [scripts/csv-analysis/README.md](scripts/csv-analysis/README.md) for input expectations and examples.

## Release Process

Public releases use two GitHub Actions stages. `release.yml` builds from the exact version tag, requires finalized release notes, a reviewed open-source license, the full UI and bounded-upgrade gates, universal Release Analyze, Developer ID signing, notarization, and checksum validation, then uploads a read-only Actions candidate artifact containing the exact DMG, checksum, notes, metadata, and canonical provenance manifest. It never creates or changes a GitHub Release. The separately dispatched `publish-release.yml` resolves that candidate to its unique, unexpired GitHub artifact ID and archive digest, downloads by ID, validates it with tools checked out at the trusted workflow SHA, and verifies a protected clean-account attestation against both that immutable object and the actual published `v1.0.5` DMG. A second isolated job is the only place that receives release-write authority; it creates a new Draft with the final prerelease state, uploads the exact validated assets, requires GitHub's SHA-256 digest and independently downloaded bytes on every later asset read, compares two complete exact-ID Draft snapshots including release and asset update timestamps, changes only `draft` to publish, and final-verifies the public release and stable latest pointer. An uncertain publication response is never retried or cleaned up automatically; the job uses only read-only exact-ID checks to determine whether the intended release is fully published. Tags with a prerelease suffix such as `-rc1` are published as prereleases and never replace the latest stable release.

Repository maintainers must configure protected GitHub Environments `chronicle-release` and `chronicle-release-publish` with required reviewers and ref restrictions. Apple credentials belong only to `chronicle-release`; staging has no GitHub Release write token. A standard GitHub token cannot be scoped to “create/upload a Draft but never publish it,” so all remote release writes are intentionally consolidated behind the separately reviewed `RELEASE_PUBLISH_TOKEN` in `chronicle-release-publish`. GitHub's documented Release update API does not provide a server-enforced strong precondition for this state change, so publication uses a cooperative single-writer boundary: the protected environment, one repository-scoped Actions concurrency group with cancellation disabled, and a maintainer rule forbidding manual or API creation of a same-tag Release or edits to the workflow-created Draft from the authenticated pre-create inventory scan through final verification. The workflow checks narrow that window but do not turn it into a server-enforced conditional update. That environment also holds `CLEAN_ACCOUNT_ATTESTATION_PAYLOAD_BASE64` and its detached Ed25519 `CLEAN_ACCOUNT_ATTESTATION_SIGNATURE_BASE64`. The independently generated, reviewed public key must exist at `docs/release-keys/clean-account-ed25519-public.pem`; publication fails closed while it is absent, and the production private key is never committed or generated by CI. Require signed, immutable `v*` tags and restrict the self-hosted release runner to trusted workflows. Keep that runner automatically updated and within GitHub's rolling support window; the pinned Node 24 actions require Actions Runner `2.327.1` or newer. These repository settings are part of the release trust boundary and cannot be supplied by workflow YAML itself.

Before credentials or a dedicated UI runner are available, run the same Release/DMG path locally or on a hosted CI runner without signing and without uploading anything:

```sh
./script/run_release_dry_run.sh
```

An already verified SwiftPM checkout can also be pinned for the complete test, universal Release Analyze, and DMG path:

```sh
RELEASE_CLONED_SOURCE_PACKAGES_DIR=/absolute/path/to/SourcePackages \
  ./script/run_release_dry_run.sh
```

Supplying either cache variable disables automatic package resolution for that script invocation.

The authoritative dry-run never permits skipped tests or skipped universal Release Analyze. It emits a portable unit summary, the Analyze receipt/log, exact DMG/checksum evidence, and a schema-3 manifest bound to the expected source commit/fingerprint/dirty state plus release tag and app version/build, then re-verifies an exact six-file payload under `build/dry-run-upload/`. The hosted workflow transfers that payload by immutable artifact ID; its pinned `download-artifact` v8 action fails on the service-side archive digest mismatch by default before a dependent job repeats source-bound exact-file verification. For a deliberately non-gate packaging check only, use `DRY_RUN_MODE=non-authoritative DRY_RUN_SKIP_TESTS=1`; that run records both skips explicitly and cannot emit PASS evidence. Dry-run artifacts remain under `dist/dry-run/` and are not public release assets.

For an informational check of an already visible GitHub Release, verify the public DMG digest against the checksum asset in explicit observation mode:

```sh
bash script/check_release_assets.sh <release-tag> published latest '' '' observe
```

Observation mode is diagnostic only and is not a release gate. The formal staging/publication path instead binds the exact candidate bytes and all six Actions provenance fields in a canonical candidate manifest, then verifies the independently signed clean-account attestation before the isolated mutation job receives the write token. The legacy ID-bound checker remains available for read-only inspection of an already visible release, but it does not authorize publication.

Stable releases require Developer ID signing, Apple notarization, stapling, and the full bilingual UI smoke gate. Local development DMGs may still be built without distribution credentials, but the release workflow will not publish them as a stable artifact.

Treat GitHub Releases as the public download source of truth. Local files under `dist/` may be developer or internal builds; do not update the Download section unless the matching tag, DMG, checksum, and release notes are published on GitHub.

See [docs/stable-release-checklist.md](docs/stable-release-checklist.md), [docs/update-strategy.md](docs/update-strategy.md), and [docs/releases/v1.1.0.md](docs/releases/v1.1.0.md) for the current release checklist and draft validation record.

## Documentation

- [docs/product-constitution.md](docs/product-constitution.md): binding product boundaries and information architecture.
- [CONTEXT.md](CONTEXT.md): current domain language for evidence, work blocks, reviews, and exports.
- [docs/adr/0001-separate-evidence-work-blocks-and-review-snapshots.md](docs/adr/0001-separate-evidence-work-blocks-and-review-snapshots.md): evidence, work-block, and immutable-review decision.
- [docs/adr/0002-local-archive-with-one-way-managed-markdown-export.md](docs/adr/0002-local-archive-with-one-way-managed-markdown-export.md): archive ownership and one-way export decision.
- [UI-design.md](UI-design.md): current UI architecture and navigation map.
- [docs/privacy-and-permissions.md](docs/privacy-and-permissions.md): privacy promise, permission model, and data removal.
- [docs/data-safety.md](docs/data-safety.md): local data location, backup, and upgrade validation.
- [docs/migrations-and-upgrades.md](docs/migrations-and-upgrades.md): migration and rollback policy.
- [docs/update-strategy.md](docs/update-strategy.md): GitHub Releases update flow and Sparkle recommendation.
- [docs/stable-release-checklist.md](docs/stable-release-checklist.md): release readiness and rollback checklist.
- [CONTRIBUTING.md](CONTRIBUTING.md): development workflow and pull-request expectations.
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md): community participation expectations.
- [Chronicle/Resources/ThirdPartyNotices.md](Chronicle/Resources/ThirdPartyNotices.md): SQLCipher Community Edition and SQLite attribution distributed with the app and DMG.
- [Product Requirements Document_ Offline Timeline Activity Tracker (macOS).pdf](Product%20Requirements%20Document_%20Offline%20Timeline%20Activity%20Tracker%20%28macOS%29.pdf): historical original PRD; the constitution and ADRs supersede it where they differ.

## License

Chronicle is licensed under the [MIT License](LICENSE). The root license covers Chronicle's own source; bundled third-party components remain governed by their notices in `Chronicle/Resources/ThirdPartyNotices.md`.

## Project Status

The current source targets Chronicle `1.1.0` and is being hardened for its next public stable release. Unit tests and an unsigned hosted-runner DMG dry-run are repeatable without release credentials; exact-tag UI evidence, Developer ID signing, notarization, clean-account upgrade evidence, and protected remote publication remain publication gates.
