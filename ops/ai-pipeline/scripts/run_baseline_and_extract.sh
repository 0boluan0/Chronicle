#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PIPELINE_DIR}/../.." && pwd)"

RESULT_DIR="${REPO_ROOT}/build/TestResults"
RUNS_DIR="${PIPELINE_DIR}/baseline/runs"
FAILURES_FILE="${PIPELINE_DIR}/failures/open_failures.yaml"
BASELINE_FILE="${PIPELINE_DIR}/baseline/test_baseline.md"

mkdir -p "${RESULT_DIR}" "${RUNS_DIR}" "${PIPELINE_DIR}/failures" "${PIPELINE_DIR}/baseline"

STAMP="$(date +"%Y%m%d-%H%M%S")"
NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
LOG_FILE="${RUNS_DIR}/xcodebuild-${STAMP}.log"
LATEST_LOG="${RESULT_DIR}/latest.log"
RESULT_BUNDLE="${RESULT_DIR}/latest.xcresult"

COMMAND="xcodebuild -project Chronicle.xcodeproj -scheme Chronicle -destination 'platform=macOS' test -resultBundlePath build/TestResults/latest.xcresult"

rm -rf "${RESULT_BUNDLE}"

pushd "${REPO_ROOT}" >/dev/null
set +e
bash -lc "${COMMAND}" 2>&1 | tee "${LOG_FILE}"
TEST_EXIT_CODE=${PIPESTATUS[0]}
set -e
popd >/dev/null

cp "${LOG_FILE}" "${LATEST_LOG}"

count_matches() {
    local pattern="$1"
    local file="$2"
    local value
    value=$(rg -c --no-messages "$pattern" "$file" || true)
    if [[ -z "${value}" ]]; then
        echo 0
    else
        echo "${value}"
    fi
}

first_match() {
    local pattern="$1"
    local file="$2"
    rg -n -m 1 --no-messages "$pattern" "$file" || true
}

yaml_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

MALLOC_COUNT=$(count_matches "pointer being freed was not allocated" "${LOG_FILE}")
RESTART_COUNT=$(count_matches "Restarting after unexpected exit" "${LOG_FILE}")
IDLE_FAIL_COUNT=$(count_matches "ChronicleTests\\.swift:186: error: -\\[ChronicleTests\\.ChronicleTests testReplayIdleEnterExit\\]" "${LOG_FILE}")
TAGGING_FAIL_COUNT=$(count_matches "ChronicleTests\\.swift:310: error: -\\[ChronicleTests\\.ChronicleTests testTaggingEnginePriority\\]" "${LOG_FILE}")
TRACKER_SIDE_EFFECT_COUNT=$(count_matches "\\[tracker\\] Activity tracker started" "${LOG_FILE}")
DEP_WARN_COUNT=$(count_matches "missing a dependency on 'Chronicle'|Unable to find module dependency: 'Chronicle'" "${LOG_FILE}")

MALLOC_LINE=$(first_match "pointer being freed was not allocated" "${LOG_FILE}")
RESTART_LINE=$(first_match "Restarting after unexpected exit" "${LOG_FILE}")
IDLE_LINE=$(first_match "ChronicleTests\\.swift:186: error: -\\[ChronicleTests\\.ChronicleTests testReplayIdleEnterExit\\]" "${LOG_FILE}")
TAGGING_LINE=$(first_match "ChronicleTests\\.swift:310: error: -\\[ChronicleTests\\.ChronicleTests testTaggingEnginePriority\\]" "${LOG_FILE}")
TRACKER_SIDE_EFFECT_LINE=$(first_match "\\[tracker\\] Activity tracker started" "${LOG_FILE}")
DEP_WARN_LINE=$(first_match "missing a dependency on 'Chronicle'|Unable to find module dependency: 'Chronicle'" "${LOG_FILE}")

if [[ "${MALLOC_COUNT}" -gt 0 || "${RESTART_COUNT}" -gt 0 ]]; then
    P0_STATUS="open"
else
    P0_STATUS="closed"
fi

if [[ "${IDLE_FAIL_COUNT}" -gt 0 ]]; then
    IDLE_STATUS="open"
else
    IDLE_STATUS="closed"
fi

if [[ "${TAGGING_FAIL_COUNT}" -gt 0 ]]; then
    TAGGING_STATUS="open"
else
    TAGGING_STATUS="closed"
fi

if [[ "${TRACKER_SIDE_EFFECT_COUNT}" -gt 0 ]]; then
    SIDE_EFFECT_STATUS="open"
else
    SIDE_EFFECT_STATUS="closed"
fi

if [[ "${DEP_WARN_COUNT}" -gt 0 ]]; then
    P2_STATUS="open"
else
    P2_STATUS="closed"
fi

OPEN_BLOCKING_COUNT=0
[[ "${P0_STATUS}" == "open" ]] && OPEN_BLOCKING_COUNT=$((OPEN_BLOCKING_COUNT + 1))
[[ "${IDLE_STATUS}" == "open" ]] && OPEN_BLOCKING_COUNT=$((OPEN_BLOCKING_COUNT + 1))
[[ "${TAGGING_STATUS}" == "open" ]] && OPEN_BLOCKING_COUNT=$((OPEN_BLOCKING_COUNT + 1))
[[ "${SIDE_EFFECT_STATUS}" == "open" ]] && OPEN_BLOCKING_COUNT=$((OPEN_BLOCKING_COUNT + 1))

if [[ "${OPEN_BLOCKING_COUNT}" -gt 0 ]]; then
    STABILIZATION_GATE="ON"
else
    STABILIZATION_GATE="OFF"
fi

cat > "${FAILURES_FILE}" <<EOF2
generated_at: "${NOW_UTC}"
source:
  command: "$(yaml_escape "${COMMAND}")"
  exit_code: ${TEST_EXIT_CODE}
  log_file: "$(yaml_escape "${LOG_FILE}")"
  result_bundle: "$(yaml_escape "${RESULT_BUNDLE}")"

failures:
  - id: FAIL-P0-001
    priority: P0
    type: process_crash
    status: ${P0_STATUS}
    blocking: true
    signature: "malloc pointer being freed was not allocated"
    detection_count: $((MALLOC_COUNT + RESTART_COUNT))
    evidence:
      malloc_line: "$(yaml_escape "${MALLOC_LINE}")"
      restart_line: "$(yaml_escape "${RESTART_LINE}")"

  - id: FAIL-P1-001
    priority: P1
    type: assertion_failure
    status: ${IDLE_STATUS}
    blocking: true
    signature: "testReplayIdleEnterExit assertion mismatch"
    detection_count: ${IDLE_FAIL_COUNT}
    evidence:
      first_line: "$(yaml_escape "${IDLE_LINE}")"

  - id: FAIL-P1-002
    priority: P1
    type: assertion_failure
    status: ${TAGGING_STATUS}
    blocking: true
    signature: "testTaggingEnginePriority expected Optional(200)"
    detection_count: ${TAGGING_FAIL_COUNT}
    evidence:
      first_line: "$(yaml_escape "${TAGGING_LINE}")"

  - id: FAIL-P1-003
    priority: P1
    type: test_environment_side_effect
    status: ${SIDE_EFFECT_STATUS}
    blocking: true
    signature: "runtime tracker/app lifecycle logs appear during unit-test execution"
    detection_count: ${TRACKER_SIDE_EFFECT_COUNT}
    evidence:
      first_line: "$(yaml_escape "${TRACKER_SIDE_EFFECT_LINE}")"

  - id: FAIL-P2-001
    priority: P2
    type: warning
    status: ${P2_STATUS}
    blocking: false
    signature: "ChronicleTests missing explicit dependency on Chronicle"
    detection_count: ${DEP_WARN_COUNT}
    evidence:
      first_line: "$(yaml_escape "${DEP_WARN_LINE}")"
EOF2

cat > "${BASELINE_FILE}" <<EOF3
# Test Baseline

- Generated (UTC): \`${NOW_UTC}\`
- Exit Code: \`${TEST_EXIT_CODE}\`
- Result Bundle: \`${RESULT_BUNDLE}\`
- Raw Log: \`${LOG_FILE}\`

## Command

\`\`\`bash
${COMMAND}
\`\`\`

## Signals

| Priority | Failure ID | Status | Detection Count |
|---|---|---|---:|
| P0 | FAIL-P0-001 | ${P0_STATUS} | $((MALLOC_COUNT + RESTART_COUNT)) |
| P1 | FAIL-P1-001 | ${IDLE_STATUS} | ${IDLE_FAIL_COUNT} |
| P1 | FAIL-P1-002 | ${TAGGING_STATUS} | ${TAGGING_FAIL_COUNT} |
| P1 | FAIL-P1-003 | ${SIDE_EFFECT_STATUS} | ${TRACKER_SIDE_EFFECT_COUNT} |
| P2 | FAIL-P2-001 | ${P2_STATUS} | ${DEP_WARN_COUNT} |

## Gate Decision

- Stabilization gate is **${STABILIZATION_GATE}**.
EOF3

if [[ "${STABILIZATION_GATE}" == "ON" ]]; then
cat >> "${BASELINE_FILE}" <<EOF4
- Feature-track dispatch is forbidden while blocking failures remain open.
EOF4
else
cat >> "${BASELINE_FILE}" <<EOF5
- No blocking failures detected in this baseline run; feature-track dispatch is allowed.
EOF5
fi

exit "${TEST_EXIT_CODE}"
