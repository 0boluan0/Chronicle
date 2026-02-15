#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"
source "${SCRIPT_DIR}/monitor_lib.sh"

ORCHESTRATOR_SH="${SCRIPT_DIR}/orchestrator.sh"
RUNTIME_DIR="${PIPELINE_DIR}/runtime"
STATE_FILE="${RUNTIME_DIR}/state.yaml"
EVENTS_DIR="${RUNTIME_DIR}/events"
LOGS_DIR="${RUNTIME_DIR}/logs"
PIDS_DIR="${RUNTIME_DIR}/pids"

AI1_PID_FILE="${PIDS_DIR}/ai1.pid"
AI2_PID_FILE="${PIDS_DIR}/ai2.pid"
SUP_PID_FILE="${PIDS_DIR}/supervisor.pid"

SHOW_EVENTS=0
SHOW_LOGS=0
SHOW_AI1_LOG=1
SHOW_AI2_LOG=1
SHOW_HELP=0
EVENT_LINES=(10 30 100)
EVENT_LINES_INDEX=0
LOG_LINES=20
REFRESH_SECONDS=1
RUNNING=1

STATUS_LINE="Ready. Press h for help."
STATUS_LEVEL="info"
ALERT_HISTORY="|"
ALERT_BANNER=""

PREV_AI1_STATE="n/a"
PREV_AI2_STATE="n/a"
PREV_SUP_STATE="n/a"

SNAPSHOT_RUN_ID="unknown"
SNAPSHOT_STATUS="UNKNOWN"
SNAPSHOT_CYCLE="0"
SNAPSHOT_TASK_ID="NONE"
SNAPSHOT_STOP_REASON="NONE"
SNAPSHOT_STUCK_COUNT="0"
SNAPSHOT_GOALS=""
SNAPSHOT_COMPLETED=""
SNAPSHOT_RUNTIME="--:--:--"
SNAPSHOT_ELAPSED_SECONDS="-1"
SNAPSHOT_AI1_PID=""
SNAPSHOT_AI2_PID=""
SNAPSHOT_SUP_PID=""
SNAPSHOT_AI1_STATE="n/a"
SNAPSHOT_AI2_STATE="n/a"
SNAPSHOT_SUP_STATE="n/a"
SNAPSHOT_LATEST_EVENT_FILE=""
SNAPSHOT_LATEST_EVENT_LEVEL=""
SNAPSHOT_LATEST_EVENT_COMPACT="N/A"
SNAPSHOT_DRY_RUN="false"
SNAPSHOT_EFFECTIVE_STATUS="UNKNOWN"

safe_value() {
  local raw="${1:-}"
  if [[ -z "${raw}" ]]; then
    echo "N/A"
  else
    echo "${raw}"
  fi
}

count_csv_items() {
  local csv="${1:-}"
  local count=0
  local item
  IFS=',' read -r -a arr <<< "${csv}"
  for item in "${arr[@]}"; do
    [[ -n "${item}" ]] && count=$((count + 1))
  done
  echo "${count}"
}

term_cols() {
  local cols
  cols="$(tput cols 2>/dev/null || echo 100)"
  if [[ -z "${cols}" || ! "${cols}" =~ ^[0-9]+$ ]]; then
    cols=100
  fi
  (( cols < 80 )) && cols=80
  echo "${cols}"
}

term_rows() {
  local rows
  rows="$(tput lines 2>/dev/null || echo 24)"
  if [[ -z "${rows}" || ! "${rows}" =~ ^[0-9]+$ ]]; then
    rows=24
  fi
  (( rows < 18 )) && rows=18
  echo "${rows}"
}

print_hr() {
  local cols="$1"
  printf '%*s\n' "${cols}" '' | tr ' ' '-'
}

truncate_text() {
  local text="$1"
  local max_len="$2"
  if (( max_len <= 3 )); then
    echo "${text}"
    return 0
  fi
  if (( ${#text} <= max_len )); then
    echo "${text}"
  else
    echo "${text:0:$((max_len - 3))}..."
  fi
}

colorize_status() {
  local st="$1"
  case "${st}" in
    SUCCESS_STOP)
      printf "%s%s%s" "${GREEN_BOLD}" "${st}" "${RESET}"
      ;;
    FUSE_STOP|BUDGET_STOP|WORKER_EXIT)
      printf "%s%s%s" "${RED_BG_BOLD}" "${st}" "${RESET}"
      ;;
    STOP_REQUESTED|USER_STOP)
      printf "%s%s%s" "${YELLOW_BOLD}" "${st}" "${RESET}"
      ;;
    AI1_EXECUTE|AI2_BASELINE|AI2_DISPATCH|AI2_VERIFY|RUNNING|BOOTSTRAP)
      printf "%s%s%s" "${BLUE_BOLD}" "${st}" "${RESET}"
      ;;
    *)
      printf "%s" "${st}"
      ;;
  esac
}

colorize_worker_state() {
  local st="$1"
  case "${st}" in
    alive)
      printf "%s%s%s" "${GREEN_BOLD}" "${st}" "${RESET}"
      ;;
    dead)
      printf "%s%s%s" "${RED_BG_BOLD}" "${st}" "${RESET}"
      ;;
    *)
      printf "%s%s%s" "${DIM}" "${st}" "${RESET}"
      ;;
  esac
}

set_status_line() {
  local level="$1"
  shift
  local msg="$*"
  STATUS_LEVEL="${level}"
  STATUS_LINE="$(date '+%H:%M:%S') ${msg}"
}

is_alert_recorded() {
  local key="$1"
  [[ "${ALERT_HISTORY}" == *"|${key}|"* ]]
}

record_alert() {
  local key="$1"
  ALERT_HISTORY="${ALERT_HISTORY}${key}|"
}

run_orchestrator_command() {
  local label="$1"
  shift
  local output exit_code
  set +e
  output="$(bash "${ORCHESTRATOR_SH}" "$@" 2>&1)"
  exit_code=$?
  set -e
  if [[ ${exit_code} -eq 0 ]]; then
    set_status_line success "${label} OK: ${output}"
  else
    set_status_line error "${label} failed(${exit_code}): ${output}"
  fi
}

restart_orchestrator() {
  local dry_run_flag=""
  local dry_run_state
  dry_run_state="$(read_yaml_value "${STATE_FILE}" dry_run false)"
  if [[ "${dry_run_state}" == "true" ]]; then
    dry_run_flag="--dry-run"
  fi

  run_orchestrator_command "stop" stop
  sleep 1
  if [[ -n "${dry_run_flag}" ]]; then
    run_orchestrator_command "start" start "${dry_run_flag}"
  else
    run_orchestrator_command "start" start
  fi
}

find_ai1_log() {
  local file
  file="$(latest_file_by_glob "${LOGS_DIR}/ai1-cycle-*.log")"
  if [[ -n "${file}" ]]; then
    echo "${file}"
    return 0
  fi
  echo "${LOGS_DIR}/ai1-worker.log"
}

find_ai2_log() {
  local file
  file="$(latest_file_by_glob "${LOGS_DIR}/ai2-baseline-*-cycle-*.log")"
  if [[ -n "${file}" ]]; then
    echo "${file}"
    return 0
  fi
  echo "${LOGS_DIR}/ai2-worker.log"
}

capture_snapshot() {
  SNAPSHOT_RUN_ID="$(read_yaml_value "${STATE_FILE}" run_id unknown)"
  SNAPSHOT_STATUS="$(read_yaml_value "${STATE_FILE}" status UNKNOWN)"
  SNAPSHOT_CYCLE="$(read_yaml_value "${STATE_FILE}" cycle 0)"
  SNAPSHOT_TASK_ID="$(read_yaml_value "${STATE_FILE}" current_task_id NONE)"
  SNAPSHOT_STOP_REASON="$(read_yaml_value "${STATE_FILE}" stop_reason NONE)"
  SNAPSHOT_STUCK_COUNT="$(read_yaml_value "${STATE_FILE}" stuck_count 0)"
  SNAPSHOT_GOALS="$(read_yaml_value "${STATE_FILE}" goal_task_ids "")"
  SNAPSHOT_COMPLETED="$(read_yaml_value "${STATE_FILE}" completed_goal_ids "")"
  SNAPSHOT_DRY_RUN="$(read_yaml_value "${STATE_FILE}" dry_run false)"

  local started_at
  started_at="$(read_yaml_value "${STATE_FILE}" started_at_utc "")"
  SNAPSHOT_ELAPSED_SECONDS="$(seconds_since_utc "${started_at}")"
  SNAPSHOT_RUNTIME="$(format_duration "${SNAPSHOT_ELAPSED_SECONDS}")"

  SNAPSHOT_AI1_PID="$(read_pid_file "${AI1_PID_FILE}")"
  SNAPSHOT_AI2_PID="$(read_pid_file "${AI2_PID_FILE}")"
  SNAPSHOT_SUP_PID="$(read_pid_file "${SUP_PID_FILE}")"
  SNAPSHOT_AI1_STATE="$(pid_state "${SNAPSHOT_AI1_PID}")"
  SNAPSHOT_AI2_STATE="$(pid_state "${SNAPSHOT_AI2_PID}")"
  SNAPSHOT_SUP_STATE="$(pid_state "${SNAPSHOT_SUP_PID}")"

  SNAPSHOT_LATEST_EVENT_FILE="$(latest_file_by_glob "${EVENTS_DIR}/events-*.jsonl")"
  SNAPSHOT_LATEST_EVENT_LEVEL="$(latest_event_field "${SNAPSHOT_LATEST_EVENT_FILE}" level)"
  SNAPSHOT_LATEST_EVENT_COMPACT="$(latest_event_compact "${SNAPSHOT_LATEST_EVENT_FILE}")"

  SNAPSHOT_EFFECTIVE_STATUS="${SNAPSHOT_STATUS}"
  if [[ "${SNAPSHOT_AI1_STATE}" != "alive" && "${SNAPSHOT_AI2_STATE}" != "alive" && "${SNAPSHOT_SUP_STATE}" != "alive" ]]; then
    case "${SNAPSHOT_STATUS}" in
      SUCCESS_STOP|FUSE_STOP|BUDGET_STOP|USER_STOP|WORKER_EXIT|STOP_REQUESTED)
        ;;
      *)
        SNAPSHOT_EFFECTIVE_STATUS="NOT_RUNNING"
        ;;
    esac
  fi
}

process_alert_candidate() {
  local key="$1"
  local message="$2"
  ALERT_BANNER="${message}"
  if ! is_alert_recorded "${key}"; then
    record_alert "${key}"
    printf '\a'
    set_status_line alert "ALERT: ${message}"
  fi
}

evaluate_alerts() {
  ALERT_BANNER=""

  case "${SNAPSHOT_EFFECTIVE_STATUS}" in
    WORKER_EXIT|FUSE_STOP|BUDGET_STOP)
      process_alert_candidate "status:${SNAPSHOT_EFFECTIVE_STATUS}" "state.status=${SNAPSHOT_EFFECTIVE_STATUS}"
      ;;
  esac

  if [[ "${SNAPSHOT_LATEST_EVENT_LEVEL}" == "error" ]]; then
    process_alert_candidate "event:error:${SNAPSHOT_CYCLE}" "latest event level=error"
  fi

  if [[ "${PREV_AI1_STATE}" == "alive" && "${SNAPSHOT_AI1_STATE}" == "dead" ]]; then
    process_alert_candidate "worker:ai1_dead" "AI1 transitioned alive -> dead"
  fi
  if [[ "${PREV_AI2_STATE}" == "alive" && "${SNAPSHOT_AI2_STATE}" == "dead" ]]; then
    process_alert_candidate "worker:ai2_dead" "AI2 transitioned alive -> dead"
  fi
  if [[ "${PREV_SUP_STATE}" == "alive" && "${SNAPSHOT_SUP_STATE}" == "dead" ]]; then
    process_alert_candidate "worker:supervisor_dead" "Supervisor transitioned alive -> dead"
  fi

  PREV_AI1_STATE="${SNAPSHOT_AI1_STATE}"
  PREV_AI2_STATE="${SNAPSHOT_AI2_STATE}"
  PREV_SUP_STATE="${SNAPSHOT_SUP_STATE}"
}

print_status_line() {
  case "${STATUS_LEVEL}" in
    success)
      printf "%s%s%s\n" "${GREEN_BOLD}" "${STATUS_LINE}" "${RESET}"
      ;;
    error|alert)
      printf "%s%s%s\n" "${RED_BG_BOLD}" "${STATUS_LINE}" "${RESET}"
      ;;
    warn)
      printf "%s%s%s\n" "${YELLOW_BOLD}" "${STATUS_LINE}" "${RESET}"
      ;;
    *)
      printf "%s\n" "${STATUS_LINE}"
      ;;
  esac
}

render_help() {
  printf "%sKeys:%s s=stop u=resume r=restart q=quit 1=events 2=logs a=ai1-log b=ai2-log n=event-lines h=help\n" "${BLUE_BOLD}" "${RESET}"
}

render_screen() {
  local cols
  cols="$(term_cols)"
  local rows
  rows="$(term_rows)"
  local goals completed goals_count completed_count completion_ratio
  goals="$(safe_value "${SNAPSHOT_GOALS}")"
  completed="$(safe_value "${SNAPSHOT_COMPLETED}")"
  goals_count="$(count_csv_items "${SNAPSHOT_GOALS}")"
  completed_count="$(count_csv_items "${SNAPSHOT_COMPLETED}")"
  if (( goals_count > 0 )); then
    completion_ratio="${completed_count}/${goals_count}"
  else
    completion_ratio="N/A"
  fi

  printf '\033[2J\033[H'
  printf "%sChronicle Orchestrator Monitor%s  %s\n" "${BLUE_BOLD}" "${RESET}" "$(date '+%Y-%m-%d %H:%M:%S')"
  print_hr "${cols}"
  printf "Run: %s\n" "$(truncate_text "$(safe_value "${SNAPSHOT_RUN_ID}")" $((cols - 6)))"
  printf "Status: %b | Cycle: %s | Task: %s | Stop: %s\n" \
    "$(colorize_status "${SNAPSHOT_EFFECTIVE_STATUS}")" \
    "$(safe_value "${SNAPSHOT_CYCLE}")" \
    "$(safe_value "${SNAPSHOT_TASK_ID}")" \
    "$(safe_value "${SNAPSHOT_STOP_REASON}")"
  printf "Workers: AI1 %s(%b) | AI2 %s(%b) | SUP %s(%b)\n" \
    "$(safe_value "${SNAPSHOT_AI1_PID}")" "$(colorize_worker_state "${SNAPSHOT_AI1_STATE}")" \
    "$(safe_value "${SNAPSHOT_AI2_PID}")" "$(colorize_worker_state "${SNAPSHOT_AI2_STATE}")" \
    "$(safe_value "${SNAPSHOT_SUP_PID}")" "$(colorize_worker_state "${SNAPSHOT_SUP_STATE}")"
  printf "Progress: goals %s | completed %s | ratio %s | stuck %s/%s | runtime %s | dry-run %s\n" \
    "${goals}" "${completed}" "${completion_ratio}" "${SNAPSHOT_STUCK_COUNT}" "${STUCK_THRESHOLD}" "${SNAPSHOT_RUNTIME}" "${SNAPSHOT_DRY_RUN}"
  printf "Latest: %s\n" "$(truncate_text "${SNAPSHOT_LATEST_EVENT_COMPACT}" $((cols - 8)))"

  if [[ -n "${ALERT_BANNER}" ]]; then
    printf "%sALERT: %s%s\n" "${RED_BG_BOLD}" "${ALERT_BANNER}" "${RESET}"
  fi

  print_hr "${cols}"
  printf "Panels: Events[%s] Logs[%s] AI1-log[%s] AI2-log[%s]\n" \
    "$( (( SHOW_EVENTS == 1 )) && echo open || echo folded )" \
    "$( (( SHOW_LOGS == 1 )) && echo open || echo folded )" \
    "$( (( SHOW_AI1_LOG == 1 )) && echo open || echo folded )" \
    "$( (( SHOW_AI2_LOG == 1 )) && echo open || echo folded )"

  local max_events=3
  local max_log_lines=2
  if (( rows >= 34 )); then
    max_events=8
    max_log_lines=6
  elif (( rows >= 28 )); then
    max_events=5
    max_log_lines=3
  fi

  if (( SHOW_EVENTS == 1 )); then
    local events_n
    events_n="${EVENT_LINES[EVENT_LINES_INDEX]}"
    if (( events_n > max_events )); then
      events_n="${max_events}"
    fi
    printf "%s[Events last %s]%s\n" "${BLUE_BOLD}" "${events_n}" "${RESET}"
    render_events_tail "${SNAPSHOT_LATEST_EVENT_FILE}" "${events_n}"
  else
    printf "%s[Events]%s folded (press 1)\n" "${DIM}" "${RESET}"
  fi

  if (( SHOW_LOGS == 1 )); then
    printf "%s[Logs]%s\n" "${BLUE_BOLD}" "${RESET}"

    if (( SHOW_AI1_LOG == 1 )); then
      local ai1_log
      ai1_log="$(find_ai1_log)"
      printf "%sAI1:%s %s\n" "${YELLOW_BOLD}" "${RESET}" "$(truncate_text "${ai1_log}" $((cols - 6)))"
      render_log_tail "${ai1_log}" "${max_log_lines}"
    else
      printf "%sAI1 log folded (press a)%s\n" "${DIM}" "${RESET}"
    fi

    if (( SHOW_AI2_LOG == 1 )); then
      local ai2_log
      ai2_log="$(find_ai2_log)"
      printf "%sAI2:%s %s\n" "${YELLOW_BOLD}" "${RESET}" "$(truncate_text "${ai2_log}" $((cols - 6)))"
      render_log_tail "${ai2_log}" "${max_log_lines}"
    else
      printf "%sAI2 log folded (press b)%s\n" "${DIM}" "${RESET}"
    fi
  else
    printf "%s[Logs]%s folded (press 2)\n" "${DIM}" "${RESET}"
  fi

  if (( SHOW_HELP == 1 )); then
    render_help
  fi

  print_hr "${cols}"
  print_status_line
}

handle_key() {
  local key="$1"
  case "${key}" in
    q)
      set_status_line info "Quit monitor."
      RUNNING=0
      ;;
    h)
      SHOW_HELP=$((1 - SHOW_HELP))
      set_status_line info "Help panel toggled."
      ;;
    1)
      SHOW_EVENTS=$((1 - SHOW_EVENTS))
      set_status_line info "Events panel toggled."
      ;;
    2)
      SHOW_LOGS=$((1 - SHOW_LOGS))
      set_status_line info "Logs panel toggled."
      ;;
    a)
      SHOW_AI1_LOG=$((1 - SHOW_AI1_LOG))
      set_status_line info "AI1 log panel toggled."
      ;;
    b)
      SHOW_AI2_LOG=$((1 - SHOW_AI2_LOG))
      set_status_line info "AI2 log panel toggled."
      ;;
    n)
      EVENT_LINES_INDEX=$(((EVENT_LINES_INDEX + 1) % 3))
      set_status_line info "Events line count set to ${EVENT_LINES[EVENT_LINES_INDEX]}."
      ;;
    s)
      run_orchestrator_command "stop" stop
      ;;
    u)
      run_orchestrator_command "resume" resume
      ;;
    r)
      restart_orchestrator
      ;;
  esac
}

cleanup_terminal() {
  tput cnorm 2>/dev/null || true
}

main() {
  trap cleanup_terminal EXIT INT TERM
  tput civis 2>/dev/null || true

  while (( RUNNING == 1 )); do
    capture_snapshot
    evaluate_alerts
    render_screen

    local ticks
    ticks="${REFRESH_SECONDS}"
    for ((i = 0; i < ticks; i++)); do
      if read -rsn1 -t 1 key; then
        handle_key "${key}"
        break
      fi
      if (( RUNNING == 0 )); then
        break
      fi
    done
  done
}

main "$@"
