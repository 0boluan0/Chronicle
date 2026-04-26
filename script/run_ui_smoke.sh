#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/Chronicle.xcodeproj"
SCHEME="ChronicleUISmoke"
DESTINATION="platform=macOS"
DERIVED_DATA="${ROOT_DIR}/build/ui-smoke"
RESULTS_DIR="${ROOT_DIR}/build/ui-smoke-results"

LANGUAGE="${1:-all}"

automation_status() {
  automationmodetool 2>&1 || true
}

require_automation_mode() {
  local status
  status="$(automation_status)"

  if [[ "$status" == *"requires user authentication"* ]]; then
    cat >&2 <<EOF
UI smoke tests require Automation Mode to be available without per-run authentication.

Current status:
$status

Run this once on the dedicated test machine as an administrator:
  sudo automationmodetool enable-automationmode-without-authentication
EOF
    exit 2
  fi
}

cleanup_processes() {
  pkill -f "ChronicleUITests-Runner" >/dev/null 2>&1 || true
  pkill -x "Chronicle" >/dev/null 2>&1 || true
}

run_case() {
  local language="$1"
  local test_name
  local result_bundle

  case "$language" in
    en)
      test_name="ChronicleUITests/ChronicleUITests/testEnglishPublicBetaSmoke"
      ;;
    zh-Hans)
      test_name="ChronicleUITests/ChronicleUITests/testChinesePublicBetaSmoke"
      ;;
    *)
      echo "unsupported language: $language" >&2
      exit 2
      ;;
  esac

  cleanup_processes
  mkdir -p "$RESULTS_DIR"
  result_bundle="${RESULTS_DIR}/${language}.xcresult"
  rm -rf "$result_bundle"

  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -resultBundlePath "$result_bundle" \
    -only-testing:"$test_name" \
    test
}

require_automation_mode

case "$LANGUAGE" in
  all)
    run_case en
    run_case zh-Hans
    ;;
  en|zh-Hans)
    run_case "$LANGUAGE"
    ;;
  *)
    echo "usage: $0 [all|en|zh-Hans]" >&2
    exit 2
    ;;
esac
