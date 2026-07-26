#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/Chronicle.xcodeproj"
DERIVED_DATA_PATH="${UNIT_TEST_DERIVED_DATA_PATH:-${ROOT_DIR}/build/unit-tests}"
RESULT_BUNDLE_INPUT="${UNIT_TEST_RESULT_BUNDLE_PATH:-${ROOT_DIR}/build/unit-test-results/ChronicleTests.xcresult}"
CLONED_SOURCE_PACKAGES_DIR="${UNIT_TEST_CLONED_SOURCE_PACKAGES_DIR:-}"
DEFAULT_EXPECTED_TEST_COUNT=296
EXPECTED_TEST_COUNT="${UNIT_TEST_EXPECTED_COUNT:-$DEFAULT_EXPECTED_TEST_COUNT}"

validate_expected_test_count() {
  local declared_test_count

  if [[ ! "$EXPECTED_TEST_COUNT" =~ ^[1-9][0-9]*$ ]]; then
    echo "UNIT_TEST_EXPECTED_COUNT must be a positive integer; got: $EXPECTED_TEST_COUNT" >&2
    return 1
  fi

  if [[ -z "${UNIT_TEST_EXPECTED_COUNT:-}" ]]; then
    declared_test_count="$(
      /usr/bin/ruby -e '
        count = Dir["ChronicleTests/**/*.swift"].sum do |path|
          File.read(path).scan(/^\s*func\s+test[A-Za-z0-9_]*\s*\(/).length
        end
        puts count
      '
    )"
    if [[ "$declared_test_count" != "$DEFAULT_EXPECTED_TEST_COUNT" ]]; then
      echo "Declared unit-test method count is ${declared_test_count}, but the committed expected count is ${DEFAULT_EXPECTED_TEST_COUNT}. Review the test change and update DEFAULT_EXPECTED_TEST_COUNT intentionally." >&2
      return 1
    fi
  fi
}

prepare_result_bundle_path() {
  local input_path="$1"
  local expanded_path
  local parent_path
  local physical_parent
  local basename

  if [[ -z "$input_path" ]]; then
    echo "UNIT_TEST_RESULT_BUNDLE_PATH must not be empty." >&2
    return 1
  fi

  expanded_path="$(/usr/bin/ruby -e 'puts File.expand_path(ARGV.fetch(0), ARGV.fetch(1))' "$input_path" "$ROOT_DIR")"
  basename="$(basename "$expanded_path")"
  if [[ ! "$basename" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*[.]xcresult$ ]]; then
    echo "UNIT_TEST_RESULT_BUNDLE_PATH must have a safe .xcresult basename: $expanded_path" >&2
    return 1
  fi

  parent_path="$(dirname "$expanded_path")"
  mkdir -p "$parent_path"
  physical_parent="$(cd "$parent_path" && pwd -P)"
  RESULT_BUNDLE_PATH="${physical_parent}/${basename}"

  if [[ -L "$RESULT_BUNDLE_PATH" ]]; then
    echo "Refusing to replace a symlink at the unit-test result path: $RESULT_BUNDLE_PATH" >&2
    return 1
  fi
  if [[ -e "$RESULT_BUNDLE_PATH" && ! -d "$RESULT_BUNDLE_PATH" ]]; then
    echo "Refusing to replace a non-directory unit-test result path: $RESULT_BUNDLE_PATH" >&2
    return 1
  fi

  if [[ -d "$RESULT_BUNDLE_PATH" ]]; then
    /bin/rm -rf -- "$RESULT_BUNDLE_PATH"
  fi
  if [[ -e "$RESULT_BUNDLE_PATH" || -L "$RESULT_BUNDLE_PATH" ]]; then
    echo "Could not remove the exact previous unit-test result bundle: $RESULT_BUNDLE_PATH" >&2
    return 1
  fi
}

validate_xcresult() {
  local result_bundle="$1"
  local expected_test_count="$2"
  local summary
  local validation_output

  if [[ ! -d "$result_bundle" || -L "$result_bundle" ]]; then
    echo "Unit-test result bundle is missing or unsafe: $result_bundle" >&2
    return 1
  fi

  if ! summary="$(
    xcrun xcresulttool get test-results summary \
      --path "$result_bundle" \
      --compact 2>&1
  )"; then
    cat >&2 <<EOF
Unit-test result bundle is invalid or unreadable: $result_bundle

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
        puts "Unit xcresult verified: #{passed}/#{expected} tests passed; 0 failed, 0 skipped, 0 expected failures."
      ' "$expected_test_count" 2>&1
  )"; then
    cat >&2 <<EOF
Unit-test result verification failed: $result_bundle
$validation_output

xcresult summary:
$summary
EOF
    return 1
  fi

  echo "$validation_output"
}

main() {
  local xcodebuild_args=(
    -project "$PROJECT_PATH"
    -scheme Chronicle
    -configuration Debug
    -destination 'platform=macOS,arch=arm64'
    -derivedDataPath "$DERIVED_DATA_PATH"
  )

  if [[ -n "$CLONED_SOURCE_PACKAGES_DIR" ]]; then
    if [[ ! -d "$CLONED_SOURCE_PACKAGES_DIR" ]]; then
      echo "UNIT_TEST_CLONED_SOURCE_PACKAGES_DIR is not a directory: $CLONED_SOURCE_PACKAGES_DIR" >&2
      exit 1
    fi
    xcodebuild_args+=(
      "-clonedSourcePackagesDirPath" "$CLONED_SOURCE_PACKAGES_DIR"
      "-disableAutomaticPackageResolution"
    )
  fi

  cd "$ROOT_DIR"

  validate_expected_test_count
  prepare_result_bundle_path "$RESULT_BUNDLE_INPUT"
  xcodebuild_args+=(
    CODE_SIGNING_ALLOWED=NO
    -parallel-testing-enabled NO
    -testLanguage en
    -testRegion US
    -resultBundlePath "$RESULT_BUNDLE_PATH"
    test
  )

  echo "Unit-test result bundle: $RESULT_BUNDLE_PATH"

  local xcodebuild_status=0
  local xcresult_status=0

  ruby ./script/support/test_preferences_guard.rb run -- \
    xcodebuild \
      "${xcodebuild_args[@]}" || xcodebuild_status=$?

  # The guarded command returns only after the XCTest host exits and the exact test-only
  # preferences cleanup has completed. Validate afterward, but never remove a failed bundle:
  # it is the evidence needed to diagnose an xcodebuild or test failure.
  validate_xcresult "$RESULT_BUNDLE_PATH" "$EXPECTED_TEST_COUNT" || xcresult_status=$?

  if [[ "$xcodebuild_status" -ne 0 ]]; then
    echo "Guarded unit-test command or preferences cleanup failed with status $xcodebuild_status; any produced result bundle remains at $RESULT_BUNDLE_PATH" >&2
    exit "$xcodebuild_status"
  fi

  if [[ "$xcresult_status" -ne 0 ]]; then
    echo "Unit-test xcresult validation failed; the result bundle remains at $RESULT_BUNDLE_PATH" >&2
    exit "$xcresult_status"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
