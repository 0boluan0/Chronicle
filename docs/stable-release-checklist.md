# Stable Release Checklist (Data-Preserving, One-Way Storage Upgrade)

This checklist is for preparing a stable Chronicle release with low upgrade risk. The current source line is `v1.1.x`.

## 1. Preflight

- Confirm the target release tag is frozen and resolves to the intended commit; the release workflow checks out `refs/tags/<tag>` explicitly and rejects any HEAD mismatch.
- Confirm the repository ruleset requires signed, immutable `v*` release tags and permits creation only by the release role (no update/deletion/admin bypass). The workflows verify exact commit resolution and ancestry, but GitHub's signed-tag/ruleset policy is the external trust boundary; CI cannot safely bootstrap or waive the release signing key.
- If manually dispatching the release workflow, start it from `main` and provide the exact existing release tag; other dispatch refs fail before any self-hosted job can start.
- Confirm `README.md`, `SECURITY.md`, the Xcode project, and `docs/releases/<tag>.md` agree on app version and build number.
- Confirm a reviewed `LICENSE` or `COPYING` exists as an exact, non-symlink, non-empty regular file. Names such as `LICENSE.md` do not satisfy the public-release gate; public source visibility alone is not an open-source license.
- Change `docs/releases/<tag>.md` to contain exactly one `Status: Final` line. Dry-runs warn while it is not final; the public release workflow fails closed.
- Confirm an online self-hosted macOS runner has the `chronicle-ui` label, Automation Mode enabled without authentication, and automatic runner updates enabled. It must be on Actions Runner `2.327.1` or newer for the pinned Node 24 actions and must remain within GitHub's rolling 30-day support window.
- Set the `CHRONICLE_UI_SMOKE_ENABLED=1` repository variable only after that runner is online.
- Configure the GitHub Environment named exactly `chronicle-release` before enabling the staging workflow. Require an independent reviewer, restrict deployments to the protected release-tag pattern, and do not allow administrators or automation actors to bypass that approval casually. The credential-bearing build and read-only candidate-staging jobs enter this environment, but repository settings remain the trust boundary: a workflow file cannot enforce its own reviewers or ref policy.
- Configure a second protected environment named exactly `chronicle-release-publish` for the manual publication workflow. Give it independent approval, restrict it to `main`, and provide only `RELEASE_PUBLISH_TOKEN`, `CLEAN_ACCOUNT_ATTESTATION_PAYLOAD_BASE64`, and `CLEAN_ACCOUNT_ATTESTATION_SIGNATURE_BASE64`. Its first job validates the candidate without the write token; only the isolated mutation step in the dependent job references that token. The publication workflow's fixed repository-scoped concurrency group must have cancellation disabled. From its authenticated pre-create inventory scan through final verification, maintainers and external automation must not create a same-tag Release or edit the workflow-created Draft manually or through the API. The staging workflow must never read these secrets or create a GitHub Release.
- Put the Apple distribution credentials below in **environment-scoped secrets on `chronicle-release`**, not ordinary repository secrets:
  - `CODESIGN_IDENTITY`, `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`
  - `APPLE_API_KEY_BASE64`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_TEAM_ID`
  - `APPLE_TEAM_ID` is the exact 10-character TeamIdentifier expected in the signed app; the workflow fails before release work if it is absent and the inspector fails if the signature differs.
- Do not configure a staging release token. GitHub Contents/Release write authority that can create a Draft and upload its assets can also publish it; there is no enforceable standard-token permission split between those operations. Staging therefore writes only an immutable Actions artifact, while `RELEASE_PUBLISH_TOKEN` is the sole remote release credential.
- Restrict the self-hosted release runner through a dedicated runner group to this repository and reviewed workflows. Treat access to that machine and runner group as release authority, because a modified workflow can otherwise execute before artifact publication checks.
- Run the lightweight local preflight before heavier test or packaging work:
  - `./script/run_release_preflight.sh`
  - This checks release metadata, community/privacy files, the runtime network surface, script syntax, workflow YAML, localized string syntax, localized key uniqueness, English/Simplified Chinese key parity, shared schemes, UI smoke manifest references, and whitespace.
  - Run `./script/test_release_guards.sh` for the offline fixture suite covering nested Mach-O enforcement, TeamIdentifier pinning, canonical candidate/provenance binding, signed clean-account evidence, token isolation, and mutation-bypass cases. CI and the formal release workflow run it as well.
- Run the hosted-runner-compatible unsigned release rehearsal before using distribution credentials:
  - `./script/run_release_dry_run.sh`
  - It runs preflight, unit tests, and the shared universal Release Analyze wrapper before building a clean unsigned universal DMG and invoking the shared artifact inspector in `rehearsal` mode. Version/build, the reviewed project license and SQLCipher notice in the app and at the DMG root, exact `arm64` + `x86_64` slices on every real Mach-O in the app (including SQLCipher.framework), exact macOS 14.0 deployment metadata on the main executable and Info.plist, compatible parseable minOS values no newer than 14.0 on nested Mach-O slices, image integrity, and checksum remain mandatory; Developer ID, TeamIdentifier, stapling, and Gatekeeper acceptance are allowed to be absent. Nothing is uploaded.
  - Its schema-3 manifest binds the exact source fingerprint/commit/dirty state, release tag, app version/build, portable unit summary, Release Analyze receipt/log, DMG, and checksum. The script re-verifies those expected source and release values before and after installing exactly six files under `build/dry-run-upload/`. The hosted workflow uploads those six files, exposes only their immutable artifact ID, and a dependent job downloads by that ID; the pinned `download-artifact` v8 action fails on the service-side archive digest mismatch by default before the independent exact-file verification runs.
  - For an already verified offline SwiftPM checkout, set `RELEASE_CLONED_SOURCE_PACKAGES_DIR=/absolute/path/to/SourcePackages`; automatic package resolution is then disabled.
- Ensure Debug unit tests pass on `main` and release branch (if used):
  - `./script/run_unit_tests.sh`
- Ensure UI smoke passes on a dedicated macOS UI runner:
  - `./script/run_ui_smoke.sh all` for the bilingual public beta path.
- `./script/run_ui_smoke.sh full` before promoting an RC. It runs the public path plus every non-Debug release UI test independently in English and Simplified Chinese, including all five main destinations, menu-bar controller, setup/classification surfaces, privacy/support settings, onboarding, legacy-route redirects, and the system-folder sheet.
  - Set `UI_SMOKE_TIMEOUT_SECONDS=<seconds>` if the dedicated runner is expected to take longer than the default 30-minute per-run watchdog.
  - Set `UI_SMOKE_CLONED_SOURCE_PACKAGES_DIR=/absolute/path/to/SourcePackages` to pin a verified cache and disable automatic package resolution.
- For a remote release dry run, dispatch the CI workflow from `main` with `run_ui_smoke=true` and `ui_smoke_scope=full`. The persistent self-hosted runner job is unavailable from other refs.
- Confirm the UI runner machine reports Automation Mode is enabled and can run without per-run authentication; `./script/run_ui_smoke.sh` should fail fast with setup instructions if this is not true.
- Verify no unplanned schema migration is included.

## 2. Database Safety

- [x] Validate migrations with a representative, non-sensitive snapshot created by a Release-configuration safety build from the exact `v1.0.5` tag (`./script/run_previous_release_upgrade_drill.sh`, passed 2026-07-23).
- [x] Run the previous-public-version Release-source safety drill: exact-`v1.0.5`-tag Release-source safety-build schema to current Debug SQLCipher/schema migration and work-block projection (`./script/run_previous_release_upgrade_drill.sh`, passed 2026-07-23).
- [x] Restore the untouched pre-upgrade plaintext backup and verify it by relaunching that exact-tag source safety build (`./script/run_previous_release_upgrade_drill.sh`, passed 2026-07-23).
- Confirm app handles migration failure with clear user-facing error.

The safety drill deliberately builds the exact previous-tag source in Release configuration with App Sandbox disabled plus unique bundle/product identities, then uses a unique `CFFIXED_USER_HOME`, `CHRONICLE_UI_TEST_APP_SUPPORT_DIR`, and the Debug-only isolated archive key. It validates the previous-release production schema, in-place plaintext-to-SQLCipher conversion, data preservation, current schema migrations, projection, and old-build rollback readability without touching a live Chronicle archive or Keychain. It is an exact-tag Release-source safety build, not the published v1.0.5 executable, and does not cover the production sandbox-to-unsandboxed location/preferences move; cross-directory lock, cleanup-retry, and fail-closed behavior remain covered independently by `SQLCipherDatabaseTests`.

### Clean-account upgrade gate

- [ ] On a disposable clean macOS user account, install and launch the actual published `v1.0.5` DMG.
- [ ] In `v1.0.5`, create representative activity, marker, tag/rule, and app-mapping data; choose export destinations so security-scoped bookmarks exist; run the available daily/weekly/CSV exports so last-run state is populated; then quit every Chronicle process.
- [ ] Before installing the candidate, make an untouched rollback backup containing the complete v1.0.5 sandbox Application Support directory and sandbox preferences plist. Keep it until the gate and rollback check are complete.
- [ ] Install the signed/notarized candidate over `v1.0.5` on that same account. Verify the historical data, export-folder bookmarks, and last-run/export status survive both the first launch and a relaunch.
- [ ] In the candidate, complete a disposable review, then write a fresh reviewed Markdown export and CSV export to the restored destinations, inspect their contents, and confirm the reviewed Markdown attempt appears in export history.
- [ ] Revoke or deny optional Accessibility and export-folder access in turn. Confirm app-level capture remains usable, protected operations fail closed with actionable recovery, and granting access again restores only the intended capability.
- [ ] Quit the candidate, preserve its current state separately, restore the complete untouched pre-upgrade backup as one set, and confirm the actual published `v1.0.5` app can read its rollback data. Never point `v1.0.5` at the candidate's SQLCipher archive.
- [ ] After all rollback evidence is preserved, exercise the documented local-data removal and uninstall path on the disposable account. Confirm Chronicle processes and managed local state are removed while previously exported ordinary files remain under user control.
- [ ] On the isolated machine, create the canonical schema-3 `chronicle_clean_account_release_gate` payload with `upgrade`, `relaunch`, `preferences`, `bookmark`, `export`, `rollback`, `permission`, and `uninstall` exactly `true`. Bind repository, a maximum-24-hour issue/expiry window, the published `v1.0.5` release and DMG IDs/bytes, and the candidate tag/source, unique Actions artifact ID/name/archive SHA-256, run ID/run attempt, canonical-manifest SHA-256, and exact DMG size/SHA-256. Use the artifact-ID-and-manifest nonce documented in `docs/release-keys/README.md`. Sign the exact payload bytes with the independent Ed25519 private key and store payload/signature separately as the two protected environment secrets; never manufacture production evidence or private keys in CI.

The Release-source drill is complementary evidence and cannot close this clean-account published-binary gate.

## 3. Export Compatibility

- Verify daily/weekly Markdown export on upgraded data.
- Export reviewed Markdown and a template-based daily report for the same date; confirm they remain isolated as `YYYY-MM-DD.md` and `YYYY-MM-DD-report.md`, with user text outside either managed block unchanged.
- Verify CSV export with default and custom columns.
- Validate timezone boundaries on day/week range exports.
- Confirm export folder bookmark recovery works after relaunch.
- Confirm Export & Integrations restores folder bookmarks and displays the current last-export status after relaunch.

## 4. Privacy and Telemetry

- Confirm window-title privacy policy is consistently applied:
  - storage
  - exports
  - diagnostics
- Confirm no remote telemetry or analytics transport exists.
- Confirm optional local counters remain opt-in, disabled by default, and leave Chronicle only through an explicit user export.
- Verify diagnostics and feedback bundle generation still works locally.

## 5. Release Artifacts

- Build DMG from clean source state. Confirm the reviewed project `LICENSE` and SQLCipher notice are each present both inside `Chronicle.app/Contents/Resources` and at the DMG root, and exactly match their reviewed source files.
- Confirm the formal workflow passes `CODE_SIGNING_ALLOWED=NO` to Xcode, then applies and verifies the Developer ID signature explicitly before notarization.
- Confirm `EXPECTED_TEAM_IDENTIFIER=<APPLE_TEAM_ID> script/inspect_release_artifact.sh <dmg> release` passes before any GitHub Release asset upload. It verifies the reviewed project license and third-party notices inside Chronicle.app and at the DMG root, enumerates every real Mach-O in Chronicle.app including SQLCipher.framework, and requires exact `arm64` + `x86_64` slices, exact macOS 14.0 on the main executable and Info.plist, a parseable macOS platform minimum no newer than 14.0 on every nested slice, the expected bundle version/build, the exact pinned TeamIdentifier, a valid Developer ID signature with hardened runtime and secure timestamp, a valid stapled DMG ticket, and Gatekeeper acceptance.
- Confirm the packaging script verifies the generated DMG image before checksum generation.
- For an unsigned local RC rehearsal, build with the release tag as the artifact version:
  - `TAG=<tag>; env -u CODESIGN_IDENTITY DMG_VERSION="$TAG" CODE_SIGNING_ALLOWED=NO REQUIRE_SIGNING=0 REQUIRE_NOTARIZATION=0 scripts/build_dmg.sh`
- Use the release workflow, not the unsigned local command, for any public RC or stable artifact.
- Verify checksum:
  - `TAG=<tag>; cd dist && shasum -a 256 -c "Chronicle-${TAG}.dmg.sha256"`
- Confirm the release workflow re-checks the exact `Chronicle-<tag>.dmg` checksum before transferring the private build artifact and before uploading the canonical candidate Actions artifact.
- Confirm the release workflow stops when signing or notarization secrets are unavailable.
- Confirm every workflow/job `GITHUB_TOKEN` remains read-only. Staging has no GitHub Release credential or remote mutation. `RELEASE_PUBLISH_TOKEN` appears exactly once, on the isolated inline mutation step. Staging serializes by exact tag; publication uses one fixed repository-scoped group so publication runs for different tags cannot overlap, and queued runs are never cancelled in progress.
- Confirm build and candidate-staging jobs target protected `chronicle-release`. Confirm both manual validation and mutation jobs target the separately protected `chronicle-release-publish` environment, and that validation never receives the release-write token.
- Confirm prerelease tags such as `v1.1.0-rc1` are created with `prerelease=true` and cannot replace the latest stable release; stable tags are created with `prerelease=false` and must pass the final exact `latest` check. Candidate metadata still binds the expected channel (`make_latest=false` for prereleases and `true` for stable releases), but the publication request itself changes only Draft state.
- Verify Developer ID signing, notarization, stapling, and checksum generation.
- Publish checksums and file sizes in release notes.
- Confirm `release.yml` performs no GitHub Release mutation and uploads `chronicle-release-candidate-<tag>-<run-attempt>` with exactly five regular files: the signed/notarized DMG, exact checksum, final notes, canonical metadata, and canonical manifest. The manifest must bind repository, source commit, artifact name, all six staging provenance fields (repository, run ID, run attempt, head SHA, workflow ref, workflow SHA), and every payload file's exact basename, byte size, and SHA-256.
- After the real clean-account exercise, dispatch `publish-release.yml` from protected `main` with the exact tag, successful staging run ID, and run attempt. Validation must use helper code checked out independently at `github.workflow_sha`, resolve exactly one unexpired candidate from that run's artifacts API, validate its ID, archive SHA-256, workflow-run ID/head SHA, and attempt-bound name, then download by artifact ID. It must cross-check the run API and full manifest provenance, download and bind the actual published `v1.0.5` DMG, and verify canonical signed schema-3 evidence, its artifact-ID nonce, and freshness before producing a one-run publish-ready artifact plus scalar identity outputs.
- Confirm the dependent mutation job has no checkout, `gh`, candidate script execution, or write token outside its single inline system-Ruby step. That step must re-validate the exact five files and all scalar/provenance/artifact-ID bindings, refuse an existing release instead of editing it, create a new Draft with its final prerelease state, and upload only the DMG/checksum through the returned release-ID endpoint. It must require the exact non-empty GitHub SHA-256 digest for each upload and every later asset read, download each uploaded asset again by immutable asset ID, and match its bytes to the validated local artifact. Before publishing, it must compare two complete exact-release-ID Draft snapshots covering release ID, tag, target, name, body, draft/prerelease state, release update timestamp, exact asset IDs, asset update timestamps, sizes, states, API digests, and downloaded-byte digests. After the tag re-check and second snapshot, the sole publication request may change only `draft` to `false`; the documented default for a newly published stable release supplies latest status, while prereleases cannot become latest. An exact final GET, remote-byte checks, tag check, and stable `latest` check must all pass.
- GitHub's documented Release update API provides no server-enforced strong precondition for that publication request. Safety therefore depends on the protected environment, fixed repository-scoped Actions concurrency, and the no-manual-or-external-create/edit rule from the inventory scan through final verification. The two snapshots detect observed drift but cannot make the remote update server-conditional.
- If a run fails after Draft creation but before publication is attempted, inspect that Draft and remove it deliberately before retrying. If the publication request returned an uncertain result, the workflow may perform only read-only exact-release, asset-byte, tag, and `latest` checks: it succeeds only if those checks confirm the exact intended public state; otherwise it fails and leaves the record untouched for inspection. The workflow never auto-retries, deletes, reuses, or overwrites a release record.
- Do not require the source-tag copy of `docs/releases/<tag>.md` to contain the final signed DMG hash: that hash does not exist until the tagged build has been signed, notarized, and packaged.
- After upload, compare the GitHub Release body's checksum and size, the GitHub Release asset digest, and the published `.sha256` asset. After publication, update the README Download section from those public assets and confirm it matches them.
- Independently verify the published GitHub Release assets and state with GitHub CLI:
  - Non-gate observation: `bash script/check_release_assets.sh <tag> published latest '' '' observe`
  - The legacy ID-bound gate form remains available for manual, read-only evidence checks, but the staging and publication workflows do not use it as authority.
  - Observation and legacy release-record checks are diagnostic only and can never authorize publication; authorization comes from the candidate manifest, trusted validation, signed clean-account evidence, protected environment, and isolated mutation job.
- Confirm GitHub Releases shows the intended tag, DMG, checksum, and notes before changing README download copy. Ignore local `dist/` files as public-release evidence until they are attached to the release.
- Complete the clean-account published-`v1.0.5` → candidate upgrade, relaunch, export, and rollback gate above; a clean install alone is insufficient for this storage transition.

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
