#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PIPELINE_DIR}/../.." && pwd)"

NEXT_COMMAND_FILE="${PIPELINE_DIR}/commands/next_command.md"
DISPATCH_DIR="${PIPELINE_DIR}/dispatch"
RUNS_DIR="${DISPATCH_DIR}/runs"
LATEST_MD="${DISPATCH_DIR}/latest_dispatch.md"

DRY_RUN=0
MODEL_ARG=""

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--dry-run] [--model <model_name>]

Options:
  --dry-run         Print what would be dispatched, do not call codex
  --model <name>    Optional model name passed to codex
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --model)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --model"
        exit 2
      fi
      MODEL_ARG="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 2
      ;;
  esac
done

if [[ ! -f "${NEXT_COMMAND_FILE}" ]]; then
  echo "Missing next command file: ${NEXT_COMMAND_FILE}"
  exit 1
fi

mkdir -p "${RUNS_DIR}"

STAMP="$(date +"%Y%m%d-%H%M%S")"
NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
RUN_LOG="${RUNS_DIR}/dispatch-${STAMP}.log"

TASK_ID="$(rg -o "Task [A-Za-z0-9_-]+" "${NEXT_COMMAND_FILE}" | head -n 1 | awk '{print $2}' || true)"
if [[ -z "${TASK_ID}" ]]; then
  TASK_ID="UNKNOWN"
fi

NEXT_CONTENT="$(cat "${NEXT_COMMAND_FILE}")"
PROMPT_FILE="$(mktemp "${RUNS_DIR}/prompt-${STAMP}-XXXXXX.txt")"
cat > "${PROMPT_FILE}" <<PROMPT_EOF
You are Codex AI1 Builder. Execute exactly the dispatch contract below.

Hard constraints:
- Follow only: ${NEXT_COMMAND_FILE}
- Do not work outside Scope In
- Do not start feature work if this is a stabilization task
- Run required tests listed by the command
- In your final response include:
  - Changed files
  - Test commands executed and results
  - Acceptance criteria checklist

Dispatch task content:

${NEXT_CONTENT}
PROMPT_EOF
PROMPT="$(cat "${PROMPT_FILE}")"
rm -f "${PROMPT_FILE}"

cat > "${LATEST_MD}" <<MD
# Latest Dispatch

- Time (UTC): ${NOW_UTC}
- Task ID: ${TASK_ID}
- Next Command: \
  \
  \
  ${NEXT_COMMAND_FILE}
- Run Log: \
  \
  \
  ${RUN_LOG}
- Dry Run: ${DRY_RUN}
MD

if [[ "${DRY_RUN}" -eq 1 ]]; then
  {
    echo "[dry-run] would dispatch task: ${TASK_ID}"
    echo "[dry-run] command file: ${NEXT_COMMAND_FILE}"
    echo "[dry-run] repo root: ${REPO_ROOT}"
    if [[ -n "${MODEL_ARG}" ]]; then
      echo "[dry-run] model: ${MODEL_ARG}"
    fi
  } | tee "${RUN_LOG}"
  exit 0
fi

CODEX_CMD=(codex exec -C "${REPO_ROOT}" --sandbox danger-full-access)
if [[ -n "${MODEL_ARG}" ]]; then
  CODEX_CMD+=(--model "${MODEL_ARG}")
fi

{
  echo "[dispatch] task=${TASK_ID}"
  echo "[dispatch] started_utc=${NOW_UTC}"
  echo "[dispatch] invoking codex..."
} | tee "${RUN_LOG}"

set +e
"${CODEX_CMD[@]}" "${PROMPT}" 2>&1 | tee -a "${RUN_LOG}"
CODEX_EXIT=${PIPESTATUS[0]}
set -e

{
  echo "[dispatch] codex_exit=${CODEX_EXIT}"
  echo "[dispatch] finished_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
} | tee -a "${RUN_LOG}"

exit "${CODEX_EXIT}"
