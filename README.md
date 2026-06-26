<p align="center">
  <img src="Chronicle/Assets.xcassets/AppIcon.appiconset/appicon_128.png" width="96" height="96" alt="Chronicle app icon">
</p>

<h1 align="center">Chronicle</h1>

<p align="center">
  A local-first macOS activity timeline for understanding how your work time is spent.
</p>

<p align="center">
  <a href="https://github.com/0boluan0/Chronicle/releases">
    <img src="https://img.shields.io/github/v/release/0boluan0/Chronicle?display_name=tag&include_prereleases&style=flat-square" alt="Release">
  </a>
  <a href="https://github.com/0boluan0/Chronicle/actions/workflows/ci.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/0boluan0/Chronicle/ci.yml?branch=main&style=flat-square" alt="CI">
  </a>
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&style=flat-square" alt="macOS 14+">
  <img src="https://img.shields.io/badge/storage-local%20SQLite-2ea44f?style=flat-square" alt="Local SQLite storage">
</p>

<p align="center">
  <a href="#overview">Overview</a> ·
  <a href="#download">Download</a> ·
  <a href="#privacy-model">Privacy</a> ·
  <a href="#development">Development</a> ·
  <a href="#release-process">Release</a>
</p>

## Overview

Chronicle is a native macOS menu bar app that records foreground app sessions, idle periods, quick notes, and user-defined tags into a local SQLite database. It is built for personal review workflows: reconstruct the day, label work blocks, inspect trends, and export reports without sending activity data to a server.

Chronicle is not a cloud analytics platform, employee monitoring tool, screenshot recorder, or keylogger. It does not provide account sync, team dashboards, remote collection, or background upload of your timeline.

### Core Capabilities

| Area | What Chronicle Provides |
| --- | --- |
| Timeline capture | Foreground app sessions, idle detection, optional window titles, and normalized activity rows. |
| Context capture | Quick markers, marker spans, manual notes, and a global quick-marker hotkey. |
| Tagging | Tag rules, app mappings, manual overrides, and effective tags for stats and export. |
| Review surfaces | Menu bar popover plus Dashboard views for timeline, overview, stats, reports, markers, and settings. |
| Export | Markdown and CSV reports for daily or weekly review workflows. |
| Localization | English and Simplified Chinese UI strings. |

## Download

Get the current build from [GitHub Releases](https://github.com/0boluan0/Chronicle/releases).

The current release candidate is [`v0.1.0-rc2`](https://github.com/0boluan0/Chronicle/releases/tag/v0.1.0-rc2):

- `Chronicle-v0.1.0-rc2.dmg`
- `Chronicle-v0.1.0-rc2.dmg.sha256`

Install it by opening the DMG and dragging `Chronicle.app` into `/Applications`.
The published DMG is 15,683,481 bytes and its SHA-256 checksum is `d8be5843d4f2c67cd8b008d186397cbf5fdafa24d157453b83da4dbedd6d8b21`.

Release-candidate builds may be unsigned or not notarized when distribution credentials are unavailable. If macOS blocks first launch, use Finder to right-click `Chronicle.app`, choose **Open**, and confirm that you trust the downloaded build.

## Privacy Model

Chronicle is designed around local ownership of activity data.

- Activity data is stored locally under `~/Library/Application Support/Chronicle`.
- The main database is `activity.sqlite`, with SQLite WAL/SHM sidecar files as needed.
- Chronicle does not sync or upload the database.
- Network access is limited to user-initiated links such as opening the GitHub Releases page.
- Window-title capture is optional and off by default.
- Accessibility permission is only needed if you enable window-title capture.

When window-title capture is enabled, Chronicle supports privacy modes for title storage:

- `Raw`: store the full title text.
- `Length`: store only `length:N`.
- `Hash`: store only a SHA-256 value.

See [docs/privacy-and-permissions.md](docs/privacy-and-permissions.md) and [docs/data-safety.md](docs/data-safety.md) for data locations, backup guidance, and removal steps.

## Day-To-Day Use

Chronicle runs from the macOS menu bar. The popover is intended for quick checks and quick capture; the Dashboard is intended for deeper review.

Typical workflow:

1. Let Chronicle capture foreground app and idle sessions in the background.
2. Add quick markers when context matters, such as a meeting, decision, interruption, or focus block.
3. Use tag rules and app mappings to turn raw app usage into meaningful categories.
4. Review the timeline and stats at the end of the day or week.
5. Export Markdown or CSV into your notes, reports, or analysis tools.

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
xcodebuild \
  -project Chronicle.xcodeproj \
  -scheme Chronicle \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/chronicle-deriveddata-unit \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -testLanguage en \
  -testRegion US \
  test
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

Dedicated UI runners may need Automation Mode enabled once by an administrator:

```sh
sudo automationmodetool enable-automationmode-without-authentication
```

The smoke runner uses isolated temporary app-support and export folders so it does not touch your live Chronicle database.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `Chronicle/App` | App startup, window routing, app state, and controllers. |
| `Chronicle/Services` | Tracking, database persistence, reports, tagging, maintenance, and permissions. |
| `Chronicle/Services/Database` | SQLite context, schema/migrations, and domain persistence methods behind `DatabaseService`. |
| `Chronicle/Views` | SwiftUI views for popover, dashboard, preferences, reports, onboarding, and quick markers. |
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

Release candidates are built by the GitHub Actions release workflow from a version tag. The workflow runs unit tests, builds a clean DMG, publishes the DMG and checksum to GitHub Releases, and uses release notes from `docs/releases/<tag>.md` when present.

Local RC packaging command:

```sh
TAG=v0.1.0-rc2
DMG_VERSION="$TAG" CODESIGN_IDENTITY="" scripts/build_dmg.sh
cd dist && shasum -a 256 -c "Chronicle-${TAG}.dmg.sha256"
```

After the GitHub Release uploads finish, verify the public DMG asset digest against the published checksum asset:

```sh
bash script/check_release_assets.sh v0.1.0-rc2
```

Signing and notarization are optional in the current workflow. When credentials are not configured, the generated artifact is a development, notarization-free DMG and the release notes should say so explicitly.

Treat GitHub Releases as the public download source of truth. Local files under `dist/` may be developer or internal builds; do not update the Download section unless the matching tag, DMG, checksum, and release notes are published on GitHub.

See [docs/stable-release-checklist.md](docs/stable-release-checklist.md), [docs/update-strategy.md](docs/update-strategy.md), and [docs/releases/v0.1.0-rc2.md](docs/releases/v0.1.0-rc2.md) for the current release checklist and RC validation record.

## Documentation

- [UI-design.md](UI-design.md): UI notes and product architecture.
- [Product Requirements Document_ Offline Timeline Activity Tracker (macOS).pdf](Product%20Requirements%20Document_%20Offline%20Timeline%20Activity%20Tracker%20%28macOS%29.pdf): original PRD.
- [docs/privacy-and-permissions.md](docs/privacy-and-permissions.md): privacy promise, permission model, and data removal.
- [docs/data-safety.md](docs/data-safety.md): local data location, backup, and upgrade validation.
- [docs/migrations-and-upgrades.md](docs/migrations-and-upgrades.md): migration and rollback policy.
- [docs/update-strategy.md](docs/update-strategy.md): GitHub Releases update flow and Sparkle recommendation.
- [docs/stable-release-checklist.md](docs/stable-release-checklist.md): release readiness and rollback checklist.

## Project Status

Chronicle is currently in release-candidate hardening. The main work areas are database reliability, export correctness, onboarding polish, localization coverage, and repeatable CI/release validation on macOS runners.
