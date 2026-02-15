#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"
source "${SCRIPT_DIR}/lib.sh"

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

REPO_LOCK_FILE="${LOCKS_DIR}/repo_write.lock"

next_dispatch_file() {
  local candidate
  for candidate in "${INBOX_DIR}"/dispatch-*.json; do
    [[ -e "${candidate}" ]] || continue
    local cycle
    cycle="$(jq -r '.cycle' "${candidate}" 2>/dev/null || true)"
    [[ -n "${cycle}" ]] || continue
    local outbox_file="${OUTBOX_DIR}/ai1-result-${cycle}.json"
    if [[ ! -f "${outbox_file}" ]]; then
      echo "${candidate}"
      return 0
    fi
  done
  return 1
}

build_prompt_file() {
  local cycle="$1"
  local task_id="$2"
  local prompt_file="$3"

  cat > "${prompt_file}" <<PROMPT_EOF
$(cat "${SCRIPT_DIR}/prompts/ai1_system_prompt.md")

Cycle: ${cycle}
Task ID: ${task_id}
Repo Root: ${REPO_ROOT}
Command Contract: ${NEXT_COMMAND_FILE}

Dispatch Contract Content:

$(cat "${NEXT_COMMAND_FILE}")
PROMPT_EOF
}

commit_changes_if_needed() {
  local cycle="$1"
  local task_id="$2"
  local commit_status="no_diff"
  local commit_sha=""

  local diff_count
  diff_count="$(git -C "${REPO_ROOT}" status --porcelain | wc -l | tr -d ' ')"

  if (( diff_count == 0 )); then
    echo "${commit_status}|${commit_sha}"
    return 0
  fi

  if ! bool_true "${AUTO_COMMIT}"; then
    echo "changes_not_committed|${commit_sha}"
    return 0
  fi

  local summary
  summary="$(awk 'BEGIN{found=0} /^## Objective/{found=1; next} found && /^[^-]/ {next} found && /^-/{sub(/^- /,""); print; exit}' "${NEXT_COMMAND_FILE}" || true)"
  [[ -n "${summary}" ]] || summary="orchestrated update"
  summary="$(echo "${summary}" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-72)"

  set +e
  git -C "${REPO_ROOT}" add -A
  git -C "${REPO_ROOT}" commit -m "ai1(cycle-${cycle}): ${task_id} ${summary}" >/dev/null 2>&1
  local commit_exit=$?
  set -e

  if [[ ${commit_exit} -eq 0 ]]; then
    commit_status="committed"
    commit_sha="$(git -C "${REPO_ROOT}" rev-parse --short HEAD)"
    state_set last_commit "${commit_sha}"
  else
    commit_status="commit_failed"
  fi

  if bool_true "${AUTO_PUSH}" && [[ "${commit_status}" == "committed" ]]; then
    set +e
    git -C "${REPO_ROOT}" push >/dev/null 2>&1
    local push_exit=$?
    set -e
    if [[ ${push_exit} -ne 0 ]]; then
      commit_status="push_failed"
    fi
  fi

  echo "${commit_status}|${commit_sha}"
}

process_dispatch() {
  local dispatch_file="$1"

  local cycle
  cycle="$(jq -r '.cycle' "${dispatch_file}")"
  local task_id
  task_id="$(jq -r '.task_id' "${dispatch_file}")"
  local outbox_file="${OUTBOX_DIR}/ai1-result-${cycle}.json"
  local cycle_log="${LOGS_DIR}/ai1-cycle-$(printf '%03d' "${cycle}").log"
  local last_message_file="${LOGS_DIR}/ai1-cycle-$(printf '%03d' "${cycle}")-message.md"
  local prompt_file
  prompt_file="$(mktemp "${LOGS_DIR}/ai1-prompt-${cycle}-XXXXXX")"

  if [[ "${task_id}" == "DONE" || "${task_id}" == "NONE" ]]; then
    jq -n \
      --arg ts "$(now_utc)" \
      --arg cycle "${cycle}" \
      --arg task_id "${task_id}" \
      '{timestamp:$ts,cycle:($cycle|tonumber),task_id:$task_id,result:"skipped_terminal",codex_exit:0,commit_status:"no_diff",commit_sha:""}' \
      > "${outbox_file}"
    rm -f "${dispatch_file}" "${prompt_file}"
    return 0
  fi

  if ! acquire_lock "${REPO_LOCK_FILE}" 600; then
    jq -n \
      --arg ts "$(now_utc)" \
      --arg cycle "${cycle}" \
      --arg task_id "${task_id}" \
      '{timestamp:$ts,cycle:($cycle|tonumber),task_id:$task_id,result:"lock_timeout",codex_exit:98,commit_status:"no_diff",commit_sha:""}' \
      > "${outbox_file}"
    rm -f "${prompt_file}"
    return 0
  fi

  local lock_released=0
  cleanup_lock() {
    if [[ ${lock_released} -eq 0 ]]; then
      release_lock "${REPO_LOCK_FILE}"
      lock_released=1
    fi
  }
  trap cleanup_lock RETURN

  state_set status AI1_EXECUTE
  state_set current_task_id "${task_id}"
  log_event info ai1_execute "AI1 starts task execution" "${cycle}" "${task_id}"

  build_prompt_file "${cycle}" "${task_id}" "${prompt_file}"

  local codex_exit=0
  local result="success"

  if [[ ${DRY_RUN} -eq 1 ]]; then
    {
      echo "[dry-run] AI1 would execute task ${task_id}"
      echo "[dry-run] cycle=${cycle}"
    } > "${cycle_log}"
    codex_exit=0
  else
    local cmd=(codex exec -C "${REPO_ROOT}" --sandbox danger-full-access -o "${last_message_file}" -)
    if [[ -n "${AI1_MODEL}" ]]; then
      cmd=(codex exec -C "${REPO_ROOT}" --sandbox danger-full-access --model "${AI1_MODEL}" -o "${last_message_file}" -)
    fi

    set +e
    "${cmd[@]}" < "${prompt_file}" > "${cycle_log}" 2>&1
    codex_exit=$?
    set -e

    if [[ ${codex_exit} -ne 0 ]]; then
      result="failed"
    fi
  fi

  local commit_status commit_sha commit_info
  if [[ ${DRY_RUN} -eq 1 ]]; then
    commit_status="no_diff"
    commit_sha=""
  else
    commit_info="$(commit_changes_if_needed "${cycle}" "${task_id}")"
    commit_status="${commit_info%%|*}"
    commit_sha="${commit_info#*|}"
  fi

  if [[ "${commit_status}" == "commit_failed" || "${commit_status}" == "push_failed" ]]; then
    result="commit_error"
    codex_exit=97
  elif [[ "${commit_status}" == "no_diff" && "${result}" == "success" ]]; then
    result="no_diff"
  fi

  jq -n \
    --arg ts "$(now_utc)" \
    --arg cycle "${cycle}" \
    --arg task_id "${task_id}" \
    --arg result "${result}" \
    --arg commit_status "${commit_status}" \
    --arg commit_sha "${commit_sha}" \
    --arg cycle_log "${cycle_log}" \
    --arg last_message_file "${last_message_file}" \
    --argjson codex_exit "${codex_exit}" \
    '{timestamp:$ts,cycle:($cycle|tonumber),task_id:$task_id,result:$result,codex_exit:$codex_exit,commit_status:$commit_status,commit_sha:$commit_sha,cycle_log:$cycle_log,last_message_file:$last_message_file}' \
    > "${outbox_file}"

  state_set last_ai1_exit "${codex_exit}"
  log_event info ai1_result "AI1 finished task execution" "${cycle}" "${task_id}"

  rm -f "${dispatch_file}" "${prompt_file}"
}

main() {
  ensure_runtime_layout
  log_event info ai1_start "AI1 worker started"

  while true; do
    record_heartbeat ai1

    if is_stop_requested; then
      log_event info ai1_stop "AI1 worker noticed stop request"
      break
    fi

    local dispatch_file=""
    dispatch_file="$(next_dispatch_file || true)"
    if [[ -z "${dispatch_file}" ]]; then
      sleep "${POLL_INTERVAL_SECONDS}"
      continue
    fi

    process_dispatch "${dispatch_file}"
  done
}

main
