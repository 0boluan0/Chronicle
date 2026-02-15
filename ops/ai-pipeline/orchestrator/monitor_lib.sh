#!/usr/bin/env bash

set -euo pipefail

RED_BG_BOLD=$'\033[41;97m'
YELLOW_BOLD=$'\033[33;1m'
GREEN_BOLD=$'\033[32;1m'
BLUE_BOLD=$'\033[34;1m'
DIM=$'\033[2m'
RESET=$'\033[0m'

read_yaml_value() {
  local file="$1"
  local key="$2"
  local default_value="${3:-}"
  if [[ ! -f "${file}" ]]; then
    echo "${default_value}"
    return 0
  fi
  local value
  value="$(awk -v k="${key}" '
    $1 == k":" {
      $1 = ""
      sub(/^ /, "", $0)
      print
      found = 1
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "${file}" 2>/dev/null || true)"
  if [[ -n "${value}" ]]; then
    echo "${value}"
  else
    echo "${default_value}"
  fi
}

read_pid_file() {
  local file="$1"
  [[ -f "${file}" ]] || return 0
  tr -d '[:space:]' < "${file}"
}

pid_state() {
  local pid="${1:-}"
  if [[ -z "${pid}" ]]; then
    echo "n/a"
    return 0
  fi
  if kill -0 "${pid}" >/dev/null 2>&1; then
    echo "alive"
  else
    echo "dead"
  fi
}

latest_file_by_glob() {
  local pattern="$1"
  ls -1t ${pattern} 2>/dev/null | head -n 1
}

seconds_since_utc() {
  local utc_ts="${1:-}"
  python3 - "${utc_ts}" <<'PY'
from datetime import datetime, timezone
import sys

raw = sys.argv[1].strip()
if not raw:
    print(-1)
    raise SystemExit(0)

try:
    dt = datetime.strptime(raw, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
except ValueError:
    print(-1)
    raise SystemExit(0)

now = datetime.now(timezone.utc)
print(int((now - dt).total_seconds()))
PY
}

format_duration() {
  local secs="${1:-0}"
  if [[ -z "${secs}" || "${secs}" == "-1" ]]; then
    echo "--:--:--"
    return 0
  fi
  if (( secs < 0 )); then
    echo "--:--:--"
    return 0
  fi
  local h m s
  h=$((secs / 3600))
  m=$(((secs % 3600) / 60))
  s=$((secs % 60))
  printf "%02d:%02d:%02d" "${h}" "${m}" "${s}"
}

latest_event_line() {
  local events_file="${1:-}"
  [[ -f "${events_file}" ]] || return 0
  tail -n 1 "${events_file}" 2>/dev/null || true
}

latest_event_field() {
  local events_file="$1"
  local field="$2"
  local line
  line="$(latest_event_line "${events_file}")"
  [[ -n "${line}" ]] || return 0
  echo "${line}" | jq -r --arg f "${field}" '.[$f] // empty' 2>/dev/null || true
}

latest_event_compact() {
  local events_file="$1"
  local line
  line="$(latest_event_line "${events_file}")"
  if [[ -z "${line}" ]]; then
    echo "N/A"
    return 0
  fi
  echo "${line}" | jq -r '
    [
      (.timestamp // "N/A"),
      "[" + (.level // "info") + "]",
      (.event // "event"),
      ("task=" + (.task_id // "NONE")),
      ("cycle=" + ((.cycle // "0")|tostring)),
      (.message // "")
    ] | join(" ")
  ' 2>/dev/null || echo "${line}"
}

render_events_tail() {
  local events_file="$1"
  local line_count="$2"
  if [[ ! -f "${events_file}" ]]; then
    echo "(no event file)"
    return 0
  fi
  tail -n "${line_count}" "${events_file}" | jq -r '
    [
      (.timestamp // "N/A"),
      "[" + (.level // "info") + "]",
      (.event // "event"),
      ("task=" + (.task_id // "NONE")),
      ("cycle=" + ((.cycle // "0")|tostring)),
      (.message // "")
    ] | join(" ")
  ' 2>/dev/null || tail -n "${line_count}" "${events_file}"
}

render_log_tail() {
  local log_file="$1"
  local line_count="$2"
  if [[ ! -f "${log_file}" ]]; then
    echo "(missing) ${log_file}"
    return 0
  fi
  tail -n "${line_count}" "${log_file}"
}

