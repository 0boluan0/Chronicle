#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/Chronicle.xcodeproj"
SCHEME="ChronicleUISmoke"
DESTINATION="platform=macOS"
DERIVED_DATA="${ROOT_DIR}/build/ui-smoke"
RESULTS_DIR="${ROOT_DIR}/build/ui-smoke-results"
UI_SMOKE_TIMEOUT_SECONDS="${UI_SMOKE_TIMEOUT_SECONDS:-1800}"

LANGUAGE="${1:-all}"

PUBLIC_TESTS_EN=(
  "ChronicleUITests/ChronicleUITests/testEnglishPublicBetaSmoke"
)

PUBLIC_TESTS_ZH_HANS=(
  "ChronicleUITests/ChronicleUITests/testChinesePublicBetaSmoke"
)

SURFACE_TESTS_EN=(
  "ChronicleUITests/ChronicleUITests/testTagsPreferencesClassificationSurfaceSmoke"
  "ChronicleUITests/ChronicleUITests/testTagWizardReviewSurfaceSmoke"
  "ChronicleUITests/ChronicleUITests/testAppMappingsReviewWorkspaceSmoke"
  "ChronicleUITests/ChronicleUITests/testQuickMarkerPanelGuidanceSmoke"
  "ChronicleUITests/ChronicleUITests/testPopoverNextActionCardSmoke"
  "ChronicleUITests/ChronicleUITests/testDashboardOverviewReviewBriefSmoke"
  "ChronicleUITests/ChronicleUITests/testDashboardTimelineReviewFocusSmoke"
  "ChronicleUITests/ChronicleUITests/testDashboardMarkersReviewNotesSmoke"
  "ChronicleUITests/ChronicleUITests/testDashboardStatsInsightsSmoke"
  "ChronicleUITests/ChronicleUITests/testDashboardDebugFlowSmoke"
  "ChronicleUITests/ChronicleUITests/testDashboardReportsCloseoutSmoke"
  "ChronicleUITests/ChronicleUITests/testReportsReviewPlanSmoke"
  "ChronicleUITests/ChronicleUITests/testPrivacyTrustSurfaceSmoke"
  "ChronicleUITests/ChronicleUITests/testDebugPreferencesDiagnosticsSurfaceSmoke"
  "ChronicleUITests/ChronicleUITests/testSupportReadinessReportSmoke"
  "ChronicleUITests/ChronicleUITests/testGeneralSetupSurfaceSmoke"
  "ChronicleUITests/ChronicleUITests/testOnboardingGuidedSetupSurfaceSmoke"
)

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

usage() {
  echo "usage: $0 [all|public|full|surface|en|zh-Hans]" >&2
  echo "env: UI_SMOKE_TIMEOUT_SECONDS=<seconds> (default: 1800, 0 disables)" >&2
}

validate_timeout() {
  case "$UI_SMOKE_TIMEOUT_SECONDS" in
    ''|*[!0-9]*)
      echo "UI_SMOKE_TIMEOUT_SECONDS must be a non-negative integer." >&2
      exit 2
      ;;
  esac
}

run_with_timeout() {
  local timeout_seconds="$1"
  shift

  if [ "$timeout_seconds" -eq 0 ]; then
    "$@"
    return
  fi

  "$@" &
  local command_pid=$!
  local watchdog_pid
  local status=0

  (
    sleep "$timeout_seconds"
    if kill -0 "$command_pid" >/dev/null 2>&1; then
      echo "UI smoke timed out after ${timeout_seconds}s; stopping xcodebuild." >&2
      kill -TERM "$command_pid" >/dev/null 2>&1 || true
      cleanup_processes
      sleep 5
      kill -KILL "$command_pid" >/dev/null 2>&1 || true
    fi
  ) &
  watchdog_pid=$!

  wait "$command_pid" || status=$?
  kill "$watchdog_pid" >/dev/null 2>&1 || true
  wait "$watchdog_pid" >/dev/null 2>&1 || true

  return "$status"
}

run_case() {
  local language="$1"
  local scope="$2"
  local result_bundle
  shift 2
  local tests=("$@")
  local only_testing_args=()

  if [ "${#tests[@]}" -eq 0 ]; then
    echo "no tests configured for ${scope}/${language}" >&2
    exit 2
  fi

  for test_name in "${tests[@]}"; do
    only_testing_args+=("-only-testing:${test_name}")
  done

  cleanup_processes
  mkdir -p "$RESULTS_DIR"
  result_bundle="${RESULTS_DIR}/${scope}-${language}.xcresult"
  rm -rf "$result_bundle"

  echo "Running ${scope} UI smoke (${language}) with ${#tests[@]} test(s)."
  echo "Result bundle: ${result_bundle}"
  echo "Timeout: ${UI_SMOKE_TIMEOUT_SECONDS}s per smoke run."

  run_with_timeout "$UI_SMOKE_TIMEOUT_SECONDS" \
    xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -resultBundlePath "$result_bundle" \
    "${only_testing_args[@]}" \
    test
}

case "$LANGUAGE" in
  all|public|full|surface|en|zh-Hans)
    ;;
  *)
    usage
    exit 2
    ;;
esac

validate_timeout

trap cleanup_processes EXIT

require_automation_mode

case "$LANGUAGE" in
  all|public)
    run_case en public "${PUBLIC_TESTS_EN[@]}"
    run_case zh-Hans public "${PUBLIC_TESTS_ZH_HANS[@]}"
    ;;
  full)
    run_case en public "${PUBLIC_TESTS_EN[@]}"
    run_case zh-Hans public "${PUBLIC_TESTS_ZH_HANS[@]}"
    run_case en surface "${SURFACE_TESTS_EN[@]}"
    ;;
  surface)
    run_case en surface "${SURFACE_TESTS_EN[@]}"
    ;;
  en)
    run_case en public "${PUBLIC_TESTS_EN[@]}"
    ;;
  zh-Hans)
    run_case zh-Hans public "${PUBLIC_TESTS_ZH_HANS[@]}"
    ;;
esac
