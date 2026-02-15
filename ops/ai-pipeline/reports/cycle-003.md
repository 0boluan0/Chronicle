# Cycle 003 Report

## Failure ID
- `FAIL-P1-002`

## Repro Command
```bash
xcodebuild -project Chronicle.xcodeproj -scheme Chronicle -destination 'platform=macOS' -only-testing:ChronicleTests/ChronicleTests/testTaggingEnginePriority test
```

## Fix Verification
- Completed successfully

## Decision
- `PASS`: Stabilization task STAB-003 completed
- Reason: 3 consecutive runs passed, full suite executed all 13 tests without failures

## Next Command ID
- None (all stabilization tasks completed)

## Notes
- **Root cause**: `TaggingEngine.evaluate` resolved equal-priority rules by `id` only, so a generic app-name rule (`tagId=100`) beat a bundle-id rule (`tagId=200`) when priorities were tied.

**Changed files**
- `Chronicle/Services/TaggingEngine.swift:26`
  - Added tie-break by rule specificity after priority (`bundle > app > title presence` composite score), then fallback to `id`.
  - Added helper `specificityScore(for:)` at `Chronicle/Services/TaggingEngine.swift:80`.
- `ChronicleTests/ChronicleTests.swift:310`
  - Added minimal verification in `testTaggingEnginePriority`:
    - `XCTAssertTrue(result.ruleMatched)`
    - Reversed-rules evaluation still returns `200`.

**Test commands executed and results**
1. `xcodebuild -project Chronicle.xcodeproj -scheme Chronicle -destination 'platform=macOS' -only-testing:ChronicleTests/ChronicleTests/testTaggingEnginePriority test`
   - Pre-fix run: **FAILED** (`Optional(100)` vs `Optional(200)`).
2. Same command (post-fix) run #1
   - **PASSED**.
3. Same command (post-fix) run #2
   - **PASSED**.
4. Same command (post-fix) run #3
   - **PASSED**.
5. `xcodebuild -project Chronicle.xcodeproj -scheme Chronicle -destination 'platform=macOS' test`
   - **PASSED** (`Executed 13 tests, with 0 failures`).
