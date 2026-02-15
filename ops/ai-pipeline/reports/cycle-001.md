# Cycle 001 Report

## Failure ID
- `FAIL-P0-001`

## Repro Command
```bash
xcodebuild -project Chronicle.xcodeproj -scheme Chronicle -destination 'platform=macOS' test -resultBundlePath build/TestResults/latest.xcresult
```

## Fix Verification
- Completed successfully

## Decision
- `PASS`: Stabilization task STAB-001 completed
- Reason: 3 consecutive full suite runs without crash/restart

## Next Command ID
- `STAB-002`

## Notes
- **Root cause**: Test-time objects were crashing during deallocation via Swift concurrency task-local teardown (`swift::TaskLocal::StopLookupScope::~StopLookupScope`), seen in crash reports with top symbols rotating across `DatabaseService.__deallocating_deinit`, `AggregationService.__deallocating_deinit`, `MarkerSpanService.__deallocating_deinit`, `AppState.__deallocating_deinit`.
- **Fix**: Added `nonisolated deinit {}` to those classes to bypass the crashing actor-isolated deinit path in this test-host scenario.
- **Changed files**:
  - `Chronicle/Services/Database/DatabaseService.swift:92`
  - `Chronicle/Services/AggregationService.swift:76`
  - `Chronicle/Services/MarkerSpanService.swift:19`
  - `Chronicle/App/AppState.swift:207`
- **Stability runs**:
  - `ops/ai-pipeline/stab-001/full-suite-stability-run1.log` - 0 crashes, 0 restarts
  - `ops/ai-pipeline/stab-001/full-suite-stability-run2.log` - 0 crashes, 0 restarts
  - `ops/ai-pipeline/stab-001/full-suite-stability-run3.log` - 0 crashes, 0 restarts
- **Test command exit code**: `65` (assertion failures)
- **Remaining failures**:
  - `testReplayIdleEnterExit` (ChronicleTests.swift:186-188) - assertion mismatch
  - `testTaggingEnginePriority` (ChronicleTests.swift:310) - assertion mismatch
