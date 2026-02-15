#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"
source "${SCRIPT_DIR}/lib.sh"

AI1_PID_FILE="${PIDS_DIR}/ai1.pid"
AI2_PID_FILE="${PIDS_DIR}/ai2.pid"
SUP_PID_FILE="${PIDS_DIR}/supervisor.pid"

usage() {
  cat <<USAGE
Usage: $(basename "$0") <start|resume|status|stop|supervise> [--dry-run]

Commands:
  start       Start a fresh orchestrator run
  resume      Resume from existing runtime/state.yaml
  status      Show orchestrator status
  stop        Request graceful stop
  supervise   Internal supervisor loop
USAGE
}

pid_alive() {
  local pid="$1"
  [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1
}

read_pid() {
  local f="$1"
  [[ -f "${f}" ]] || return 1
  cat "${f}"
}

write_pid() {
  local f="$1"
  local pid="$2"
  echo "${pid}" > "${f}"
}

remove_pid_files() {
  rm -f "${AI1_PID_FILE}" "${AI2_PID_FILE}" "${SUP_PID_FILE}"
}

is_running() {
  local p
  p="$(read_pid "${SUP_PID_FILE}" 2>/dev/null || true)"
  pid_alive "${p}"
}

seconds_since_utc() {
  local ts="$1"
  python3 - "$ts" <<'PY'
from datetime import datetime, timezone
import sys
raw = sys.argv[1]
try:
    dt = datetime.strptime(raw, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
except ValueError:
    print(0)
    raise SystemExit(0)
now = datetime.now(timezone.utc)
print(int((now - dt).total_seconds()))
PY
}

bootstrap_commit_if_dirty() {
  local dry_run="$1"
  if [[ "${dry_run}" == "1" ]]; then
    return 0
  fi
  if ! bool_true "${AUTO_COMMIT}"; then
    return 0
  fi
  if ! bool_true "${BOOTSTRAP_COMMIT_DIRTY:-true}"; then
    return 0
  fi
  if [[ -z "$(git -C "${REPO_ROOT}" status --porcelain)" ]]; then
    return 0
  fi

  set +e
  git -C "${REPO_ROOT}" add -A
  git -C "${REPO_ROOT}" commit -m "orchestrator(bootstrap): snapshot workspace before automated cycles" >/dev/null 2>&1
  local commit_exit=$?
  set -e

  if [[ ${commit_exit} -eq 0 ]]; then
    local sha
    sha="$(git -C "${REPO_ROOT}" rev-parse --short HEAD)"
    state_set last_commit "${sha}"
    log_event info orchestrator_bootstrap_commit "Committed bootstrap workspace snapshot"
  else
    log_event warn orchestrator_bootstrap_commit "Bootstrap commit skipped or failed"
  fi
}

start_workers() {
  local dry_run="$1"

  local ai1_args=()
  local ai2_args=()
  if [[ "${dry_run}" == "1" ]]; then
    ai1_args+=(--dry-run)
    ai2_args+=(--dry-run)
  fi

  bash "${SCRIPT_DIR}/ai1_worker.sh" "${ai1_args[@]}" >> "${LOGS_DIR}/ai1-worker.log" 2>&1 &
  local ai1_pid=$!
  write_pid "${AI1_PID_FILE}" "${ai1_pid}"
  state_set ai1_pid "${ai1_pid}"

  bash "${SCRIPT_DIR}/ai2_worker.sh" "${ai2_args[@]}" >> "${LOGS_DIR}/ai2-worker.log" 2>&1 &
  local ai2_pid=$!
  write_pid "${AI2_PID_FILE}" "${ai2_pid}"
  state_set ai2_pid "${ai2_pid}"

  bash "${SCRIPT_DIR}/orchestrator.sh" supervise >> "${LOGS_DIR}/supervisor.log" 2>&1 &
  local sup_pid=$!
  write_pid "${SUP_PID_FILE}" "${sup_pid}"
  state_set supervisor_pid "${sup_pid}"
}

cmd_start() {
  local dry_run="$1"
  ensure_runtime_layout

  if is_running; then
    echo "Orchestrator already running"
    exit 1
  fi

  ensure_target_branch

  state_init
  state_set run_id "run-$(date +"%Y%m%d-%H%M%S")"
  state_set started_at_utc "$(now_utc)"
  state_set status BOOTSTRAP
  state_set stop_requested false
  state_set stop_reason NONE
  state_set stuck_count 0
  state_set completed_goal_ids ""
  state_set current_task_id NONE
  state_set dry_run "$( [[ "${dry_run}" == "1" ]] && echo true || echo false )"
  state_set target_branch "${TARGET_BRANCH}"
  state_set goal_task_ids "${GOAL_TASK_IDS}"
  state_set run_cycle_start "$(state_get cycle 0)"
  bootstrap_commit_if_dirty "${dry_run}"

  remove_pid_files
  start_workers "${dry_run}"

  log_event info orchestrator_start "Orchestrator started"
  echo "Started orchestrator run_id=$(state_get run_id)"
}

cmd_resume() {
  local dry_run="$1"
  ensure_runtime_layout

  if is_running; then
    echo "Orchestrator already running"
    exit 1
  fi

  ensure_target_branch

  state_set status BOOTSTRAP
  state_set stop_requested false
  state_set stop_reason NONE
  state_set dry_run "$( [[ "${dry_run}" == "1" ]] && echo true || echo false )"
  state_set run_cycle_start "$(state_get cycle 0)"
  [[ "$(state_get started_at_utc)" != "1970-01-01T00:00:00Z" ]] || state_set started_at_utc "$(now_utc)"

  remove_pid_files
  start_workers "${dry_run}"

  log_event info orchestrator_resume "Orchestrator resumed"
  echo "Resumed orchestrator run_id=$(state_get run_id)"
}

cmd_status() {
  ensure_runtime_layout

  local ai1_pid ai2_pid sup_pid
  ai1_pid="$(read_pid "${AI1_PID_FILE}" 2>/dev/null || true)"
  ai2_pid="$(read_pid "${AI2_PID_FILE}" 2>/dev/null || true)"
  sup_pid="$(read_pid "${SUP_PID_FILE}" 2>/dev/null || true)"

  echo "Run ID: $(state_get run_id unknown)"
  echo "Status: $(state_get status UNKNOWN)"
  echo "Cycle: $(state_get cycle 0)"
  echo "Current Task: $(state_get current_task_id NONE)"
  echo "Stop Requested: $(state_get stop_requested false)"
  echo "Stop Reason: $(state_get stop_reason NONE)"
  echo "Stuck Count: $(state_get stuck_count 0)"
  echo "Goals: $(state_get goal_task_ids)"
  echo "Completed Goals: $(state_get completed_goal_ids)"
  echo "AI1 PID: ${ai1_pid:-N/A} ($(pid_alive "${ai1_pid}" && echo alive || echo dead))"
  echo "AI2 PID: ${ai2_pid:-N/A} ($(pid_alive "${ai2_pid}" && echo alive || echo dead))"
  echo "Supervisor PID: ${sup_pid:-N/A} ($(pid_alive "${sup_pid}" && echo alive || echo dead))"

  local latest_event
  latest_event="$(tail -n 1 "$(event_file_for_today)" 2>/dev/null || true)"
  if [[ -n "${latest_event}" ]]; then
    echo "Latest Event: ${latest_event}"
  fi
}

cmd_stop() {
  ensure_runtime_layout
  state_set status STOP_REQUESTED
  set_stop USER_STOP
  log_event info orchestrator_stop "User requested stop"

  local pid
  pid="$(read_pid "${AI1_PID_FILE}" 2>/dev/null || true)"
  pid_alive "${pid}" && kill "${pid}" >/dev/null 2>&1 || true
  pid="$(read_pid "${AI2_PID_FILE}" 2>/dev/null || true)"
  pid_alive "${pid}" && kill "${pid}" >/dev/null 2>&1 || true
  pid="$(read_pid "${SUP_PID_FILE}" 2>/dev/null || true)"
  pid_alive "${pid}" && kill "${pid}" >/dev/null 2>&1 || true

  write_final_summary "USER_STOP"
  remove_pid_files
  echo "Stop requested"
}

cmd_supervise() {
  ensure_runtime_layout
  state_set status RUNNING
  log_event info supervisor_start "Supervisor loop started"

  while true; do
    record_heartbeat supervisor

    local ai1_pid ai2_pid
    ai1_pid="$(read_pid "${AI1_PID_FILE}" 2>/dev/null || true)"
    ai2_pid="$(read_pid "${AI2_PID_FILE}" 2>/dev/null || true)"

    if is_stop_requested; then
      break
    fi

    if ! pid_alive "${ai1_pid}" || ! pid_alive "${ai2_pid}"; then
      set_stop WORKER_EXIT
      log_event error supervisor_worker_exit "Detected worker process exit"
      break
    fi

    local run_cycle_start cycle_elapsed
    run_cycle_start="$(state_get run_cycle_start 0)"
    cycle_elapsed=$(( $(state_get cycle 0) - run_cycle_start ))
    if (( cycle_elapsed >= MAX_CYCLES )); then
      set_stop BUDGET_STOP
      log_event warn supervisor_budget "Cycle budget exceeded"
      break
    fi

    local started elapsed
    started="$(state_get started_at_utc)"
    elapsed="$(seconds_since_utc "${started}")"
    if (( elapsed >= MAX_RUNTIME_HOURS * 3600 )); then
      set_stop BUDGET_STOP
      log_event warn supervisor_budget "Runtime budget exceeded"
      break
    fi

    sleep "${POLL_INTERVAL_SECONDS}"
  done

  local reason
  reason="$(state_get stop_reason NONE)"

  local pid
  pid="$(read_pid "${AI1_PID_FILE}" 2>/dev/null || true)"
  pid_alive "${pid}" && kill "${pid}" >/dev/null 2>&1 || true
  pid="$(read_pid "${AI2_PID_FILE}" 2>/dev/null || true)"
  pid_alive "${pid}" && kill "${pid}" >/dev/null 2>&1 || true

  state_set status "${reason}"
  write_final_summary "${reason}"
  log_event info supervisor_stop "Supervisor stopped with reason=${reason}"

  remove_pid_files
}

main() {
  local cmd="${1:-}"
  local dry_run=0
  [[ "${2:-}" == "--dry-run" ]] && dry_run=1

  case "${cmd}" in
    start)
      cmd_start "${dry_run}"
      ;;
    resume)
      cmd_resume "${dry_run}"
      ;;
    status)
      cmd_status
      ;;
    stop)
      cmd_stop
      ;;
    supervise)
      cmd_supervise
      ;;
    *)
      usage
      exit 2
      ;;
  esac
}

main "$@"
