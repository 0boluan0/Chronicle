# Task FEAT-001 — Ship Quick Marker v1 End-to-End Slice

## Objective
Deliver a minimal, end-to-end Quick Marker v1 slice: from quick entry trigger (menu and existing hotkey path) to local marker persistence and timeline visibility, with deterministic tests and no unrelated refactor.

## Scope In
- Wire quick entry trigger flow to marker creation for:
  - Point marker (single timestamp).
  - Interval marker (start/stop pair).
- Persist marker data locally (text, type, start/end timestamps) using existing local storage path (SQLite/repository layer).
- Ensure timeline query/projection includes newly created markers immediately after write.
- Add focused ChronicleTests covering creation, persistence, and timeline projection.
- Keep behavior offline-only and local-only (no network calls, no telemetry).

## Scope Out
- UI redesign or menu bar visual overhaul.
- Rule engine/tagging changes.
- Stats aggregation changes.
- Cross-module refactors not required for marker flow.
- New online dependencies, sync, telemetry, or update checks.
- Database migration unless strictly required; if unavoidable, include compatibility note and rollback-safe approach.

## Required Tests
- Add/update and run focused tests (exact names required):
  - `testQuickMarkerMenuCreatesPointMarkerWithExactTimestamp`
  - `testQuickMarkerHotkeyCreatesPointMarkerWithExactTimestamp`
  - `testQuickMarkerIntervalStartStopCreatesBoundedInterval`
  - `testQuickMarkerPersistsAndReloadsFromRepository`
  - `testTimelineProjectionIncludesNewQuickMarker`
- Run focused marker tests:
  - `xcodebuild -project Chronicle.xcodeproj -scheme Chronicle -destination 'platform=macOS' -only-testing:ChronicleTests test`
- Run full suite regression:
  - `xcodebuild -project Chronicle.xcodeproj -scheme Chronicle -destination 'platform=macOS' test -resultBundlePath build/TestResults/latest.xcresult`

## Acceptance Criteria
- Menu quick entry creates a point marker with user text and correct persisted timestamp.
- Existing hotkey path creates a point marker with equivalent behavior.
- Interval flow supports start then stop, producing one persisted interval marker with deterministic boundaries.
- New markers are visible in timeline data source/projection without app restart.
- All required tests pass, and full test suite passes locally.
- No violation of Offline/Privacy/Local-data invariants.
- Change set is minimal and limited to marker flow + required tests.

## Output Format
- `Summary`: 3-6 lines describing implemented behavior.
- `Files Changed`: list of paths with one-line purpose each.
- `Tests`: each command + pass/fail + key evidence (include xcresult path for full suite).
- `Scope Control`: one line confirming no out-of-scope refactor/dependency changes.
- `Follow-ups`: only if blocking gaps remain.