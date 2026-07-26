#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/Chronicle.xcodeproj"
APP_VERSION="$(awk -F ' = ' '/MARKETING_VERSION = / { gsub(/;/, "", $2); print $2 }' "${PROJECT_PATH}/project.pbxproj" | sort -u)"
APP_BUILD="$(awk -F ' = ' '/CURRENT_PROJECT_VERSION = / { gsub(/;/, "", $2); print $2 }' "${PROJECT_PATH}/project.pbxproj" | sort -u)"
DRY_RUN_TAG="${DRY_RUN_TAG:-v${APP_VERSION}}"
ARTIFACT_VERSION="${DRY_RUN_ARTIFACT_VERSION:-${DRY_RUN_TAG}-unsigned-dry-run}"
OUTPUT_DIR="${DRY_RUN_OUTPUT_DIR:-${ROOT_DIR}/dist/dry-run}"
RELEASE_CLONED_SOURCE_PACKAGES_DIR="${RELEASE_CLONED_SOURCE_PACKAGES_DIR:-}"
SOURCE_FINGERPRINT_TOOL="${ROOT_DIR}/script/support/release_source_fingerprint.rb"
MANIFEST_VERIFIER="${ROOT_DIR}/script/support/verify_release_dry_run_manifest.rb"
RELEASE_ANALYZE_SCRIPT="${ROOT_DIR}/script/run_release_analyze.sh"
DRY_RUN_MODE="${DRY_RUN_MODE:-authoritative}"
DRY_RUN_SKIP_TESTS="${DRY_RUN_SKIP_TESTS:-0}"
DRY_RUN_UPLOAD_DIR_INPUT="${DRY_RUN_UPLOAD_DIR:-${ROOT_DIR}/build/dry-run-upload}"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/chronicle-release-dry-run.XXXXXX")"
UNIT_TEST_SUMMARY_TEMP="${TEMP_ROOT}/unit-test-summary.json"
UNIT_TEST_RESULT_INPUT="${UNIT_TEST_RESULT_BUNDLE_PATH:-${ROOT_DIR}/build/unit-test-results/ChronicleTests.xcresult}"
UPLOAD_STAGING=""

cleanup() {
  if [[ -n "$UPLOAD_STAGING" && -d "$UPLOAD_STAGING" && ! -L "$UPLOAD_STAGING" ]]; then
    rm -rf -- "$UPLOAD_STAGING"
  fi
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

source_fingerprint() {
  /usr/bin/ruby "$SOURCE_FINGERPRINT_TOOL" "$ROOT_DIR"
}

assert_source_unchanged() {
  local stage="$1"
  local current_fingerprint
  local current_commit
  local current_dirty
  current_fingerprint="$(source_fingerprint)"
  current_commit="$(git rev-parse HEAD)"
  current_dirty="$(/usr/bin/ruby "$SOURCE_FINGERPRINT_TOOL" "$ROOT_DIR" --dirty)"
  if [[ "$current_fingerprint" != "$SOURCE_FINGERPRINT" ||
        "$current_commit" != "$SOURCE_COMMIT" ||
        "$current_dirty" != "$SOURCE_DIRTY_TEXT" ]]; then
    echo "Release inputs changed during the dry-run (${stage})." >&2
    echo "Initial fingerprint: ${SOURCE_FINGERPRINT}" >&2
    echo "Current fingerprint: ${current_fingerprint}" >&2
    echo "Initial commit: ${SOURCE_COMMIT}" >&2
    echo "Current commit: ${current_commit}" >&2
    echo "Initial dirty state: ${SOURCE_DIRTY_TEXT}" >&2
    echo "Current dirty state: ${current_dirty}" >&2
    exit 1
  fi
}

verify_manifest_against_current_source() {
  local manifest_path="$1"
  local artifact_directory="$2"
  local current_fingerprint
  local current_commit
  local current_dirty
  shift 2

  current_fingerprint="$(source_fingerprint)"
  current_commit="$(git rev-parse HEAD)"
  current_dirty="$(/usr/bin/ruby "$SOURCE_FINGERPRINT_TOOL" "$ROOT_DIR" --dirty)"
  if [[ "$current_fingerprint" != "$SOURCE_FINGERPRINT" ||
        "$current_commit" != "$SOURCE_COMMIT" ||
        "$current_dirty" != "$SOURCE_DIRTY_TEXT" ]]; then
    echo "Release inputs changed before dry-run manifest verification." >&2
    exit 1
  fi

  /usr/bin/ruby "$MANIFEST_VERIFIER" \
    "$manifest_path" \
    "$artifact_directory" \
    "$current_fingerprint" \
    "$current_commit" \
    "$DRY_RUN_TAG" \
    "$APP_VERSION" \
    "$APP_BUILD" \
    "$current_dirty" \
    "$@"
}

install_evidence_file() {
  local source_path="$1"
  local destination_path="$2"
  local destination_name
  local staging_path

  destination_name="$(basename "$destination_path")"
  if [[ "$(cd "$(dirname "$destination_path")" && pwd -P)" != "$OUTPUT_DIR" ]]; then
    echo "Evidence destination must be an immediate child of the dry-run output directory: ${destination_path}" >&2
    return 1
  fi
  if [[ ! -f "$source_path" || -L "$source_path" || ! -s "$source_path" ]]; then
    echo "Evidence source must be a non-symlink, non-empty regular file: ${source_path}" >&2
    return 1
  fi
  if [[ -L "$destination_path" || ( -e "$destination_path" && ! -f "$destination_path" ) ]]; then
    echo "Evidence destination is unsafe: ${destination_path}" >&2
    return 1
  fi
  staging_path="$(mktemp "${OUTPUT_DIR}/.${destination_name}.tmp.XXXXXX")"
  /bin/cp "$source_path" "$staging_path"
  chmod 600 "$staging_path"
  mv -f -- "$staging_path" "$destination_path"
}

prepare_upload_destination() {
  local build_root
  local expanded
  local leaf

  mkdir -p "${ROOT_DIR}/build"
  build_root="$(cd "${ROOT_DIR}/build" && pwd -P)"
  expanded="$(/usr/bin/ruby -e 'puts File.expand_path(ARGV.fetch(0), ARGV.fetch(1))' "$DRY_RUN_UPLOAD_DIR_INPUT" "$ROOT_DIR")"
  leaf="$(basename "$expanded")"
  if [[ "$(dirname "$expanded")" != "$build_root" || ! "$leaf" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "DRY_RUN_UPLOAD_DIR must be a safe immediate child of Chronicle's build directory: ${expanded}" >&2
    return 1
  fi
  UPLOAD_DIR="${build_root}/${leaf}"
  if [[ -L "$UPLOAD_DIR" || ( -e "$UPLOAD_DIR" && ! -d "$UPLOAD_DIR" ) ]]; then
    echo "Dry-run upload directory must be a non-symlink directory or absent: ${UPLOAD_DIR}" >&2
    return 1
  fi
  UPLOAD_STAGING="$(mktemp -d "${build_root}/.${leaf}.tmp.XXXXXX")"
}

if [[ -z "$APP_VERSION" || "$APP_VERSION" == *$'\n'* ]]; then
  echo "Could not resolve one MARKETING_VERSION from the Xcode project." >&2
  exit 1
fi
if [[ -z "$APP_BUILD" || "$APP_BUILD" == *$'\n'* ]]; then
  echo "Could not resolve one CURRENT_PROJECT_VERSION from the Xcode project." >&2
  exit 1
fi

case "$DRY_RUN_MODE" in
  authoritative|non-authoritative)
    ;;
  *)
    echo "DRY_RUN_MODE must be authoritative or non-authoritative; got: ${DRY_RUN_MODE}" >&2
    exit 1
    ;;
esac
case "$DRY_RUN_SKIP_TESTS" in
  0|1)
    ;;
  *)
    echo "DRY_RUN_SKIP_TESTS must be 0 or 1; got: ${DRY_RUN_SKIP_TESTS}" >&2
    exit 1
    ;;
esac
if [[ "$DRY_RUN_MODE" == "authoritative" && "$DRY_RUN_SKIP_TESTS" != "0" ]]; then
  echo "Authoritative dry-run evidence cannot skip unit tests." >&2
  echo "Use DRY_RUN_MODE=non-authoritative DRY_RUN_SKIP_TESTS=1 for an explicitly non-gate artifact rehearsal." >&2
  exit 1
fi
if [[ ! "$ARTIFACT_VERSION" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "DRY_RUN_ARTIFACT_VERSION must be a safe single path component; got: ${ARTIFACT_VERSION}" >&2
  exit 1
fi
if [[ ! -f "$SOURCE_FINGERPRINT_TOOL" || -L "$SOURCE_FINGERPRINT_TOOL" ]]; then
  echo "Release source fingerprint tool is missing or unsafe: ${SOURCE_FINGERPRINT_TOOL}" >&2
  exit 1
fi
if [[ ! -f "$MANIFEST_VERIFIER" || -L "$MANIFEST_VERIFIER" ]]; then
  echo "Dry-run manifest verifier is missing or unsafe: ${MANIFEST_VERIFIER}" >&2
  exit 1
fi
if [[ ! -f "$RELEASE_ANALYZE_SCRIPT" || -L "$RELEASE_ANALYZE_SCRIPT" ]]; then
  echo "Release Analyze wrapper is missing or unsafe: ${RELEASE_ANALYZE_SCRIPT}" >&2
  exit 1
fi

if [[ -n "$RELEASE_CLONED_SOURCE_PACKAGES_DIR" && ! -d "$RELEASE_CLONED_SOURCE_PACKAGES_DIR" ]]; then
  echo "RELEASE_CLONED_SOURCE_PACKAGES_DIR is not a directory: $RELEASE_CLONED_SOURCE_PACKAGES_DIR" >&2
  exit 1
fi

cd "$ROOT_DIR"

OUTPUT_DIR="$(/usr/bin/ruby -e 'puts File.expand_path(ARGV.fetch(0), ARGV.fetch(1))' "$OUTPUT_DIR" "$ROOT_DIR")"
if [[ "$OUTPUT_DIR" == "/" || "$OUTPUT_DIR" == "$ROOT_DIR" || "$OUTPUT_DIR" == "${HOME:-}" ]]; then
  echo "Refusing unsafe dry-run output directory: ${OUTPUT_DIR}" >&2
  exit 1
fi
if [[ -L "$OUTPUT_DIR" || ( -e "$OUTPUT_DIR" && ! -d "$OUTPUT_DIR" ) ]]; then
  echo "Dry-run output directory must be a non-symlink directory or absent: ${OUTPUT_DIR}" >&2
  exit 1
fi
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd -P)"
UNIT_TEST_SUMMARY_PATH="${OUTPUT_DIR}/Chronicle-${ARTIFACT_VERSION}.unit-test-summary.json"
ANALYZE_LOG_PATH="${OUTPUT_DIR}/Chronicle-${ARTIFACT_VERSION}.release-analyze.log"
ANALYZE_RECEIPT_PATH="${OUTPUT_DIR}/Chronicle-${ARTIFACT_VERSION}.release-analyze.receipt.json"

SOURCE_COMMIT="$(git rev-parse HEAD)"
SOURCE_BRANCH="$(git symbolic-ref --short -q HEAD || printf 'DETACHED')"
SOURCE_DIRTY_TEXT="$(/usr/bin/ruby "$SOURCE_FINGERPRINT_TOOL" "$ROOT_DIR" --dirty)"
if [[ "$SOURCE_DIRTY_TEXT" == "true" ]]; then
  SOURCE_DIRTY=1
else
  SOURCE_DIRTY=0
fi
SOURCE_FINGERPRINT="$(source_fingerprint)"
echo "Dry-run source commit: ${SOURCE_COMMIT}"
echo "Dry-run source branch: ${SOURCE_BRANCH}"
echo "Dry-run source dirty: ${SOURCE_DIRTY}"
echo "Dry-run source fingerprint: ${SOURCE_FINGERPRINT}"

echo "Running release preflight for ${DRY_RUN_TAG}..."
RELEASE_TAG="$DRY_RUN_TAG" \
REQUIRE_OPEN_SOURCE_LICENSE=0 \
REQUIRE_FINAL_RELEASE_NOTES=0 \
  ./script/run_release_preflight.sh
assert_source_unchanged "after preflight"

if [[ "$DRY_RUN_SKIP_TESTS" != "1" ]]; then
  echo "Running unit tests..."
  UNIT_TEST_DERIVED_DATA_PATH="${TEMP_ROOT}/unit-tests" \
  UNIT_TEST_CLONED_SOURCE_PACKAGES_DIR="$RELEASE_CLONED_SOURCE_PACKAGES_DIR" \
    ./script/run_unit_tests.sh
  UNIT_TEST_RESULT_PATH="$(/usr/bin/ruby -e 'puts File.expand_path(ARGV.fetch(0), ARGV.fetch(1))' "$UNIT_TEST_RESULT_INPUT" "$ROOT_DIR")"
  xcrun xcresulttool get test-results summary \
    --path "$UNIT_TEST_RESULT_PATH" \
    --compact > "$UNIT_TEST_SUMMARY_TEMP"
  install_evidence_file "$UNIT_TEST_SUMMARY_TEMP" "$UNIT_TEST_SUMMARY_PATH"
  assert_source_unchanged "after unit tests"
else
  UNIT_TEST_RESULT_PATH=""
  echo "NON-AUTHORITATIVE: skipping unit tests because DRY_RUN_MODE=non-authoritative and DRY_RUN_SKIP_TESTS=1."
fi

if [[ "$DRY_RUN_MODE" == "authoritative" ]]; then
  echo "Running universal Release Analyze..."
  RELEASE_ANALYZE_DERIVED_DATA_PATH="${TEMP_ROOT}/release-analyze" \
  RELEASE_ANALYZE_CLONED_SOURCE_PACKAGES_DIR="$RELEASE_CLONED_SOURCE_PACKAGES_DIR" \
  RELEASE_ANALYZE_LOG_PATH="$ANALYZE_LOG_PATH" \
  RELEASE_ANALYZE_RECEIPT_PATH="$ANALYZE_RECEIPT_PATH" \
  RELEASE_ANALYZE_SOURCE_FINGERPRINT="$SOURCE_FINGERPRINT" \
    bash "$RELEASE_ANALYZE_SCRIPT"
  ANALYZE_EXECUTED=1
  assert_source_unchanged "after Release Analyze"
else
  ANALYZE_EXECUTED=0
  echo "NON-AUTHORITATIVE: skipping Release Analyze; the binding manifest will record the explicit skip."
fi

echo "Building unsigned Release DMG..."
CODE_SIGNING_ALLOWED=NO \
CODESIGN_IDENTITY="" \
REQUIRE_SIGNING=0 \
REQUIRE_NOTARIZATION=0 \
NOTARY_KEYCHAIN_PROFILE="" \
NOTARYTOOL_KEY_PATH="" \
NOTARYTOOL_KEY_ID="" \
NOTARYTOOL_ISSUER_ID="" \
DMG_VERSION="$ARTIFACT_VERSION" \
DERIVED_DATA="${TEMP_ROOT}/dmg-release" \
OUTPUT_DIR="$OUTPUT_DIR" \
CLONED_SOURCE_PACKAGES_DIR="$RELEASE_CLONED_SOURCE_PACKAGES_DIR" \
  ./scripts/build_dmg.sh

DMG_PATH="${OUTPUT_DIR}/Chronicle-${ARTIFACT_VERSION}.dmg"
CHECKSUM_PATH="${DMG_PATH}.sha256"
[[ -f "$DMG_PATH" ]] || { echo "Dry-run DMG missing: ${DMG_PATH}" >&2; exit 1; }
[[ -f "$CHECKSUM_PATH" ]] || { echo "Dry-run checksum missing: ${CHECKSUM_PATH}" >&2; exit 1; }

(
  cd "$OUTPUT_DIR"
  shasum -a 256 -c "$(basename "$CHECKSUM_PATH")"
)

EXPECTED_APP_VERSION="$APP_VERSION" \
EXPECTED_APP_BUILD="$APP_BUILD" \
EXPECTED_MINIMUM_MACOS=14.0 \
  ./script/inspect_release_artifact.sh "$DMG_PATH" rehearsal

assert_source_unchanged "after Release build and artifact inspection"

DMG_SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print tolower($1)}')"
PUBLISHED_DMG_SHA256="$(awk 'NF { print tolower($1); exit }' "$CHECKSUM_PATH")"
if [[ "$DMG_SHA256" != "$PUBLISHED_DMG_SHA256" ]]; then
  echo "Dry-run DMG digest no longer matches its checksum file." >&2
  exit 1
fi
CHECKSUM_SHA256="$(shasum -a 256 "$CHECKSUM_PATH" | awk '{print tolower($1)}')"
DMG_SIZE="$(/usr/bin/ruby -e 'puts File.size(ARGV.fetch(0))' "$DMG_PATH")"
CHECKSUM_SIZE="$(/usr/bin/ruby -e 'puts File.size(ARGV.fetch(0))' "$CHECKSUM_PATH")"
TESTS_EXECUTED="$((1 - DRY_RUN_SKIP_TESTS))"

if [[ "$TESTS_EXECUTED" == "1" ]]; then
  UNIT_SUMMARY_NAME="$(basename "$UNIT_TEST_SUMMARY_PATH")"
  UNIT_SUMMARY_SIZE="$(/usr/bin/ruby -e 'puts File.size(ARGV.fetch(0))' "$UNIT_TEST_SUMMARY_PATH")"
  UNIT_SUMMARY_SHA256="$(shasum -a 256 "$UNIT_TEST_SUMMARY_PATH" | awk '{print tolower($1)}')"
else
  UNIT_SUMMARY_NAME=""
  UNIT_SUMMARY_SIZE=""
  UNIT_SUMMARY_SHA256=""
fi

if [[ "$ANALYZE_EXECUTED" == "1" ]]; then
  ANALYZE_LOG_NAME="$(basename "$ANALYZE_LOG_PATH")"
  ANALYZE_RECEIPT_NAME="$(basename "$ANALYZE_RECEIPT_PATH")"
else
  ANALYZE_LOG_NAME=""
  ANALYZE_RECEIPT_NAME=""
fi

DRY_RUN_MANIFEST_PATH="${OUTPUT_DIR}/Chronicle-${ARTIFACT_VERSION}.dry-run-manifest.json"
DRY_RUN_MANIFEST_STAGING="${DRY_RUN_MANIFEST_PATH}.tmp.$$"
if [[ -L "$DRY_RUN_MANIFEST_PATH" || ( -e "$DRY_RUN_MANIFEST_PATH" && ! -f "$DRY_RUN_MANIFEST_PATH" ) ]]; then
  echo "Dry-run binding manifest path is unsafe: ${DRY_RUN_MANIFEST_PATH}" >&2
  exit 1
fi
if [[ -e "$DRY_RUN_MANIFEST_STAGING" || -L "$DRY_RUN_MANIFEST_STAGING" ]]; then
  echo "Dry-run binding manifest staging path already exists: ${DRY_RUN_MANIFEST_STAGING}" >&2
  exit 1
fi

DRY_RUN_MANIFEST_STAGING="$DRY_RUN_MANIFEST_STAGING" \
DRY_RUN_MODE="$DRY_RUN_MODE" \
DRY_RUN_TESTS_EXECUTED="$TESTS_EXECUTED" \
DRY_RUN_UNIT_SUMMARY_PATH="$UNIT_TEST_SUMMARY_PATH" \
DRY_RUN_UNIT_SUMMARY_NAME="$UNIT_SUMMARY_NAME" \
DRY_RUN_UNIT_SUMMARY_SIZE="$UNIT_SUMMARY_SIZE" \
DRY_RUN_UNIT_SUMMARY_SHA256="$UNIT_SUMMARY_SHA256" \
DRY_RUN_ANALYZE_EXECUTED="$ANALYZE_EXECUTED" \
DRY_RUN_ANALYZE_LOG_PATH="$ANALYZE_LOG_PATH" \
DRY_RUN_ANALYZE_LOG_NAME="$ANALYZE_LOG_NAME" \
DRY_RUN_ANALYZE_RECEIPT_PATH="$ANALYZE_RECEIPT_PATH" \
DRY_RUN_ANALYZE_RECEIPT_NAME="$ANALYZE_RECEIPT_NAME" \
DRY_RUN_SOURCE_COMMIT="$SOURCE_COMMIT" \
DRY_RUN_SOURCE_BRANCH="$SOURCE_BRANCH" \
DRY_RUN_SOURCE_DIRTY="$SOURCE_DIRTY" \
DRY_RUN_SOURCE_FINGERPRINT="$SOURCE_FINGERPRINT" \
DRY_RUN_TAG_VALUE="$DRY_RUN_TAG" \
DRY_RUN_ARTIFACT_VERSION_VALUE="$ARTIFACT_VERSION" \
DRY_RUN_APP_VERSION="$APP_VERSION" \
DRY_RUN_APP_BUILD="$APP_BUILD" \
DRY_RUN_DMG_NAME="$(basename "$DMG_PATH")" \
DRY_RUN_DMG_SIZE="$DMG_SIZE" \
DRY_RUN_DMG_SHA256="$DMG_SHA256" \
DRY_RUN_CHECKSUM_NAME="$(basename "$CHECKSUM_PATH")" \
DRY_RUN_CHECKSUM_SIZE="$CHECKSUM_SIZE" \
DRY_RUN_CHECKSUM_SHA256="$CHECKSUM_SHA256" \
  /usr/bin/ruby -rjson -rdigest -rtime -e '
    digest_pattern = /\A[0-9a-f]{64}\z/
    mode = ENV.fetch("DRY_RUN_MODE")
    authoritative = mode == "authoritative"
    tests_executed = ENV.fetch("DRY_RUN_TESTS_EXECUTED") == "1"
    analyze_executed = ENV.fetch("DRY_RUN_ANALYZE_EXECUTED") == "1"
    abort "authoritative manifest cannot omit tests" if authoritative && !tests_executed
    abort "authoritative manifest cannot omit Release Analyze" if authoritative && !analyze_executed

    tests = { "executed" => tests_executed }
    if tests_executed
      summary_path = ENV.fetch("DRY_RUN_UNIT_SUMMARY_PATH")
      summary_bytes = File.binread(summary_path)
      summary = JSON.parse(summary_bytes)
      required = %w[result totalTestCount passedTests failedTests skippedTests expectedFailures]
      missing = required.reject { |field| summary.key?(field) }
      abort "unit summary is missing #{missing.join(", ")}" unless missing.empty?
      abort "unit summary is not passed" unless summary.fetch("result") == "Passed"
      total = Integer(summary.fetch("totalTestCount"))
      passed = Integer(summary.fetch("passedTests"))
      failed = Integer(summary.fetch("failedTests"))
      skipped = Integer(summary.fetch("skippedTests"))
      expected_failures = Integer(summary.fetch("expectedFailures"))
      abort "unit summary is not an exact all-pass result" unless total.positive? && passed == total && failed.zero? && skipped.zero? && expected_failures.zero?
      summary_sha256 = Digest::SHA256.hexdigest(summary_bytes)
      abort "unit summary SHA-256 changed before manifest creation" unless summary_sha256 == ENV.fetch("DRY_RUN_UNIT_SUMMARY_SHA256")
      abort "unit summary size changed before manifest creation" unless summary_bytes.bytesize == Integer(ENV.fetch("DRY_RUN_UNIT_SUMMARY_SIZE"), 10)
      tests.merge!(
        "status" => "passed",
        "result_bundle_evidence" => "ChronicleTests.xcresult",
        "summary" => {
          "name" => ENV.fetch("DRY_RUN_UNIT_SUMMARY_NAME"),
          "size" => summary_bytes.bytesize,
          "sha256" => summary_sha256
        },
        "total" => total,
        "passed" => passed,
        "failed" => failed,
        "skipped" => skipped,
        "expected_failures" => expected_failures
      )
    else
      tests.merge!(
        "status" => "skipped_non_authoritative",
        "reason" => "explicit non-authoritative artifact rehearsal"
      )
    end

    analysis = { "executed" => analyze_executed }
    if analyze_executed
      log_bytes = File.binread(ENV.fetch("DRY_RUN_ANALYZE_LOG_PATH"))
      receipt_bytes = File.binread(ENV.fetch("DRY_RUN_ANALYZE_RECEIPT_PATH"))
      analysis.merge!(
        "status" => "passed",
        "log" => {
          "name" => ENV.fetch("DRY_RUN_ANALYZE_LOG_NAME"),
          "size" => log_bytes.bytesize,
          "sha256" => Digest::SHA256.hexdigest(log_bytes)
        },
        "receipt" => {
          "name" => ENV.fetch("DRY_RUN_ANALYZE_RECEIPT_NAME"),
          "size" => receipt_bytes.bytesize,
          "sha256" => Digest::SHA256.hexdigest(receipt_bytes)
        }
      )
    else
      analysis.merge!(
        "status" => "skipped_non_authoritative",
        "reason" => "explicit non-authoritative artifact rehearsal"
      )
    end

    %w[
      DRY_RUN_SOURCE_FINGERPRINT DRY_RUN_DMG_SHA256 DRY_RUN_CHECKSUM_SHA256
    ].each do |name|
      abort "invalid #{name}" unless ENV.fetch(name).match?(digest_pattern)
    end
    manifest = {
      "schema_version" => 3,
      "attestation_type" => "chronicle_unsigned_release_dry_run",
      "status" => authoritative ? "passed" : "completed_non_authoritative",
      "pass" => authoritative,
      "authoritative_rehearsal" => authoritative,
      "publishable" => false,
      "created_at" => Time.now.utc.iso8601,
      "source" => {
        "fingerprint_schema" => "chronicle-release-source-fingerprint-v1",
        "fingerprint" => ENV.fetch("DRY_RUN_SOURCE_FINGERPRINT"),
        "commit" => ENV.fetch("DRY_RUN_SOURCE_COMMIT"),
        "branch" => ENV.fetch("DRY_RUN_SOURCE_BRANCH"),
        "dirty" => ENV.fetch("DRY_RUN_SOURCE_DIRTY") == "1"
      },
      "release" => {
        "tag" => ENV.fetch("DRY_RUN_TAG_VALUE"),
        "artifact_version" => ENV.fetch("DRY_RUN_ARTIFACT_VERSION_VALUE"),
        "app_version" => ENV.fetch("DRY_RUN_APP_VERSION"),
        "app_build" => ENV.fetch("DRY_RUN_APP_BUILD")
      },
      "validation" => {
        "preflight" => { "status" => "passed" },
        "unit_tests" => tests,
        "release_analyze" => analysis
      },
      "artifact" => {
        "inspection_mode" => "rehearsal",
        "signing" => "unsigned",
        "notarized" => false,
        "stapled" => false,
        "dmg" => {
          "name" => ENV.fetch("DRY_RUN_DMG_NAME"),
          "size" => Integer(ENV.fetch("DRY_RUN_DMG_SIZE"), 10),
          "sha256" => ENV.fetch("DRY_RUN_DMG_SHA256")
        },
        "checksum" => {
          "name" => ENV.fetch("DRY_RUN_CHECKSUM_NAME"),
          "size" => Integer(ENV.fetch("DRY_RUN_CHECKSUM_SIZE"), 10),
          "sha256" => ENV.fetch("DRY_RUN_CHECKSUM_SHA256")
        }
      }
    }
    File.open(ENV.fetch("DRY_RUN_MANIFEST_STAGING"), File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.write(JSON.pretty_generate(manifest) << "\n")
      file.flush
      file.fsync
    end
  '

if [[ -L "$DRY_RUN_MANIFEST_PATH" || ( -e "$DRY_RUN_MANIFEST_PATH" && ! -f "$DRY_RUN_MANIFEST_PATH" ) ]]; then
  echo "Dry-run binding manifest destination became unsafe: ${DRY_RUN_MANIFEST_PATH}" >&2
  exit 1
fi
mv -f -- "$DRY_RUN_MANIFEST_STAGING" "$DRY_RUN_MANIFEST_PATH"

verify_manifest_against_current_source \
  "$DRY_RUN_MANIFEST_PATH" "$OUTPUT_DIR"
assert_source_unchanged "after manifest finalization"

prepare_upload_destination
EVIDENCE_PATHS=("$DMG_PATH" "$CHECKSUM_PATH" "$DRY_RUN_MANIFEST_PATH")
if [[ "$TESTS_EXECUTED" == "1" ]]; then
  EVIDENCE_PATHS+=("$UNIT_TEST_SUMMARY_PATH")
fi
if [[ "$ANALYZE_EXECUTED" == "1" ]]; then
  EVIDENCE_PATHS+=("$ANALYZE_LOG_PATH" "$ANALYZE_RECEIPT_PATH")
fi
for evidence_path in "${EVIDENCE_PATHS[@]}"; do
  /bin/cp "$evidence_path" "$UPLOAD_STAGING/$(basename "$evidence_path")"
done

STAGED_MANIFEST_PATH="${UPLOAD_STAGING}/$(basename "$DRY_RUN_MANIFEST_PATH")"
verify_manifest_against_current_source \
  "$STAGED_MANIFEST_PATH" "$UPLOAD_STAGING" --exact-files
assert_source_unchanged "after exact evidence staging"

if [[ -d "$UPLOAD_DIR" ]]; then
  rm -rf -- "$UPLOAD_DIR"
fi
if [[ -e "$UPLOAD_DIR" || -L "$UPLOAD_DIR" ]]; then
  echo "Could not clear the exact previous dry-run upload directory: ${UPLOAD_DIR}" >&2
  exit 1
fi
mv -- "$UPLOAD_STAGING" "$UPLOAD_DIR"
UPLOAD_STAGING=""

verify_manifest_against_current_source \
  "${UPLOAD_DIR}/$(basename "$DRY_RUN_MANIFEST_PATH")" \
  "$UPLOAD_DIR" --exact-files
assert_source_unchanged "after verified evidence installation"

if [[ "$DRY_RUN_MODE" == "authoritative" ]]; then
  echo "AUTHORITATIVE REHEARSAL PASS: source-bound unit tests, universal Release Analyze, and unsigned artifact checks succeeded."
else
  echo "NON-AUTHORITATIVE REHEARSAL COMPLETE: this result is not PASS evidence and is not a release gate."
fi
echo "Version: ${APP_VERSION} (${APP_BUILD})"
echo "DMG: ${DMG_PATH}"
echo "Checksum: ${CHECKSUM_PATH}"
if [[ "$TESTS_EXECUTED" == "1" ]]; then
  echo "Unit summary: ${UNIT_TEST_SUMMARY_PATH}"
fi
if [[ "$ANALYZE_EXECUTED" == "1" ]]; then
  echo "Release Analyze log: ${ANALYZE_LOG_PATH}"
  echo "Release Analyze receipt: ${ANALYZE_RECEIPT_PATH}"
else
  echo "Release Analyze: skipped_non_authoritative"
fi
echo "Binding manifest: ${DRY_RUN_MANIFEST_PATH}"
echo "Verified upload payload: ${UPLOAD_DIR}"
echo "Publishable: no (unsigned rehearsal artifact)"
echo "No release was uploaded."
