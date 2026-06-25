# Stable Release Checklist (Public Beta / Non-Breaking Upgrade)

This checklist is for preparing a stable `v0.x` release with low upgrade risk.

## 1. Preflight

- Confirm target release tag and branch are frozen.
- Run the lightweight local preflight before heavier test or packaging work:
  - `./script/run_release_preflight.sh`
  - This checks script syntax, workflow YAML, localized string syntax, localized key uniqueness, English/Simplified Chinese key parity, shared schemes, UI smoke manifest references, and whitespace.
- Ensure Debug unit tests pass on `main` and release branch (if used):
  - `xcodebuild -project Chronicle.xcodeproj -scheme Chronicle -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/chronicle-deriveddata-unit CODE_SIGNING_ALLOWED=NO test`
- Ensure UI smoke passes on a dedicated macOS UI runner:
  - `./script/run_ui_smoke.sh all` for the bilingual public beta path.
  - `./script/run_ui_smoke.sh full` before promoting an RC, including the English surface checks for quick capture, dashboard, reports, the Reports system folder picker sheet, App Health deep links, preferences, and onboarding.
  - Set `UI_SMOKE_TIMEOUT_SECONDS=<seconds>` if the dedicated runner is expected to take longer than the default 30-minute per-run watchdog.
- For a remote release dry run, trigger the CI workflow manually with `run_ui_smoke=true` and `ui_smoke_scope=full`.
- Confirm the UI runner machine reports Automation Mode is enabled and can run without per-run authentication; `./script/run_ui_smoke.sh` should fail fast with setup instructions if this is not true.
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
- Confirm export folder bookmark recovery works after relaunch.
- Confirm export status lines in dashboard and preferences stay in sync.

## 4. Privacy and Telemetry

- Confirm window-title privacy policy is consistently applied:
  - storage
  - exports
  - diagnostics
- Confirm telemetry remains opt-in and disabled by default.
- Verify diagnostics and feedback bundle generation still works locally.

## 5. Release Artifacts

- Build DMG from clean source state.
- Confirm the packaging script verifies the generated DMG image before checksum generation.
- For RC candidates, build with the release tag as the artifact version:
  - `TAG=<tag>; DMG_VERSION="$TAG" CODESIGN_IDENTITY="" scripts/build_dmg.sh`
- Verify checksum:
  - `TAG=<tag>; cd dist && shasum -a 256 -c "Chronicle-${TAG}.dmg.sha256"`
- Confirm the release workflow re-checks DMG checksums before uploading assets.
- If signing secrets are unavailable, verify the workflow publishes a development DMG plus checksum.
- If signing secrets are available, verify signing, notarization, stapling, and checksum generation.
- Publish checksums and file sizes in release notes.
- After upload, compare the GitHub Release asset digest, the published `.sha256` asset, README download copy, and `docs/releases/<tag>.md`; all four must name the same DMG checksum before the release is promoted.
- Verify the uploaded GitHub Release assets with GitHub CLI:
  - `bash script/check_release_assets.sh <tag>`
- Confirm GitHub Releases shows the intended tag, DMG, checksum, and notes before changing README download copy. Ignore local `dist/` files as public-release evidence until they are attached to the release.
- Smoke-test install on a clean macOS user account.

## 6. Rollout and Recovery

- Publish release notes with:
  - user-visible changes
  - migration behavior
  - known issues
- Include the manual update path via GitHub Releases.
- Prepare rollback note with previous stable build link.
- Monitor first 48h feedback and triage:
  - startup failures
  - migration failures
  - export regressions
  - localization regressions
  - onboarding / quick marker breakage
