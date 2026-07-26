#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/Chronicle.xcodeproj"
SCHEME="ChronicleUISmoke"
DESTINATION="platform=macOS"
DERIVED_DATA="${ROOT_DIR}/build/ui-smoke"
RESULTS_DIR="${ROOT_DIR}/build/ui-smoke-results"
UI_SMOKE_TIMEOUT_SECONDS="${UI_SMOKE_TIMEOUT_SECONDS:-1800}"
UI_SMOKE_CLONED_SOURCE_PACKAGES_DIR="${UI_SMOKE_CLONED_SOURCE_PACKAGES_DIR:-}"
UI_TEST_DEFAULTS_PREFIX="com.Chronicle.Chronicle.ui-tests."
UI_TEST_PREFERENCES_DIR="${HOME}/Library/Preferences"
UI_TEST_DEFAULTS_SEEN_DOMAINS=()

LANGUAGE="${1:-all}"

PUBLIC_TESTS_EN=(
  "ChronicleUITests/ChronicleUITests/testEnglishPublicBetaSmoke"
)

PUBLIC_TESTS_ZH_HANS=(
  "ChronicleUITests/ChronicleUITests/testChinesePublicBetaSmoke"
)

SURFACE_TESTS=(
  "ChronicleUITests/ChronicleUITests/testTagsPreferencesClassificationSurfaceSmoke"
  "ChronicleUITests/ChronicleUITests/testTagWizardReviewSurfaceSmoke"
  "ChronicleUITests/ChronicleUITests/testAppMappingsReviewWorkspaceSmoke"
  "ChronicleUITests/ChronicleUITests/testQuickMarkerPanelGuidanceSmoke"
  "ChronicleUITests/ChronicleUITests/testPopoverControllerSmoke"
  "ChronicleUITests/ChronicleUITests/testArchiveStartupFailureRecoverySurfaceSmoke"
  "ChronicleUITests/ChronicleUITests/testDashboardPendingReviewSmoke"
  "ChronicleUITests/ChronicleUITests/testDashboardWorkBlockTimelineSmoke"
  "ChronicleUITests/ChronicleUITests/testDashboardNotesLibrarySmoke"
  "ChronicleUITests/ChronicleUITests/testDashboardWorkBlockInsightsSmoke"
  "ChronicleUITests/ChronicleUITests/testDashboardExportIntegrationsSmoke"
  "ChronicleUITests/ChronicleUITests/testLegacySettingsExportRouteRedirectsToIntegrations"
  "ChronicleUITests/ChronicleUITests/testGeneralSetupSurfaceSmoke"
  "ChronicleUITests/ChronicleUITests/testPrivacyTrustSurfaceSmoke"
  "ChronicleUITests/ChronicleUITests/testSupportReadinessReportSmoke"
  "ChronicleUITests/ChronicleUITests/testSupportHealthRouteOpensReportSmoke"
  "ChronicleUITests/ChronicleUITests/testOnboardingGuidedSetupSurfaceSmoke"
  "ChronicleUITests/ChronicleUITests/testReportFolderPickerPresentsSystemSheet"
  "ChronicleUITests/ChronicleUITests/testExportBookmarksAndLastRunStatusRestoreAcrossRelaunch"
)

require_automation_mode() {
  local status
  local automation_status_code
  local normalized
  local unknown_lines
  local is_enabled=false
  local is_disabled=false
  local allows_without_auth=false
  local requires_auth=false

  if ! command -v automationmodetool >/dev/null 2>&1; then
    echo "automationmodetool is unavailable; refusing to run UI smoke tests without a verified Automation Mode status." >&2
    exit 2
  fi

  automation_status_code=0
  status="$(automationmodetool 2>&1)" || automation_status_code=$?
  if [ "$automation_status_code" -ne 0 ]; then
    cat >&2 <<EOF
Could not verify Automation Mode; automationmodetool exited with status ${automation_status_code}.

Output:
$status
EOF
    exit 2
  fi

  normalized="$(
    printf '%s\n' "$status" |
      tr '[:upper:]' '[:lower:]' |
      sed -e 's/\r$//' -e '/^[[:space:]]*$/d'
  )"
  unknown_lines="$(
    printf '%s\n' "$normalized" |
      grep -Ev '^(automation mode is (enabled|disabled)\.|this device (does not require|requires) user authentication to enable automation mode\.)$' || true
  )"

  [ -n "$normalized" ] || {
    echo "automationmodetool returned no status; refusing to run UI smoke tests." >&2
    exit 2
  }
  [ -z "$unknown_lines" ] || {
    cat >&2 <<EOF
automationmodetool returned an unrecognized status; refusing to run UI smoke tests.

Output:
$status
EOF
    exit 2
  }

  grep -Fxq 'automation mode is enabled.' <<<"$normalized" && is_enabled=true
  grep -Fxq 'automation mode is disabled.' <<<"$normalized" && is_disabled=true
  grep -Fxq 'this device does not require user authentication to enable automation mode.' <<<"$normalized" && allows_without_auth=true
  grep -Fxq 'this device requires user authentication to enable automation mode.' <<<"$normalized" && requires_auth=true

  if [ "$requires_auth" = true ]; then
    cat >&2 <<EOF
UI smoke tests require Automation Mode to be available without per-run authentication.

Current status:
$status

Run this once on the dedicated test machine as an administrator:
  sudo automationmodetool enable-automationmode-without-authentication
EOF
    exit 2
  fi

  if [ "$is_enabled" = true ] && [ "$is_disabled" = false ]; then
    echo "Automation Mode is enabled; continuing with UI smoke tests."
    return
  fi

  if [ "$is_disabled" = true ] &&
     [ "$is_enabled" = false ] &&
     [ "$allows_without_auth" = true ]; then
    cat >&2 <<EOF
Automation Mode is currently disabled, but this machine allows XCTest to enable it without authentication.
Continuing; xcodebuild will request Automation Mode when the UI smoke runner starts.
EOF
    return
  fi

  cat >&2 <<EOF
Automation Mode status is incomplete or contradictory; refusing to run UI smoke tests.

Output:
$status
EOF
  exit 2
}

cleanup_processes() {
  local runner_pattern="${DERIVED_DATA}/Build/Products/.*/ChronicleUITests-Runner.app/Contents/MacOS/ChronicleUITests-Runner"
  local target_pattern="${DERIVED_DATA}/Build/Products/.*/Chronicle.app/Contents/MacOS/Chronicle"

  pkill -f "$runner_pattern" >/dev/null 2>&1 || true
  pkill -f "$target_pattern" >/dev/null 2>&1 || true

  local attempt=0
  while pgrep -f "$runner_pattern" >/dev/null 2>&1 ||
        pgrep -f "$target_pattern" >/dev/null 2>&1; do
    if [ "$attempt" -ge 50 ]; then
      echo "Chronicle UI-test processes did not stop; refusing preferences cleanup." >&2
      return 1
    fi
    sleep 0.1
    attempt=$((attempt + 1))
  done
}

list_ui_test_defaults_paths() {
  find "$UI_TEST_PREFERENCES_DIR" \
    -maxdepth 1 \
    -mindepth 1 \
    -name "${UI_TEST_DEFAULTS_PREFIX}*.plist" \
    -print |
    LC_ALL=C sort
}

remember_ui_test_defaults_domain() {
  local candidate="$1"
  local existing

  if [ "${#UI_TEST_DEFAULTS_SEEN_DOMAINS[@]}" -ne 0 ]; then
    for existing in "${UI_TEST_DEFAULTS_SEEN_DOMAINS[@]}"; do
      [ "$existing" = "$candidate" ] && return 0
    done
  fi
  UI_TEST_DEFAULTS_SEEN_DOMAINS+=("$candidate")
}

prepare_ui_test_defaults() {
  if [ ! -d "$UI_TEST_PREFERENCES_DIR" ] || [ -L "$UI_TEST_PREFERENCES_DIR" ]; then
    echo "UI-test preferences directory is missing or unsafe: $UI_TEST_PREFERENCES_DIR" >&2
    return 1
  fi

  UI_TEST_PREFERENCES_DIR="$(cd "$UI_TEST_PREFERENCES_DIR" && pwd -P)"
  UI_TEST_DEFAULTS_SEEN_DOMAINS=()
  cleanup_ui_test_defaults_until_stable
  echo "UI-test preferences pre-run baseline verified empty."
}

validate_new_ui_test_defaults_path() {
  local path="$1"
  local parent
  local basename
  local domain

  parent="$(dirname "$path")"
  basename="$(basename "$path")"
  domain="${basename%.plist}"

  if [ "$parent" != "$UI_TEST_PREFERENCES_DIR" ] ||
     [ "$basename" != "${domain}.plist" ] ||
     [[ ! "$domain" =~ ^com[.]Chronicle[.]Chronicle[.]ui-tests[.]chronicle-ui-tests-(en|zh-Hans)-[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] ||
     [ -L "$path" ] ||
     [ ! -f "$path" ]; then
    echo "Refusing unsafe UI-test preferences cleanup target: $path" >&2
    return 1
  fi
}

cleanup_ui_test_defaults_until_stable() {
  local matching_paths=()
  local remaining_paths=()
  local path
  local basename
  local domain
  local attempt=0
  local stable_passes=0
  local readable_domain=false
  local removed_count=0

  while [ "$attempt" -lt 20 ]; do
    attempt=$((attempt + 1))
    matching_paths=()
    while IFS= read -r path; do
      [ -n "$path" ] && matching_paths+=("$path")
    done < <(list_ui_test_defaults_paths)

    if [ "${#matching_paths[@]}" -ne 0 ]; then
      for path in "${matching_paths[@]}"; do
        validate_new_ui_test_defaults_path "$path" || return 1
        basename="$(basename "$path")"
        domain="${basename%.plist}"
        remember_ui_test_defaults_domain "$domain"
        /usr/bin/defaults delete "$domain" >/dev/null 2>&1 || true
        removed_count=$((removed_count + 1))
      done

      # cfprefsd may briefly leave an empty plist after deleting a domain. Revalidate the exact
      # regular-file target before unlinking, then keep polling for a late rewrite.
      sleep 0.25
      for path in "${matching_paths[@]}"; do
        if [ -e "$path" ] || [ -L "$path" ]; then
          validate_new_ui_test_defaults_path "$path" || return 1
          /bin/unlink "$path" || return 1
        fi
      done
    fi

    readable_domain=false
    if [ "${#UI_TEST_DEFAULTS_SEEN_DOMAINS[@]}" -ne 0 ]; then
      for domain in "${UI_TEST_DEFAULTS_SEEN_DOMAINS[@]}"; do
        if /usr/bin/defaults read "$domain" >/dev/null 2>&1; then
          readable_domain=true
          /usr/bin/defaults delete "$domain" >/dev/null 2>&1 || true
        fi
      done
    fi

    remaining_paths=()
    while IFS= read -r path; do
      [ -n "$path" ] && remaining_paths+=("$path")
    done < <(list_ui_test_defaults_paths)

    if [ "${#remaining_paths[@]}" -eq 0 ] && [ "$readable_domain" = false ]; then
      stable_passes=$((stable_passes + 1))
      if [ "$stable_passes" -ge 6 ]; then
        echo "UI-test preferences cleanup verified: stable zero (${removed_count} removal observation(s))."
        return 0
      fi
    else
      stable_passes=0
    fi
    sleep 0.5
  done

  echo "UI-test preferences did not remain absent for six consecutive checks." >&2
  if [ "${#remaining_paths[@]}" -ne 0 ]; then
    printf '  %s\n' "${remaining_paths[@]}" >&2
  fi
  return 1
}

cleanup_on_exit() {
  local exit_status=$?
  trap - EXIT

  if cleanup_processes; then
    cleanup_ui_test_defaults_until_stable || exit_status=1
  else
    exit_status=1
  fi

  exit "$exit_status"
}

usage() {
  echo "usage: $0 [all|public|full|surface|en|zh-Hans]" >&2
  echo "env: UI_SMOKE_TIMEOUT_SECONDS=<seconds> (default: 1800, 0 disables)" >&2
  echo "env: UI_SMOKE_CLONED_SOURCE_PACKAGES_DIR=<path> (optional verified SwiftPM cache)" >&2
}

validate_timeout() {
  case "$UI_SMOKE_TIMEOUT_SECONDS" in
    ''|*[!0-9]*)
      echo "UI_SMOKE_TIMEOUT_SECONDS must be a non-negative integer." >&2
      exit 2
      ;;
  esac
}

selected_result_bundles() {
  case "$LANGUAGE" in
    all|public)
      printf '%s\n' "${RESULTS_DIR}/public-en.xcresult" "${RESULTS_DIR}/public-zh-Hans.xcresult"
      ;;
    full)
      printf '%s\n' "${RESULTS_DIR}/full-en.xcresult" "${RESULTS_DIR}/full-zh-Hans.xcresult"
      ;;
    surface)
      printf '%s\n' "${RESULTS_DIR}/surface-en.xcresult" "${RESULTS_DIR}/surface-zh-Hans.xcresult"
      ;;
    en)
      printf '%s\n' "${RESULTS_DIR}/public-en.xcresult"
      ;;
    zh-Hans)
      printf '%s\n' "${RESULTS_DIR}/public-zh-Hans.xcresult"
      ;;
  esac
}

prepare_selected_result_bundles() {
  local result_bundle

  if [[ -L "$RESULTS_DIR" || ( -e "$RESULTS_DIR" && ! -d "$RESULTS_DIR" ) ]]; then
    echo "UI-smoke results path is unsafe: $RESULTS_DIR" >&2
    exit 2
  fi
  mkdir -p "$RESULTS_DIR"

  while IFS= read -r result_bundle; do
    [[ -n "$result_bundle" ]] || continue
    if [[ -L "$result_bundle" || ( -e "$result_bundle" && ! -d "$result_bundle" ) ]]; then
      echo "Refusing to replace an unsafe UI-smoke result path: $result_bundle" >&2
      exit 2
    fi
    if [[ -d "$result_bundle" ]]; then
      /bin/rm -rf -- "$result_bundle"
    fi
    if [[ -e "$result_bundle" || -L "$result_bundle" ]]; then
      echo "Could not remove the exact previous UI-smoke result bundle: $result_bundle" >&2
      exit 2
    fi
  done < <(selected_result_bundles)
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
      cleanup_processes || true
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

validate_no_swiftui_publishing_warnings() {
  local result_bundle="$1"
  local tests_json
  local details_json
  local warning_count
  local test_id
  local test_ids=()

  if ! tests_json="$(
    xcrun xcresulttool get test-results tests \
      --path "$result_bundle" \
      --compact 2>&1
  )"; then
    cat >&2 <<EOF
Could not enumerate UI tests while checking SwiftUI runtime warnings: $result_bundle

xcresulttool output:
$tests_json
EOF
    return 1
  fi

  while IFS= read -r test_id; do
    [ -n "$test_id" ] && test_ids+=("$test_id")
  done < <(
    printf '%s' "$tests_json" |
      /usr/bin/ruby -rjson -e '
        report = JSON.parse(STDIN.read)
        identifiers = []
        walk = nil
        walk = lambda do |value|
          case value
          when Hash
            if value["nodeType"] == "Test Case"
              identifier = value["nodeIdentifier"].to_s
              abort "test case is missing nodeIdentifier" if identifier.empty?
              identifiers << identifier
            end
            value.each_value { |child| walk.call(child) }
          when Array
            value.each { |child| walk.call(child) }
          end
        end
        walk.call(report)
        identifiers.uniq.each { |identifier| puts identifier }
      '
  )

  if [ "${#test_ids[@]}" -eq 0 ]; then
    echo "UI result bundle contains no Test Case identifiers: $result_bundle" >&2
    return 1
  fi

  for test_id in "${test_ids[@]}"; do
    if ! details_json="$(
      xcrun xcresulttool get test-results test-details \
        --path "$result_bundle" \
        --test-id "$test_id" \
        --compact 2>&1
    )"; then
      cat >&2 <<EOF
Could not inspect UI test details for SwiftUI runtime warnings: $test_id

xcresulttool output:
$details_json
EOF
      return 1
    fi

    if ! warning_count="$(
      printf '%s' "$details_json" |
        /usr/bin/ruby -rjson -e '
          details = JSON.parse(STDIN.read)
          warning_prefix = "Publishing changes from within view updates is not allowed"
          count = 0
          walk = nil
          walk = lambda do |value|
            case value
            when Hash
              if value["nodeType"] == "Runtime Warning" &&
                 value["name"].to_s.include?(warning_prefix)
                count += 1
              end
              value.each_value { |child| walk.call(child) }
            when Array
              value.each { |child| walk.call(child) }
            end
          end
          walk.call(details)
          puts count
        ' 2>&1
    )"; then
      echo "Could not parse UI test details for SwiftUI runtime warnings: $test_id" >&2
      echo "$warning_count" >&2
      return 1
    fi

    case "$warning_count" in
      ''|*[!0-9]*)
        echo "Invalid SwiftUI runtime warning count for $test_id: $warning_count" >&2
        return 1
        ;;
    esac

    if [ "$warning_count" -ne 0 ]; then
      echo "$test_id reported ${warning_count} SwiftUI publishing warning(s)." >&2
      return 1
    fi
  done

  echo "SwiftUI publishing warnings verified: 0 across ${#test_ids[@]} UI test case(s)"
}

validate_xcresult() {
  local result_bundle="$1"
  local expected_test_count="$2"
  local summary
  local validation_output

  if [ ! -d "$result_bundle" ] || [ -L "$result_bundle" ]; then
    echo "UI smoke result bundle is missing or unsafe: $result_bundle" >&2
    return 1
  fi

  if ! summary="$(
    xcrun xcresulttool get test-results summary \
      --path "$result_bundle" \
      --compact 2>&1
  )"; then
    cat >&2 <<EOF
UI smoke result bundle is invalid or unreadable: $result_bundle

xcresulttool output:
$summary
EOF
    return 1
  fi

  if ! validation_output="$(
    printf '%s' "$summary" |
      /usr/bin/ruby -rjson -e '
        expected = Integer(ARGV.fetch(0))
        summary = JSON.parse(STDIN.read)
        fields = %w[result totalTestCount passedTests failedTests skippedTests expectedFailures]
        missing = fields.reject { |field| summary.key?(field) }
        abort "missing summary fields: #{missing.join(", ")}" unless missing.empty?

        result = summary.fetch("result")
        total = Integer(summary.fetch("totalTestCount"))
        passed = Integer(summary.fetch("passedTests"))
        failed = Integer(summary.fetch("failedTests"))
        skipped = Integer(summary.fetch("skippedTests"))
        expected_failures = Integer(summary.fetch("expectedFailures"))

        errors = []
        errors << "result is #{result.inspect}, expected \"Passed\"" unless result == "Passed"
        errors << "total test count is #{total}, expected #{expected}" unless total == expected
        errors << "passed test count is #{passed}, expected #{expected}" unless passed == expected
        errors << "#{failed} test(s) failed" unless failed.zero?
        errors << "#{skipped} test(s) skipped" unless skipped.zero?
        errors << "#{expected_failures} expected failure(s) reported" unless expected_failures.zero?

        abort errors.join("; ") unless errors.empty?
        puts "xcresult verified: #{passed}/#{expected} configured UI test(s) passed"
      ' "$expected_test_count" 2>&1
  )"; then
    cat >&2 <<EOF
UI smoke result verification failed: $result_bundle
$validation_output

xcresult summary:
$summary
EOF
    return 1
  fi

  echo "$validation_output"
  validate_no_swiftui_publishing_warnings "$result_bundle"
}

run_case() {
  local language="$1"
  local scope="$2"
  local result_bundle
  shift 2
  local tests=("$@")
  local only_testing_args=()
  local xcodebuild_args=(
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -destination "$DESTINATION"
    -derivedDataPath "$DERIVED_DATA"
  )
  local xcodebuild_status=0
  local xcresult_status=0
  local defaults_cleanup_status=0

  if [ "${#tests[@]}" -eq 0 ]; then
    echo "no tests configured for ${scope}/${language}" >&2
    exit 2
  fi

  for test_name in "${tests[@]}"; do
    only_testing_args+=("-only-testing:${test_name}")
  done

  if [ -n "$UI_SMOKE_CLONED_SOURCE_PACKAGES_DIR" ]; then
    if [ ! -d "$UI_SMOKE_CLONED_SOURCE_PACKAGES_DIR" ]; then
      echo "UI_SMOKE_CLONED_SOURCE_PACKAGES_DIR is not a directory: $UI_SMOKE_CLONED_SOURCE_PACKAGES_DIR" >&2
      exit 2
    fi
    xcodebuild_args+=(
      "-clonedSourcePackagesDirPath" "$UI_SMOKE_CLONED_SOURCE_PACKAGES_DIR"
      "-disableAutomaticPackageResolution"
    )
  fi

  cleanup_processes
  mkdir -p "$RESULTS_DIR"
  result_bundle="${RESULTS_DIR}/${scope}-${language}.xcresult"
  xcodebuild_args+=(
    CODE_SIGNING_ALLOWED=YES
    CODE_SIGN_IDENTITY=-
    PRODUCT_BUNDLE_IDENTIFIER=com.Chronicle.Chronicle.UISmoke
    -parallel-testing-enabled NO
    -testLanguage "$language"
    -resultBundlePath "$result_bundle"
    "${only_testing_args[@]}"
    test
  )

  echo "Running ${scope} UI smoke (${language}) with ${#tests[@]} test(s)."
  echo "Result bundle: ${result_bundle}"
  echo "Timeout: ${UI_SMOKE_TIMEOUT_SECONDS}s per smoke run."

  run_with_timeout "$UI_SMOKE_TIMEOUT_SECONDS" \
    env CHRONICLE_UI_SMOKE_LANGUAGE="$language" \
    xcodebuild \
    "${xcodebuild_args[@]}" || xcodebuild_status=$?

  if cleanup_processes; then
    cleanup_ui_test_defaults_until_stable || defaults_cleanup_status=$?
  else
    defaults_cleanup_status=$?
  fi

  validate_xcresult "$result_bundle" "${#tests[@]}" || xcresult_status=$?

  if [ "$xcodebuild_status" -ne 0 ]; then
    echo "xcodebuild failed for ${scope}/${language} with status ${xcodebuild_status}." >&2
    return "$xcodebuild_status"
  fi

  if [ "$defaults_cleanup_status" -ne 0 ]; then
    echo "UI-test preferences cleanup failed for ${scope}/${language}." >&2
    return "$defaults_cleanup_status"
  fi

  if [ "$xcresult_status" -ne 0 ]; then
    return "$xcresult_status"
  fi
}

main() {
  case "$LANGUAGE" in
    all|public|full|surface|en|zh-Hans)
      ;;
    *)
      usage
      exit 2
      ;;
  esac

  validate_timeout
  prepare_selected_result_bundles
  prepare_ui_test_defaults
  trap cleanup_on_exit EXIT
  require_automation_mode

  case "$LANGUAGE" in
    all|public)
      run_case en public "${PUBLIC_TESTS_EN[@]}"
      run_case zh-Hans public "${PUBLIC_TESTS_ZH_HANS[@]}"
      ;;
    full)
      run_case en full "${PUBLIC_TESTS_EN[@]}" "${SURFACE_TESTS[@]}"
      run_case zh-Hans full "${PUBLIC_TESTS_ZH_HANS[@]}" "${SURFACE_TESTS[@]}"
      ;;
    surface)
      run_case en surface "${SURFACE_TESTS[@]}"
      run_case zh-Hans surface "${SURFACE_TESTS[@]}"
      ;;
    en)
      run_case en public "${PUBLIC_TESTS_EN[@]}"
      ;;
    zh-Hans)
      run_case zh-Hans public "${PUBLIC_TESTS_ZH_HANS[@]}"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
