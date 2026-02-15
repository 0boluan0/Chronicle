#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="${PIPELINE_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "${PIPELINE_DIR}/.." && pwd)}"
RUNTIME_DIR="${PIPELINE_DIR}/runtime"
LOCKS_DIR="${RUNTIME_DIR}/locks"
EVENTS_DIR="${RUNTIME_DIR}/events"
INBOX_DIR="${RUNTIME_DIR}/inbox"
OUTBOX_DIR="${RUNTIME_DIR}/outbox"
PIDS_DIR="${RUNTIME_DIR}/pids"
LOGS_DIR="${RUNTIME_DIR}/logs"
HEARTBEAT_DIR="${RUNTIME_DIR}/heartbeat"
STATE_FILE="${RUNTIME_DIR}/state.yaml"
REPORTS_DIR="${PIPELINE_DIR}/reports"
BACKLOG_FILE="${PIPELINE_DIR}/backlog.yaml"
STATUS_BOARD_FILE="${PIPELINE_DIR}/status_board.md"
FAILURES_FILE="${PIPELINE_DIR}/failures/open_failures.yaml"
NEXT_COMMAND_FILE="${PIPELINE_DIR}/commands/next_command.md"
BASELINE_SCRIPT="${PIPELINE_DIR}/scripts/run_baseline_and_extract.sh"
FINAL_SUMMARY_FILE="${REPORTS_DIR}/orchestrator-final-summary.md"

now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

now_local() {
  date +"%Y-%m-%d %H:%M %z"
}

ensure_runtime_layout() {
  mkdir -p "${LOCKS_DIR}" "${EVENTS_DIR}" "${INBOX_DIR}" "${OUTBOX_DIR}" "${PIDS_DIR}" "${LOGS_DIR}" "${HEARTBEAT_DIR}" "${REPORTS_DIR}"
  : > "${LOCKS_DIR}/repo_write.lock"
  : > "${LOCKS_DIR}/baseline.lock"
  [[ -f "${STATE_FILE}" ]] || state_init
}

last_cycle_from_reports() {
  local max=0
  local f
  for f in "${REPORTS_DIR}"/cycle-*.md; do
    [[ -e "${f}" ]] || continue
    local base
    base="$(basename "${f}")"
    local n
    n="${base#cycle-}"
    n="${n%.md}"
    if [[ "${n}" =~ ^[0-9]+$ ]] && ((10#${n} > max)); then
      max=$((10#${n}))
    fi
  done
  echo "${max}"
}

state_init() {
  local initial_cycle
  initial_cycle="$(last_cycle_from_reports)"
  cat > "${STATE_FILE}" <<STATE_EOF
run_id: run-$(date +"%Y%m%d-%H%M%S")
status: BOOTSTRAP
started_at_utc: $(now_utc)
updated_at_utc: $(now_utc)
cycle: ${initial_cycle}
stuck_count: 0
stop_requested: false
stop_reason: NONE
current_task_id: NONE
goal_task_ids: ${GOAL_TASK_IDS:-FEAT-001}
completed_goal_ids: 
last_ai1_exit: -1
last_ai2_exit: -1
last_commit: NONE
target_branch: ${TARGET_BRANCH:-codex/orchestrated}
dry_run: false
STATE_EOF
}

state_get() {
  local key="$1"
  local default="${2:-}"
  local value
  value="$(awk -v k="${key}" '$1==k":" {$1=""; sub(/^ /,""); print; found=1; exit} END{if(!found) exit 1}' "${STATE_FILE}" 2>/dev/null || true)"
  if [[ -z "${value}" ]]; then
    echo "${default}"
  else
    echo "${value}"
  fi
}

state_set() {
  local key="$1"
  shift
  local value="$*"
  local tmp
  tmp="$(mktemp)"
  awk -v k="${key}" -v v="${value}" '
    BEGIN { found = 0 }
    $1 == k":" {
      print k": "v
      found = 1
      next
    }
    { print }
    END {
      if (!found) {
        print k": "v
      }
    }
  ' "${STATE_FILE}" > "${tmp}"
  mv "${tmp}" "${STATE_FILE}"
  state_touch
}

state_touch() {
  local ts
  ts="$(now_utc)"
  local tmp
  tmp="$(mktemp)"
  awk -v v="${ts}" '
    BEGIN { found = 0 }
    $1 == "updated_at_utc:" {
      print "updated_at_utc: " v
      found = 1
      next
    }
    { print }
    END {
      if (!found) {
        print "updated_at_utc: " v
      }
    }
  ' "${STATE_FILE}" > "${tmp}"
  mv "${tmp}" "${STATE_FILE}"
}

bool_true() {
  local v="${1:-false}"
  [[ "${v}" == "true" || "${v}" == "1" || "${v}" == "yes" ]]
}

event_file_for_today() {
  echo "${EVENTS_DIR}/events-$(date +"%Y%m%d").jsonl"
}

log_event() {
  local level="$1"
  local event="$2"
  local message="$3"
  local cycle="${4:-$(state_get cycle 0)}"
  local task_id="${5:-$(state_get current_task_id NONE)}"
  jq -nc \
    --arg ts "$(now_utc)" \
    --arg level "${level}" \
    --arg event "${event}" \
    --arg message "${message}" \
    --arg cycle "${cycle}" \
    --arg task_id "${task_id}" \
    '{timestamp:$ts,level:$level,event:$event,message:$message,cycle:$cycle,task_id:$task_id}' \
    >> "$(event_file_for_today)"
}

acquire_lock() {
  local lock_file="$1"
  local timeout_seconds="${2:-300}"
  local waited=0
  while true; do
    if shlock -f "${lock_file}" -p "$$" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
    if (( waited >= timeout_seconds )); then
      return 1
    fi
  done
}

release_lock() {
  local lock_file="$1"
  rm -f "${lock_file}"
}

parse_task_id() {
  local file="$1"
  rg -o "Task[[:space:]]+[A-Za-z0-9_-]+" "${file}" | head -n1 | awk '{print $2}' || true
}

is_terminal_task() {
  local file="$1"
  rg -q "^# Task (DONE|NONE)(\b|[[:space:]])" "${file}"
}

blocking_open_count() {
  local file="$1"
  awk '
    function emit() {
      if (in_item && blocking == "true" && status == "open") {
        count++
      }
    }
    /^[[:space:]]*-[[:space:]]id:/ {
      emit()
      in_item = 1
      status = ""
      blocking = "false"
      next
    }
    in_item && /^[[:space:]]+status:/ {
      status = $2
      next
    }
    in_item && /^[[:space:]]+blocking:/ {
      blocking = $2
      next
    }
    END {
      emit()
      print count + 0
    }
  ' "${file}"
}

highest_open_failure() {
  local file="$1"
  awk '
    function emit() {
      if (in_item && status == "open") {
        print id "|" priority "|" blocking "|" type "|" signature
      }
    }
    /^[[:space:]]*-[[:space:]]id:/ {
      emit()
      in_item = 1
      id = $3
      priority = "P9"
      status = ""
      blocking = "false"
      type = "unknown"
      signature = ""
      next
    }
    in_item && /^[[:space:]]+priority:/ { priority = $2; next }
    in_item && /^[[:space:]]+status:/ { status = $2; next }
    in_item && /^[[:space:]]+blocking:/ { blocking = $2; next }
    in_item && /^[[:space:]]+type:/ { type = $2; next }
    in_item && /^[[:space:]]+signature:/ {
      sub(/^[[:space:]]+signature:[[:space:]]*/, "", $0)
      gsub(/^"/, "", $0)
      gsub(/"$/, "", $0)
      signature = $0
      next
    }
    END { emit() }
  ' "${file}" | awk -F'|' '
    function rank(p) {
      if (p == "P0") return 0
      if (p == "P1") return 1
      if (p == "P2") return 2
      return 9
    }
    { print rank($2) "|" $0 }
  ' | sort -t'|' -k1,1n | head -n1 | cut -d'|' -f2-
}

next_ready_feature_task() {
  local file="$1"
  awk '
    function emit() {
      if (in_item && track == "feature" && status == "ready") {
        print id "|" priority
      }
    }
    /^[[:space:]]*-[[:space:]]id:/ {
      emit()
      in_item = 1
      id = $3
      track = ""
      status = ""
      priority = "P9"
      next
    }
    in_item && /^[[:space:]]+track:/ { track = $2; next }
    in_item && /^[[:space:]]+status:/ { status = $2; next }
    in_item && /^[[:space:]]+priority:/ { priority = $2; next }
    END { emit() }
  ' "${file}" | awk -F'|' '
    function rank(p) {
      if (p == "P0") return 0
      if (p == "P1") return 1
      if (p == "P2") return 2
      return 9
    }
    { print rank($2) "|" $0 }
  ' | sort -t'|' -k1,1n | head -n1 | cut -d'|' -f2
}

csv_contains() {
  local csv="$1"
  local needle="$2"
  [[ ",${csv}," == *",${needle},"* ]]
}

csv_add_unique() {
  local csv="$1"
  local val="$2"
  if [[ -z "${csv}" ]]; then
    echo "${val}"
    return
  fi
  if csv_contains "${csv}" "${val}"; then
    echo "${csv}"
  else
    echo "${csv},${val}"
  fi
}

goals_completed() {
  local goals="${GOAL_TASK_IDS:-$(state_get goal_task_ids)}"
  local completed="$(state_get completed_goal_ids)"
  IFS=',' read -r -a goal_arr <<< "${goals}"
  local g
  for g in "${goal_arr[@]}"; do
    [[ -z "${g}" ]] && continue
    if ! csv_contains "${completed}" "${g}"; then
      return 1
    fi
  done
  return 0
}

ensure_target_branch() {
  local current_branch
  current_branch="$(git -C "${REPO_ROOT}" branch --show-current)"
  if [[ "${current_branch}" == "${TARGET_BRANCH}" ]]; then
    return 0
  fi
  git -C "${REPO_ROOT}" checkout -B "${TARGET_BRANCH}" >/dev/null
}

update_status_board() {
  local stage="$1"
  local active_task="$2"
  local blocking_open="$3"
  local latest_log="$4"
  local gate="OFF"
  if (( blocking_open > 0 )); then
    gate="ON"
  fi
  cat > "${STATUS_BOARD_FILE}" <<BOARD_EOF
# Chronicle AI Pipeline Status Board

Updated: $(now_local)

## Now
- Stage: \`${stage}\`
- Active Task: \`${active_task}\`
- Dispatch Rule: Highest-priority open failure first; if none, dispatch next ready feature task
- Latest Baseline: \`${latest_log}\`

## Blocked
- $( (( blocking_open > 0 )) && echo "Blocking failures open (${blocking_open})" || echo "None" )

## Done (Recent 10)
- Managed by orchestrator runtime reports (`cycle-<N>.md`)

## Metrics
| Metric | Value | Notes |
|---|---:|---|
| cycle_count | $(state_get cycle 0) | Current orchestrator cycle |
| open_blocking_failures | ${blocking_open} | From open_failures.yaml |
| latest_local_test_exit_code | $(state_get last_ai2_exit -1) | Baseline command exit code |
| stuck_count | $(state_get stuck_count 0) | Consecutive no-progress cycles |
| stabilization_gate | ${gate} | ON when blocking failures > 0 |
BOARD_EOF
}

write_cycle_report() {
  local cycle="$1"
  local failure_id="$2"
  local decision="$3"
  local next_id="$4"
  local note="$5"
  local report_file
  report_file="${REPORTS_DIR}/cycle-$(printf "%03d" "${cycle}").md"
  cat > "${report_file}" <<REPORT_EOF
# Cycle $(printf "%03d" "${cycle}") Report

## Failure ID
- \`${failure_id}\`

## Repro Command
\`\`\`bash
xcodebuild -project Chronicle.xcodeproj -scheme Chronicle -destination 'platform=macOS' test -resultBundlePath build/TestResults/latest.xcresult
\`\`\`

## Fix Verification
- Refer baseline: \`${PIPELINE_DIR}/baseline/test_baseline.md\`

## Decision
- \`${decision}\`

## Next Command ID
- \`${next_id}\`

## Notes
- ${note}
REPORT_EOF
}

write_done_command() {
  local reason="$1"
  cat > "${NEXT_COMMAND_FILE}" <<DONE_EOF
# Task DONE — Orchestrator Completion

## Objective
Stop dispatching new work because completion criteria are satisfied.

## Reason
- ${reason}

## Next Command ID
- NONE
DONE_EOF
}

write_fallback_next_command() {
  local task_id="$1"
  local mode="$2"
  local extra="$3"
  cat > "${NEXT_COMMAND_FILE}" <<CMD_EOF
# Task ${task_id} — Auto Dispatch (${mode})

## Objective
Execute this orchestrator-dispatched task with strict scope and close the highest-priority pending objective.

## Scope In
- Implement only changes required for \`${task_id}\`
- Update tests needed by the task
- Keep changes minimal and reversible

## Scope Out
- Unrelated refactors
- New feature work outside current task

## Required Tests
\`\`\`bash
xcodebuild -project Chronicle.xcodeproj -scheme Chronicle -destination 'platform=macOS' test -resultBundlePath build/TestResults/latest.xcresult
\`\`\`

## Acceptance Criteria
- [ ] Task objective implemented
- [ ] Required tests pass
- [ ] Pipeline artifacts updated by AI2

## Output Format
1. Changed files
2. Test commands and results
3. Acceptance checklist

## Notes
- ${extra}
CMD_EOF
}

write_final_summary() {
  local reason="$1"
  cat > "${FINAL_SUMMARY_FILE}" <<SUMMARY_EOF
# Orchestrator Final Summary

- Time (UTC): $(now_utc)
- Reason: ${reason}
- Final Status: $(state_get status UNKNOWN)
- Cycle: $(state_get cycle 0)
- Stuck Count: $(state_get stuck_count 0)
- Current Task: $(state_get current_task_id NONE)
- Completed Goals: $(state_get completed_goal_ids)
- Target Goals: $(state_get goal_task_ids)
- Last AI1 Exit: $(state_get last_ai1_exit -1)
- Last AI2 Exit: $(state_get last_ai2_exit -1)
- Last Commit: $(state_get last_commit NONE)

## Artifacts
- State: \`${STATE_FILE}\`
- Failures: \`${FAILURES_FILE}\`
- Next Command: \`${NEXT_COMMAND_FILE}\`
- Status Board: \`${STATUS_BOARD_FILE}\`
SUMMARY_EOF
}

set_stop() {
  local reason="$1"
  state_set stop_requested true
  state_set stop_reason "${reason}"
  state_set status "${reason}"
}

is_stop_requested() {
  bool_true "$(state_get stop_requested false)"
}

record_heartbeat() {
  local worker="$1"
  jq -nc --arg ts "$(now_utc)" --arg worker "${worker}" '{timestamp:$ts,worker:$worker}' > "${HEARTBEAT_DIR}/${worker}.json"
}

safe_slug() {
  local raw="$1"
  echo "${raw}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-'
}
