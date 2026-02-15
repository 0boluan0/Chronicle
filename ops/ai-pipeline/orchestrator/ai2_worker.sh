#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"
source "${SCRIPT_DIR}/lib.sh"

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

BASELINE_LOCK_FILE="${LOCKS_DIR}/baseline.lock"

latest_baseline_log() {
  awk '/^[[:space:]]+log_file:/ {gsub(/"/, "", $2); print $2; exit}' "${FAILURES_FILE}" 2>/dev/null || true
}

run_baseline_locked() {
  local cycle="$1"
  local phase="$2"
  local baseline_exit=0

  if ! acquire_lock "${BASELINE_LOCK_FILE}" 900; then
    log_event error ai2_lock_timeout "AI2 failed to acquire baseline lock" "${cycle}"
    return 99
  fi

  local lock_released=0
  cleanup_lock() {
    if [[ ${lock_released} -eq 0 ]]; then
      release_lock "${BASELINE_LOCK_FILE}"
      lock_released=1
    fi
  }
  trap cleanup_lock RETURN

  if [[ ${DRY_RUN} -eq 1 ]]; then
    baseline_exit=0
    log_event info ai2_baseline_dry_run "AI2 dry-run baseline phase=${phase}" "${cycle}"
  else
    set +e
    "${BASELINE_SCRIPT}" > "${LOGS_DIR}/ai2-baseline-${phase}-cycle-$(printf '%03d' "${cycle}").log" 2>&1
    baseline_exit=$?
    set -e
  fi

  state_set last_ai2_exit "${baseline_exit}"
  echo "${baseline_exit}"
}

generate_next_command_with_codex() {
  local cycle="$1"
  local task_id="$2"
  local mode="$3"
  local context_note="$4"

  local prompt_file
  prompt_file="$(mktemp "${LOGS_DIR}/ai2-next-prompt-${cycle}-XXXXXX.md")"
  local output_file="${LOGS_DIR}/ai2-next-message-cycle-$(printf '%03d' "${cycle}").md"
  local run_log="${LOGS_DIR}/ai2-next-codex-cycle-$(printf '%03d' "${cycle}").log"

  cat > "${prompt_file}" <<PROMPT_EOF
$(cat "${SCRIPT_DIR}/prompts/ai2_system_prompt.md")

Cycle: ${cycle}
Mode: ${mode}
Target Task ID: ${task_id}

Current Baseline Snapshot:
$(sed -n '1,200p' "${PIPELINE_DIR}/baseline/test_baseline.md")

Open Failures Snapshot:
$(sed -n '1,220p' "${FAILURES_FILE}")

Backlog Snapshot:
$(sed -n '1,260p' "${BACKLOG_FILE}")

Extra Context:
- ${context_note}

Strict requirements:
- Return only markdown for next command file.
- First line must be: # Task ${task_id} — <Title>
- Must contain: Objective, Scope In, Scope Out, Required Tests, Acceptance Criteria, Output Format.
PROMPT_EOF

  local cmd=(codex exec -C "${REPO_ROOT}" --sandbox workspace-write -o "${output_file}" -)
  if [[ -n "${AI2_MODEL}" ]]; then
    cmd=(codex exec -C "${REPO_ROOT}" --sandbox workspace-write --model "${AI2_MODEL}" -o "${output_file}" -)
  fi

  set +e
  "${cmd[@]}" < "${prompt_file}" > "${run_log}" 2>&1
  local codex_exit=$?
  set -e

  rm -f "${prompt_file}"

  if [[ ${codex_exit} -ne 0 ]]; then
    log_event warn ai2_codex_failed "AI2 codex generation failed, fallback" "${cycle}" "${task_id}"
    return 1
  fi

  if ! rg -q "^# Task[[:space:]]+${task_id}(\b|[[:space:]])" "${output_file}"; then
    log_event warn ai2_codex_invalid "AI2 codex output invalid, fallback" "${cycle}" "${task_id}"
    return 1
  fi

  cp "${output_file}" "${NEXT_COMMAND_FILE}"
  log_event info ai2_codex_success "AI2 generated next command via codex" "${cycle}" "${task_id}"
  return 0
}

write_dispatch_payload() {
  local cycle="$1"
  local task_id="$2"
  local mode="$3"
  local dispatch_file="${INBOX_DIR}/dispatch-${cycle}.json"

  jq -n \
    --arg ts "$(now_utc)" \
    --arg cycle "${cycle}" \
    --arg task_id "${task_id}" \
    --arg mode "${mode}" \
    --arg command_file "${NEXT_COMMAND_FILE}" \
    '{timestamp:$ts,cycle:($cycle|tonumber),task_id:$task_id,mode:$mode,command_file:$command_file}' \
    > "${dispatch_file}"

  echo "${dispatch_file}"
}

wait_for_ai1_result() {
  local cycle="$1"
  local timeout_seconds="${AI1_TIMEOUT_SECONDS}"
  local waited=0
  local outbox_file="${OUTBOX_DIR}/ai1-result-${cycle}.json"

  while (( waited < timeout_seconds )); do
    if is_stop_requested; then
      return 2
    fi
    if [[ -f "${outbox_file}" ]]; then
      echo "${outbox_file}"
      return 0
    fi
    sleep "${POLL_INTERVAL_SECONDS}"
    waited=$((waited + POLL_INTERVAL_SECONDS))
    record_heartbeat ai2
  done

  return 1
}

mark_goal_completed_if_needed() {
  local task_id="$1"
  local ai1_exit="$2"
  local blocking_after="$3"

  [[ "${ai1_exit}" == "0" ]] || return 0
  (( blocking_after == 0 )) || return 0

  local goals="${GOAL_TASK_IDS}"
  if ! csv_contains "${goals}" "${task_id}"; then
    return 0
  fi

  local completed
  completed="$(state_get completed_goal_ids)"
  completed="$(csv_add_unique "${completed}" "${task_id}")"
  state_set completed_goal_ids "${completed}"
}

main() {
  ensure_runtime_layout
  log_event info ai2_start "AI2 worker started"

  while true; do
    record_heartbeat ai2

    if is_stop_requested; then
      log_event info ai2_stop "AI2 worker noticed stop request"
      break
    fi

    local cycle
    cycle=$(( $(state_get cycle 0) + 1 ))
    state_set cycle "${cycle}"
    state_set status AI2_BASELINE

    local pre_exit
    pre_exit="$(run_baseline_locked "${cycle}" pre)"

    local blocking_before
    blocking_before="$(blocking_open_count "${FAILURES_FILE}")"
    local highest
    highest="$(highest_open_failure "${FAILURES_FILE}" || true)"

    local failure_id="NONE"
    local failure_priority="NONE"
    if [[ -n "${highest}" ]]; then
      failure_id="${highest%%|*}"
      local rest="${highest#*|}"
      failure_priority="${rest%%|*}"
    fi

    local mode="feature"
    local target_task_id=""
    local context_note=""

    if (( blocking_before > 0 )); then
      mode="stabilization"
      target_task_id="STAB-AUTO-${failure_id}"
      context_note="Blocking failures detected: ${blocking_before}; highest=${failure_id} (${failure_priority})"
    else
      target_task_id="$(next_ready_feature_task "${BACKLOG_FILE}" || true)"
      if [[ -z "${target_task_id}" ]]; then
        mode="terminal"
        target_task_id="NONE"
        context_note="No open failures and no ready feature tasks found"
      else
        mode="feature"
        context_note="No blocking failures. Next ready feature task=${target_task_id}"
      fi
    fi

    if goals_completed && (( blocking_before == 0 )); then
      write_done_command "All goal tasks completed and no blocking failures are open."
      write_cycle_report "${cycle}" "${failure_id}" "PASS" "DONE" "Completion criteria reached before dispatch."
      update_status_board "Feature Development" "DONE" "${blocking_before}" "$(latest_baseline_log)"
      state_set status SUCCESS_STOP
      set_stop SUCCESS_STOP
      log_event info ai2_success_stop "AI2 reached success stop" "${cycle}" "DONE"
      break
    fi

    if [[ "${mode}" == "terminal" ]]; then
      write_done_command "No ready task found and no blocking failure remains."
    else
      if [[ ${DRY_RUN} -eq 1 ]]; then
        write_fallback_next_command "${target_task_id}" "${mode}" "Dry-run generated dispatch"
      elif ! generate_next_command_with_codex "${cycle}" "${target_task_id}" "${mode}" "${context_note}"; then
        write_fallback_next_command "${target_task_id}" "${mode}" "Fallback generated after AI2 codex failure"
      fi
    fi

    local next_id
    next_id="$(parse_task_id "${NEXT_COMMAND_FILE}")"
    [[ -n "${next_id}" ]] || next_id="UNKNOWN"

    write_cycle_report "${cycle}" "${failure_id}" "DISPATCHED" "${next_id}" "${context_note}"
    update_status_board "$( [[ "${mode}" == "stabilization" ]] && echo "Stabilization" || echo "Feature Development" )" "${next_id}" "${blocking_before}" "$(latest_baseline_log)"

    if is_terminal_task "${NEXT_COMMAND_FILE}"; then
      state_set status SUCCESS_STOP
      set_stop SUCCESS_STOP
      log_event info ai2_terminal_command "AI2 generated terminal command" "${cycle}" "${next_id}"
      break
    fi

    state_set status AI2_DISPATCH
    state_set current_task_id "${next_id}"
    write_dispatch_payload "${cycle}" "${next_id}" "${mode}" >/dev/null
    log_event info ai2_dispatch "AI2 dispatched task to AI1" "${cycle}" "${next_id}"

    local outbox_file=""
    if ! outbox_file="$(wait_for_ai1_result "${cycle}")"; then
      local stuck
      stuck=$(( $(state_get stuck_count 0) + 1 ))
      state_set stuck_count "${stuck}"
      write_cycle_report "${cycle}" "${failure_id}" "RETRY" "${next_id}" "AI1 timeout waiting for result"
      log_event warn ai2_timeout "AI1 result timeout" "${cycle}" "${next_id}"

      if (( stuck >= STUCK_THRESHOLD )); then
        write_fallback_next_command "${next_id}" "stuck-recovery" "Stuck threshold reached; manual diagnosis required"
        set_stop FUSE_STOP
        log_event error ai2_fuse_stop "Fuse stop triggered by timeout" "${cycle}" "${next_id}"
        break
      fi
      continue
    fi

    state_set status AI2_VERIFY

    local ai1_exit commit_status result_kind
    ai1_exit="$(jq -r '.codex_exit' "${outbox_file}")"
    commit_status="$(jq -r '.commit_status' "${outbox_file}")"
    result_kind="$(jq -r '.result' "${outbox_file}")"

    local verify_exit
    verify_exit="$(run_baseline_locked "${cycle}" post)"
    local blocking_after
    blocking_after="$(blocking_open_count "${FAILURES_FILE}")"

    local progress=0
    if (( blocking_after < blocking_before )); then
      progress=1
    fi
    if [[ "${result_kind}" == "success" || "${result_kind}" == "no_diff" ]]; then
      progress=1
    fi

    mark_goal_completed_if_needed "${next_id}" "${ai1_exit}" "${blocking_after}"

    if (( progress == 1 )); then
      state_set stuck_count 0
    else
      local stuck
      stuck=$(( $(state_get stuck_count 0) + 1 ))
      state_set stuck_count "${stuck}"
      if (( stuck >= STUCK_THRESHOLD )); then
        write_fallback_next_command "${next_id}" "stuck-recovery" "No progress for ${stuck} consecutive cycles"
        set_stop FUSE_STOP
        write_cycle_report "${cycle}" "${failure_id}" "FUSE_STOP" "${next_id}" "No progress for ${stuck} cycles"
        log_event error ai2_fuse_stop "Fuse stop triggered by no progress" "${cycle}" "${next_id}"
        break
      fi
    fi

    local decision="PASS"
    if (( blocking_after > 0 )); then
      decision="BLOCKED"
    fi

    write_cycle_report "${cycle}" "${failure_id}" "${decision}" "${next_id}" "ai1_exit=${ai1_exit}, commit=${commit_status}, pre=${pre_exit}, verify=${verify_exit}, blocking_before=${blocking_before}, blocking_after=${blocking_after}"
    update_status_board "$( [[ ${blocking_after} -gt 0 ]] && echo "Stabilization" || echo "Feature Development" )" "${next_id}" "${blocking_after}" "$(latest_baseline_log)"

    if goals_completed && (( blocking_after == 0 )); then
      write_done_command "Goal task IDs completed and no blocking failures remain."
      set_stop SUCCESS_STOP
      state_set status SUCCESS_STOP
      log_event info ai2_success_stop "Success stop after verify" "${cycle}" "${next_id}"
      break
    fi

    sleep "${POLL_INTERVAL_SECONDS}"
  done
}

main
