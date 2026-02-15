# Test Baseline

- Generated (UTC): `2026-02-15T09:14:36Z`
- Exit Code: `0`
- Result Bundle: `/Users/fengyihang/Chronicle/Chronicle/build/TestResults/latest.xcresult`
- Raw Log: `/Users/fengyihang/Chronicle/Chronicle/ops/ai-pipeline/baseline/runs/xcodebuild-20260215-171436.log`

## Command

```bash
xcodebuild -project Chronicle.xcodeproj -scheme Chronicle -destination 'platform=macOS' test -resultBundlePath build/TestResults/latest.xcresult
```

## Signals

| Priority | Failure ID | Status | Detection Count |
|---|---|---|---:|
| P0 | FAIL-P0-001 | closed | 0 |
| P1 | FAIL-P1-001 | closed | 0 |
| P1 | FAIL-P1-002 | closed | 0 |
| P1 | FAIL-P1-003 | closed | 0 |
| P2 | FAIL-P2-001 | closed | 0 |

## Gate Decision

- Stabilization gate is **OFF**.
- No blocking failures detected in this baseline run; feature-track dispatch is allowed.
