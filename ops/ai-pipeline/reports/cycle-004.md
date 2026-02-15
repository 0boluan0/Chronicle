# Cycle 004 Report

## Failure ID
- `FAIL-P2-001`
- `FAIL-P1-003`

## Repro Command
```bash
xcodebuild -project Chronicle.xcodeproj -scheme Chronicle -destination 'platform=macOS' test -resultBundlePath build/TestResults/latest.xcresult
```

## Fix Verification
- Completed successfully
- Full suite passed: `Executed 13 tests, with 0 failures`
- Latest baseline artifact: `ops/ai-pipeline/baseline/test_baseline.md`

## Decision
- `PASS`: dependency + runtime side-effect issues are closed
- Reason: test target dependency restored and test-host startup side effects disabled during unit tests

## Next Command ID
- `FEAT-001`

## Notes
- **Root cause A (`FAIL-P2-001`)**: `ChronicleTests` lacked explicit target dependency on `Chronicle`, causing module resolution failure (`Unable to find module dependency: 'Chronicle'`).
- **Fix A**:
  - Added `PBXTargetDependency` and `PBXContainerItemProxy` from test target to app target.
  - Changed file: `Chronicle.xcodeproj/project.pbxproj`
- **Root cause B (`FAIL-P1-003`)**: unit-test host still executed runtime startup services and emitted tracker side-effect log.
- **Fix B**:
  - Added test-mode launch guard in `AppDelegate` to skip `ActivityTracker`, hotkey registration, and auto-export while running unit tests.
  - Changed file: `Chronicle/App/AppDelegate.swift`
- **Pipeline tooling update**:
  - Baseline extractor now also matches `Unable to find module dependency: 'Chronicle'` and writes dynamic gate state (`ON/OFF`).
  - Changed file: `ops/ai-pipeline/scripts/run_baseline_and_extract.sh`
