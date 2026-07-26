#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/Chronicle.xcodeproj"
PREVIOUS_TAG="${UPGRADE_DRILL_PREVIOUS_TAG:-v1.0.5}"
PACKAGE_CACHE="${UPGRADE_DRILL_CLONED_SOURCE_PACKAGES_DIR:-}"
EVIDENCE_DIR="${UPGRADE_DRILL_EVIDENCE_DIR:-${ROOT_DIR}/build/release-evidence}"
CANONICAL_REPORT_POINTER="${EVIDENCE_DIR}/previous-release-upgrade-drill-latest-passed.path"
INSPECTOR_SOURCE="${ROOT_DIR}/script/support/sqlcipher_upgrade_drill_inspector.c"
SOURCE_FINGERPRINT_TOOL="${ROOT_DIR}/script/support/release_source_fingerprint.rb"
PLAIN_SQLITE_HEADER="53514c69746520666f726d6174203300"
V105_PRODUCTION_TABLES_SQL="SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN ('Activities','Markers','MarkerSpans','Tags','Rules','AppMappings','RawEvents','SchemaMigrations');"
V105_PRODUCTION_MIGRATIONS_SQL="SELECT COUNT(*) FROM SchemaMigrations WHERE name IN ('2026_01_add_bundle_id','2026_02_raw_events','2026_03_effective_tag_columns','2026_04_rules_match_bundle_id','2026_05_app_mappings_tagging_mode');"
V105_ALL_MIGRATIONS_SQL="SELECT COUNT(*) FROM SchemaMigrations;"
V105_SCHEMA_READINESS_SQL="SELECT (SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN ('Activities','Markers','MarkerSpans','Tags','Rules','AppMappings','RawEvents','SchemaMigrations')) || '|' || (SELECT COUNT(*) FROM SchemaMigrations WHERE name IN ('2026_01_add_bundle_id','2026_02_raw_events','2026_03_effective_tag_columns','2026_04_rules_match_bundle_id','2026_05_app_mappings_tagging_mode')) || '|' || (SELECT COUNT(*) FROM SchemaMigrations);"
RUN_TIMESTAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
RUN_TOKEN="d${RUN_TIMESTAMP//[TZ]/}p$$"
OLD_BUNDLE_ID="com.Chronicle.Chronicle.UpgradeDrill.v105.${RUN_TOKEN}"
CANDIDATE_BUNDLE_ID="com.Chronicle.Chronicle.UpgradeDrill.candidate.${RUN_TOKEN}"
OLD_PRODUCT_NAME="ChronicleUpgradeDrillV105_${RUN_TOKEN}"
CANDIDATE_PRODUCT_NAME="ChronicleUpgradeDrillCandidate_${RUN_TOKEN}"
CANDIDATE_DEFAULTS_DOMAIN="${CANDIDATE_BUNDLE_ID}.defaults"
REAL_PREFERENCES_DIR="$(cd "${HOME:?HOME is required}" && pwd -P)/Library/Preferences"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/chronicle-previous-release-upgrade.XXXXXX")"
OLD_SOURCE="${TEMP_ROOT}/v1.0.5-source"
OLD_DERIVED_DATA="${TEMP_ROOT}/v1.0.5-derived-data"
CANDIDATE_DERIVED_DATA="${TEMP_ROOT}/candidate-derived-data"
CANDIDATE_SUPPORT="${TEMP_ROOT}/candidate-app-support"
ISOLATED_HOME="${TEMP_ROOT}/isolated-home"
PLAINTEXT_BACKUP="${TEMP_ROOT}/v1.0.5-plaintext-backup.sqlite"
INSPECTOR_BINARY="${TEMP_ROOT}/sqlcipher-upgrade-drill-inspector"
OLD_SUPPORT="${ISOLATED_HOME}/Library/Application Support/${OLD_PRODUCT_NAME}"
OLD_DATABASE="${OLD_SUPPORT}/activity.sqlite"
OLD_PID=""
CANDIDATE_PID=""
PACKAGE_ARGS=()
LOG_TEE_PID=""
DRILL_SUCCEEDED=0
OLD_EXECUTABLE_SHA256=""
CANDIDATE_EXECUTABLE_SHA256=""
CANDIDATE_SQLCIPHER_SHA256=""
CANDIDATE_DATABASE_SHA256=""
CANDIDATE_APP_VERSION=""
CANDIDATE_APP_BUILD=""

mkdir -p "$EVIDENCE_DIR"
if [[ -L "$EVIDENCE_DIR" || ! -d "$EVIDENCE_DIR" ]]; then
  echo "Upgrade-drill evidence directory must be a non-symlink directory: ${EVIDENCE_DIR}" >&2
  exit 1
fi
EVIDENCE_DIR="$(cd "$EVIDENCE_DIR" && pwd -P)"
CANONICAL_REPORT_POINTER="${EVIDENCE_DIR}/previous-release-upgrade-drill-latest-passed.path"
REPORT_PATH="${EVIDENCE_DIR}/previous-release-upgrade-drill-${RUN_TIMESTAMP}.log"
ATTESTATION_PATH="${EVIDENCE_DIR}/previous-release-upgrade-drill-${RUN_TIMESTAMP}.json"
LOG_FIFO="${TEMP_ROOT}/upgrade-drill-log.pipe"
if [[ -e "$REPORT_PATH" || -L "$REPORT_PATH" || -e "$ATTESTATION_PATH" || -L "$ATTESTATION_PATH" ]]; then
  echo "Refusing to replace existing upgrade-drill evidence for ${RUN_TIMESTAMP}." >&2
  exit 1
fi
exec 3>&1 4>&2
/usr/bin/mkfifo "$LOG_FIFO"
tee "$REPORT_PATH" < "$LOG_FIFO" >&3 &
LOG_TEE_PID=$!
exec > "$LOG_FIFO" 2>&1

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

header_hex() {
  if [[ ! -f "$1" ]]; then
    return 1
  fi
  /usr/bin/xxd -p -l 16 "$1" | tr -d '\n'
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "$actual" != "$expected" ]]; then
    fail "${label}: expected '${expected}', got '${actual}'"
  fi
}

sqlite_scalar() {
  /usr/bin/sqlite3 -batch -bail "$1" "$2"
}

candidate_source_fingerprint() (
  ruby "$SOURCE_FINGERPRINT_TOOL" "$ROOT_DIR"
)

candidate_source_dirty() (
  ruby "$SOURCE_FINGERPRINT_TOOL" "$ROOT_DIR" --dirty
)

gentle_stop() {
  local pid="$1"
  local label="$2"
  local attempt
  if [[ -z "$pid" ]] || ! kill -0 "$pid" >/dev/null 2>&1; then
    wait "$pid" >/dev/null 2>&1 || true
    return 0
  fi

  echo "Stopping ${label} with SIGTERM (pid ${pid})..."
  kill -TERM "$pid" >/dev/null 2>&1 || true
  for attempt in $(seq 1 100); do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      wait "$pid" >/dev/null 2>&1 || true
      return 0
    fi
    sleep 0.1
  done
  echo "${label} did not exit after SIGTERM; no force-kill was attempted." >&2
  return 1
}

remove_exact_temporary_path() {
  local target="$1"
  [[ -e "$target" || -L "$target" ]] || return 0
  case "$target" in
    "${TMPDIR:-/tmp}/chronicle-previous-release-upgrade."*)
      /bin/rm -rf -- "$target"
      ;;
    *)
      echo "Refusing to remove a path outside the drill's exact temporary namespaces: ${target}" >&2
      return 1
      ;;
  esac
}

is_generated_preference_domain() {
  case "$1" in
    "$OLD_BUNDLE_ID"|"$CANDIDATE_BUNDLE_ID"|"$CANDIDATE_DEFAULTS_DOMAIN")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

cleanup_generated_preference_domain() {
  local domain="$1"
  local plist_path
  if ! is_generated_preference_domain "$domain"; then
    echo "Refusing to clean a preference domain not generated by this drill: ${domain}" >&2
    return 1
  fi
  plist_path="${REAL_PREFERENCES_DIR}/${domain}.plist"

  # CFFIXED_USER_HOME does not reliably redirect CFPreferences. Ask the preferences
  # service to forget the exact generated domain first, then remove only that domain's
  # orphaned plist if the service has already stopped recognizing it.
  /usr/bin/defaults delete "$domain" >/dev/null 2>&1 || true
  if /usr/bin/defaults read "$domain" >/dev/null 2>&1; then
    echo "Preference cleanup failed; the generated domain is still readable: ${domain}" >&2
    return 1
  fi
  if [[ -e "$plist_path" || -L "$plist_path" ]]; then
    if ! /bin/unlink "$plist_path"; then
      echo "Preference cleanup failed; could not unlink the exact generated plist: ${plist_path}" >&2
      return 1
    fi
  fi

  if [[ -e "$plist_path" || -L "$plist_path" ]]; then
    echo "Preference cleanup failed; the exact generated plist remains: ${plist_path}" >&2
    return 1
  fi
}

cleanup_generated_preferences() {
  local domain
  local succeeded=1
  for domain in "$OLD_BUNDLE_ID" "$CANDIDATE_BUNDLE_ID" "$CANDIDATE_DEFAULTS_DOMAIN"; do
    if ! cleanup_generated_preference_domain "$domain"; then
      succeeded=0
    fi
  done
  if [[ "$succeeded" == "1" ]]; then
    echo "Verified cleanup of all three exact generated preference domains and plist paths."
    return 0
  fi
  return 1
}

write_passed_attestation() {
  local log_sha256="$1"
  local log_size="$2"
  local staging_path="${ATTESTATION_PATH}.tmp.$$"

  if [[ -e "$staging_path" || -L "$staging_path" ]]; then
    echo "Refusing existing attestation staging path: ${staging_path}" >&2
    return 1
  fi

  ATTESTATION_PATH="$ATTESTATION_PATH" \
  ATTESTATION_STAGING_PATH="$staging_path" \
  ATTESTATION_CREATED_AT="$RUN_TIMESTAMP" \
  ATTESTATION_SOURCE_FINGERPRINT="$CANDIDATE_SOURCE_FINGERPRINT" \
  ATTESTATION_SOURCE_COMMIT="$CANDIDATE_HEAD" \
  ATTESTATION_SOURCE_BRANCH="$CANDIDATE_BRANCH" \
  ATTESTATION_SOURCE_DIRTY="$CANDIDATE_WORKTREE_DIRTY" \
  ATTESTATION_PREVIOUS_TAG="$PREVIOUS_TAG" \
  ATTESTATION_PREVIOUS_COMMIT="$PREVIOUS_COMMIT" \
  ATTESTATION_PREVIOUS_TREE="$PREVIOUS_TREE" \
  ATTESTATION_OLD_BUNDLE_ID="$OLD_BUNDLE_ID" \
  ATTESTATION_OLD_PRODUCT_NAME="$OLD_PRODUCT_NAME" \
  ATTESTATION_OLD_EXECUTABLE_SHA256="$OLD_EXECUTABLE_SHA256" \
  ATTESTATION_CANDIDATE_BUNDLE_ID="$CANDIDATE_BUNDLE_ID" \
  ATTESTATION_CANDIDATE_PRODUCT_NAME="$CANDIDATE_PRODUCT_NAME" \
  ATTESTATION_CANDIDATE_VERSION="$CANDIDATE_APP_VERSION" \
  ATTESTATION_CANDIDATE_BUILD="$CANDIDATE_APP_BUILD" \
  ATTESTATION_CANDIDATE_EXECUTABLE_SHA256="$CANDIDATE_EXECUTABLE_SHA256" \
  ATTESTATION_CANDIDATE_SQLCIPHER_SHA256="$CANDIDATE_SQLCIPHER_SHA256" \
  ATTESTATION_CANDIDATE_DATABASE_SHA256="$CANDIDATE_DATABASE_SHA256" \
  ATTESTATION_LOG_FILE="$(basename "$REPORT_PATH")" \
  ATTESTATION_LOG_SHA256="$log_sha256" \
  ATTESTATION_LOG_SIZE="$log_size" \
    /usr/bin/ruby -rjson -rtime -e '
      digest_pattern = /\A[0-9a-f]{64}\z/
      required_digests = %w[
        ATTESTATION_SOURCE_FINGERPRINT
        ATTESTATION_OLD_EXECUTABLE_SHA256
        ATTESTATION_CANDIDATE_EXECUTABLE_SHA256
        ATTESTATION_CANDIDATE_SQLCIPHER_SHA256
        ATTESTATION_CANDIDATE_DATABASE_SHA256
        ATTESTATION_LOG_SHA256
      ]
      required_digests.each do |name|
        abort "invalid #{name}" unless ENV.fetch(name).match?(digest_pattern)
      end

      dirty = ENV.fetch("ATTESTATION_SOURCE_DIRTY")
      abort "invalid source dirty state" unless %w[0 1].include?(dirty)
      log_size = Integer(ENV.fetch("ATTESTATION_LOG_SIZE"), 10)
      abort "upgrade-drill log is empty" unless log_size.positive?

      manifest = {
        "schema_version" => 1,
        "attestation_type" => "chronicle_previous_release_upgrade_drill",
        "status" => "passed",
        "pass" => true,
        "created_at" => Time.strptime(ENV.fetch("ATTESTATION_CREATED_AT"), "%Y%m%dT%H%M%S%z").utc.iso8601,
        "source" => {
          "fingerprint_schema" => "chronicle-release-source-fingerprint-v1",
          "fingerprint" => ENV.fetch("ATTESTATION_SOURCE_FINGERPRINT"),
          "commit" => ENV.fetch("ATTESTATION_SOURCE_COMMIT"),
          "branch" => ENV.fetch("ATTESTATION_SOURCE_BRANCH"),
          "dirty" => dirty == "1"
        },
        "previous_release" => {
          "tag" => ENV.fetch("ATTESTATION_PREVIOUS_TAG"),
          "resolved_commit" => ENV.fetch("ATTESTATION_PREVIOUS_COMMIT"),
          "source" => {
            "mode" => "git_archive_resolved_commit_release_safety_build",
            "archive_commit" => ENV.fetch("ATTESTATION_PREVIOUS_COMMIT"),
            "tree_oid" => ENV.fetch("ATTESTATION_PREVIOUS_TREE"),
            "configuration" => "Release",
            "bundle_id" => ENV.fetch("ATTESTATION_OLD_BUNDLE_ID"),
            "product_name" => ENV.fetch("ATTESTATION_OLD_PRODUCT_NAME"),
            "sandbox_enabled" => false,
            "executable_sha256" => ENV.fetch("ATTESTATION_OLD_EXECUTABLE_SHA256")
          },
          "published_dmg" => {
            "used" => false,
            "path" => nil,
            "sha256" => nil
          }
        },
        "candidate" => {
          "mode" => "debug_ui_test_direct_app_support",
          "configuration" => "Debug",
          "signing" => "unsigned",
          "bundle_id" => ENV.fetch("ATTESTATION_CANDIDATE_BUNDLE_ID"),
          "product_name" => ENV.fetch("ATTESTATION_CANDIDATE_PRODUCT_NAME"),
          "version" => ENV.fetch("ATTESTATION_CANDIDATE_VERSION"),
          "build" => ENV.fetch("ATTESTATION_CANDIDATE_BUILD"),
          "executable_sha256" => ENV.fetch("ATTESTATION_CANDIDATE_EXECUTABLE_SHA256"),
          "sqlcipher_framework_sha256" => ENV.fetch("ATTESTATION_CANDIDATE_SQLCIPHER_SHA256"),
          "upgraded_database_sha256" => ENV.fetch("ATTESTATION_CANDIDATE_DATABASE_SHA256"),
          "uses_fixed_test_key" => true,
          "uses_app_support_override" => true
        },
        "database_schema" => {
          "previous_migration_count" => 5,
          "candidate_migration_count" => 11,
          "candidate_only_table_count" => 8,
          "preserved_sentinel_domains" => 7
        },
        "checks" => {
          "previous_schema_created" => true,
          "plaintext_to_sqlcipher_upgrade" => true,
          "candidate_integrity" => true,
          "candidate_projection" => true,
          "rollback_backup_unchanged" => true,
          "previous_source_rollback_read" => true,
          "generated_preferences_cleaned" => true,
          "temporary_data_removed" => true
        },
        "log" => {
          "file" => ENV.fetch("ATTESTATION_LOG_FILE"),
          "size" => log_size,
          "sha256" => ENV.fetch("ATTESTATION_LOG_SHA256")
        },
        "limitations" => [
          "The previous app is a source safety build, not the published v1.0.5 DMG.",
          "The candidate is an unsigned Debug UI-test build with a fixed test key.",
          "This does not satisfy the external published-binary clean-account upgrade gate."
        ]
      }

      File.open(ENV.fetch("ATTESTATION_STAGING_PATH"), File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(JSON.pretty_generate(manifest) << "\n")
        file.flush
        file.fsync
      end
    '

  mv -- "$staging_path" "$ATTESTATION_PATH"
}

cleanup() {
  local original_status=$?
  local safe_to_remove=1
  local cleanup_succeeded=1
  local log_sha256=""
  local log_size=""
  trap - EXIT
  if [[ -n "$CANDIDATE_PID" ]] && ! gentle_stop "$CANDIDATE_PID" "candidate app"; then
    safe_to_remove=0
  fi
  if [[ -n "$OLD_PID" ]] && ! gentle_stop "$OLD_PID" "v1.0.5 app"; then
    safe_to_remove=0
  fi

  if [[ "$safe_to_remove" == "1" ]]; then
    if ! cleanup_generated_preferences; then
      cleanup_succeeded=0
    fi
    if ! remove_exact_temporary_path "$TEMP_ROOT" || [[ -e "$TEMP_ROOT" ]]; then
      cleanup_succeeded=0
      echo "Cleanup failed; the exact temporary root remains: ${TEMP_ROOT}" >&2
    else
      echo "Removed the unique drill home/container and temporary build/data root."
    fi
  else
    cleanup_succeeded=0
    echo "A drill app is still running, so its temporary files were deliberately left in place: ${TEMP_ROOT}" >&2
  fi
  if [[ "$original_status" == "0" && "$cleanup_succeeded" != "1" ]]; then
    original_status=1
  fi

  # Close the process-substitution writer before hashing the log. Nothing written after this
  # point is part of the attested log, so the digest cannot race tee or become self-referential.
  exec 1>&3 2>&4
  if [[ -n "$LOG_TEE_PID" ]] && ! wait "$LOG_TEE_PID"; then
    echo "Upgrade-drill evidence tee failed." >&2
    original_status=1
  fi

  if [[ "$original_status" == "0" && "$DRILL_SUCCEEDED" == "1" ]]; then
    log_sha256="$(shasum -a 256 "$REPORT_PATH" | awk '{print tolower($1)}')"
    log_size="$(/usr/bin/ruby -e 'puts File.size(ARGV.fetch(0))' "$REPORT_PATH")"
    if ! write_passed_attestation "$log_sha256" "$log_size"; then
      echo "Could not write the passed upgrade-drill attestation." >&2
      original_status=1
    fi
  elif [[ "$original_status" == "0" ]]; then
    echo "Upgrade drill exited without reaching its PASS boundary; refusing attestation." >&2
    original_status=1
  fi

  if [[ "$original_status" == "0" ]]; then
    local pointer_staging="${CANONICAL_REPORT_POINTER}.tmp.$$"
    printf '%s\n' "$(basename "$ATTESTATION_PATH")" > "$pointer_staging"
    mv -f -- "$pointer_staging" "$CANONICAL_REPORT_POINTER"
    echo "Upgrade-drill attestation: ${ATTESTATION_PATH}"
    echo "Canonical passed-attestation pointer: ${CANONICAL_REPORT_POINTER}"
  fi
  exit "$original_status"
}
trap cleanup EXIT

process_has_readable_open_database() {
  local pid="$1"
  local database="$2"
  local database_directory
  local physical_database
  local open_files
  if ! database_directory="$(cd "$(dirname "$database")" && pwd -P)"; then
    return 1
  fi
  physical_database="${database_directory}/$(basename "$database")"
  if ! open_files="$(/usr/sbin/lsof -a -p "$pid" -Fan -- "$physical_database" 2>/dev/null)"; then
    return 1
  fi
  { printf '%s\n' "$open_files" | /usr/bin/grep -Fqx "n${physical_database}" \
      || printf '%s\n' "$open_files" | /usr/bin/grep -Fqx "n${database}"; } \
    && printf '%s\n' "$open_files" | /usr/bin/grep -Eq '^a[ru]$'
}

wait_for_v105_schema() {
  local database="$1"
  local pid="$2"
  local log_path="$3"
  local attempt
  local observed_header="unavailable"
  local observed_schema="unreadable"
  local observed_database_access="not-open"
  local sqlite_error_path="${TEMP_ROOT}/v1.0.5-schema-readiness-sqlite.err"
  for attempt in $(seq 1 600); do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      tail -n 80 "$log_path" >&2 || true
      fail "v1.0.5 exited before creating its production schema"
    fi
    observed_header="$(header_hex "$database" 2>/dev/null || true)"
    observed_database_access="not-open"
    : > "$sqlite_error_path"
    if [[ "$observed_header" == "$PLAIN_SQLITE_HEADER" ]]; then
      observed_schema="$(sqlite_scalar "$database" "$V105_SCHEMA_READINESS_SQL" 2>"$sqlite_error_path" || true)"
      if [[ "$observed_schema" == "8|5|5" ]] && process_has_readable_open_database "$pid" "$database"; then
        observed_database_access="read-capable-open"
        if ! kill -0 "$pid" >/dev/null 2>&1; then
          tail -n 80 "$log_path" >&2 || true
          fail "v1.0.5 exited after opening the complete production archive"
        fi
        echo "v1.0.5 process has the complete production archive open for reading (8 required tables, exactly 5 required migrations)."
        return 0
      fi
    fi
    sleep 0.1
  done
  echo "Last v1.0.5 schema observation: header=${observed_header:-unavailable}, named_tables|named_migrations|all_migrations=${observed_schema:-unreadable}, process_access=${observed_database_access}" >&2
  if [[ -s "$sqlite_error_path" ]]; then
    echo "Last v1.0.5 SQLite readiness error:" >&2
    tail -n 20 "$sqlite_error_path" >&2 || true
  fi
  tail -n 80 "$log_path" >&2 || true
  fail "timed out waiting for the complete v1.0.5 production schema"
}

wait_for_candidate_upgrade() {
  local database="$1"
  local pid="$2"
  local app_frameworks="$3"
  local log_path="$4"
  local inspector_log="${TEMP_ROOT}/candidate-inspection.log"
  local deadline_epoch=$(( $(date +%s) + 90 ))
  while [[ "$(date +%s)" -lt "$deadline_epoch" ]]; do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      tail -n 100 "$log_path" >&2 || true
      fail "the candidate exited before the upgrade could be verified"
    fi
    if [[ -f "$database" ]] && [[ "$(header_hex "$database" 2>/dev/null || true)" != "$PLAIN_SQLITE_HEADER" ]]; then
      if DYLD_FRAMEWORK_PATH="$app_frameworks" "$INSPECTOR_BINARY" "$database" >"$inspector_log" 2>&1; then
        cat "$inspector_log"
        return 0
      fi
    fi
    sleep 0.1
  done
  cat "$inspector_log" >&2 2>/dev/null || true
  tail -n 100 "$log_path" >&2 || true
  fail "timed out waiting for the candidate to encrypt, migrate, and project the v1.0.5 archive"
}

[[ -f "$PROJECT_PATH/project.pbxproj" ]] || fail "run this script from a Chronicle source checkout"
[[ -f "$INSPECTOR_SOURCE" ]] || fail "missing SQLCipher drill inspector source"
[[ -f "$SOURCE_FINGERPRINT_TOOL" && ! -L "$SOURCE_FINGERPRINT_TOOL" ]] || fail "missing safe release source fingerprint tool"
command -v git >/dev/null || fail "git is required"
command -v xcodebuild >/dev/null || fail "Xcode command-line tools are required"
command -v xcrun >/dev/null || fail "xcrun is required"
command -v codesign >/dev/null || fail "codesign is required"
command -v /usr/bin/sqlite3 >/dev/null || fail "the system sqlite3 CLI is required"
command -v /usr/bin/xxd >/dev/null || fail "xxd is required"
[[ -x /usr/sbin/lsof ]] || fail "the system lsof utility is required"

PREVIOUS_COMMIT="$(git -C "$ROOT_DIR" rev-parse "refs/tags/${PREVIOUS_TAG}^{commit}" 2>/dev/null)" \
  || fail "the local ${PREVIOUS_TAG} tag is missing"
PREVIOUS_TREE="$(git -C "$ROOT_DIR" rev-parse "${PREVIOUS_COMMIT}^{tree}")"
CANDIDATE_HEAD="$(git -C "$ROOT_DIR" rev-parse HEAD)"
CANDIDATE_BRANCH="$(git -C "$ROOT_DIR" symbolic-ref --short -q HEAD || printf 'DETACHED')"
CANDIDATE_SOURCE_FINGERPRINT="$(candidate_source_fingerprint)"
if [[ "$(candidate_source_dirty)" == "true" ]]; then
  CANDIDATE_WORKTREE_DIRTY=1
  CANDIDATE_WORKTREE_STATE="dirty (tracked changes and/or release-input untracked files are included in the fingerprint)"
else
  CANDIDATE_WORKTREE_DIRTY=0
  CANDIDATE_WORKTREE_STATE="clean"
fi
if [[ "$PREVIOUS_TAG" != "v1.0.5" ]]; then
  fail "this drill's schema and preservation assertions are reviewed specifically for v1.0.5"
fi
if [[ -n "$PACKAGE_CACHE" ]]; then
  [[ -d "$PACKAGE_CACHE" ]] || fail "UPGRADE_DRILL_CLONED_SOURCE_PACKAGES_DIR is not a directory: ${PACKAGE_CACHE}"
  PACKAGE_ARGS=(
    -clonedSourcePackagesDirPath "$PACKAGE_CACHE"
    -disableAutomaticPackageResolution
  )
fi

echo "Chronicle previous-release upgrade/rollback drill"
echo "Previous tag: ${PREVIOUS_TAG} (${PREVIOUS_COMMIT})"
echo "Candidate source: ${ROOT_DIR}"
echo "Candidate HEAD: ${CANDIDATE_HEAD}"
echo "Candidate branch: ${CANDIDATE_BRANCH}"
echo "Candidate source fingerprint: ${CANDIDATE_SOURCE_FINGERPRINT}"
echo "Candidate worktree: ${CANDIDATE_WORKTREE_STATE}"
echo "Old bundle identity: ${OLD_BUNDLE_ID}"
echo "Candidate bundle identity: ${CANDIDATE_BUNDLE_ID}"
echo "All archive data is non-sensitive sentinel data under one unique CFFIXED_USER_HOME/container."
echo "Production Chronicle bundle/container paths are not used."
echo "SecurityAgent is never queried, clicked, or terminated by this script."

mkdir -p "$OLD_SOURCE"
git -C "$ROOT_DIR" archive "$PREVIOUS_COMMIT" | tar -x -C "$OLD_SOURCE"

echo "Building the exact-${PREVIOUS_TAG}-tag Release-source safety build with an ad-hoc-signed, unique runtime identity..."
xcodebuild \
  -quiet \
  -project "${OLD_SOURCE}/Chronicle.xcodeproj" \
  -scheme Chronicle \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$OLD_DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY=- \
  ENABLE_APP_SANDBOX=NO \
  PRODUCT_BUNDLE_IDENTIFIER="$OLD_BUNDLE_ID" \
  PRODUCT_NAME="$OLD_PRODUCT_NAME" \
  INFOPLIST_KEY_CFBundleName="$OLD_PRODUCT_NAME" \
  INFOPLIST_KEY_CFBundleDisplayName="$OLD_PRODUCT_NAME" \
  build

OLD_APP="$(find "${OLD_DERIVED_DATA}/Build/Products/Release" -maxdepth 1 -type d -name '*.app' -print -quit)"
[[ -n "$OLD_APP" ]] || fail "could not locate the built ${PREVIOUS_TAG} app"
OLD_EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${OLD_APP}/Contents/Info.plist")"
OLD_BUILT_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${OLD_APP}/Contents/Info.plist")"
OLD_BUILT_APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "${OLD_APP}/Contents/Info.plist")"
assert_equal "$OLD_BUNDLE_ID" "$OLD_BUILT_BUNDLE_ID" "v1.0.5 source safety-build bundle isolation"
assert_equal "$OLD_PRODUCT_NAME" "$OLD_BUILT_APP_NAME" "v1.0.5 source safety-build app-name isolation"
codesign --verify --deep --strict "$OLD_APP"
OLD_EXECUTABLE_SHA256="$(shasum -a 256 "${OLD_APP}/Contents/MacOS/${OLD_EXECUTABLE_NAME}" | awk '{print tolower($1)}')"
OLD_ENTITLEMENTS="$(codesign -d --entitlements :- "$OLD_APP" 2>&1 || true)"
if printf '%s' "$OLD_ENTITLEMENTS" | tr '\n' ' ' | grep -Eq '<key>com.apple.security.app-sandbox</key>[[:space:]]*<true/>'; then
  fail "the v1.0.5 safety build unexpectedly retained App Sandbox and could escape CFFIXED_USER_HOME"
fi

OLD_LOG="${TEMP_ROOT}/v1.0.5-first-launch.log"
mkdir -p "$ISOLATED_HOME"
echo "Launching ${PREVIOUS_TAG} to create its production schema in the unique temporary home/container..."
env \
  CFFIXED_USER_HOME="$ISOLATED_HOME" \
  "${OLD_APP}/Contents/MacOS/${OLD_EXECUTABLE_NAME}" >"$OLD_LOG" 2>&1 &
OLD_PID=$!
wait_for_v105_schema "$OLD_DATABASE" "$OLD_PID" "$OLD_LOG"
gentle_stop "$OLD_PID" "v1.0.5 app" || fail "could not stop v1.0.5 gently after schema creation"
OLD_PID=""

assert_equal "8" "$(sqlite_scalar "$OLD_DATABASE" "$V105_PRODUCTION_TABLES_SQL")" "v1.0.5 production tables"
assert_equal "5" "$(sqlite_scalar "$OLD_DATABASE" "$V105_PRODUCTION_MIGRATIONS_SQL")" "v1.0.5 production migrations"
assert_equal "5" "$(sqlite_scalar "$OLD_DATABASE" "$V105_ALL_MIGRATIONS_SQL")" "v1.0.5 exact migration set"

echo "Writing representative, non-sensitive sentinels through the exact-tag safety-build production schema..."
/usr/bin/sqlite3 -batch -bail "$OLD_DATABASE" <<'SQL'
PRAGMA wal_checkpoint(TRUNCATE);
BEGIN IMMEDIATE;
INSERT INTO Tags (name, color) VALUES ('Upgrade Drill', '#123456');
INSERT INTO Activities (
  start_time, end_time, app_name, bundle_id, window_title, is_idle,
  tag_id, rule_tag_id, user_tag_override_id, effective_tag_id
)
SELECT
  1735689600, 1735691400, 'Chronicle Upgrade Drill',
  'com.chronicle.upgrade-drill.sentinel', 'Release rehearsal sentinel', 0,
  id, id, NULL, id
FROM Tags WHERE name='Upgrade Drill';
INSERT INTO Markers (timestamp, text)
VALUES (1735690200, 'Chronicle upgrade drill marker');
INSERT INTO MarkerSpans (start_time, end_time, text)
VALUES (1735689900, 1735690800, 'Chronicle upgrade drill span');
INSERT INTO Rules (
  name, enabled, match_bundle_id, match_app_name, match_window_title,
  match_mode, tag_id, priority
)
SELECT
  'Chronicle upgrade drill rule', 1, 'com.chronicle.upgrade-drill.sentinel',
  'Chronicle Upgrade Drill', 'Release rehearsal sentinel', 'contains', id, 500
FROM Tags WHERE name='Upgrade Drill';
INSERT INTO AppMappings (bundle_id, app_name, tag_id, updated_at, tagging_mode)
SELECT
  'com.chronicle.upgrade-drill.sentinel', 'Chronicle Upgrade Drill', id,
  1735689600, 'auto'
FROM Tags WHERE name='Upgrade Drill';
INSERT INTO RawEvents (ts, type, bundle_id, app_name, window_title, payload)
VALUES (
  1735689600, 'app_activated', 'com.chronicle.upgrade-drill.sentinel',
  'Chronicle Upgrade Drill', 'Release rehearsal sentinel', '{"drill":true}'
);
COMMIT;
PRAGMA wal_checkpoint(TRUNCATE);
SQL
chmod 600 "$OLD_DATABASE"

assert_equal "1" "$(sqlite_scalar "$OLD_DATABASE" "SELECT COUNT(*) FROM Activities WHERE bundle_id='com.chronicle.upgrade-drill.sentinel';")" "v1.0.5 activity sentinel"
assert_equal "1" "$(sqlite_scalar "$OLD_DATABASE" "SELECT COUNT(*) FROM Markers WHERE text='Chronicle upgrade drill marker';")" "v1.0.5 marker sentinel"
assert_equal "1" "$(sqlite_scalar "$OLD_DATABASE" "SELECT COUNT(*) FROM MarkerSpans WHERE text='Chronicle upgrade drill span';")" "v1.0.5 marker span sentinel"
assert_equal "1" "$(sqlite_scalar "$OLD_DATABASE" "SELECT COUNT(*) FROM Tags WHERE name='Upgrade Drill';")" "v1.0.5 tag sentinel"
assert_equal "1" "$(sqlite_scalar "$OLD_DATABASE" "SELECT COUNT(*) FROM Rules WHERE name='Chronicle upgrade drill rule';")" "v1.0.5 rule sentinel"
assert_equal "1" "$(sqlite_scalar "$OLD_DATABASE" "SELECT COUNT(*) FROM AppMappings WHERE bundle_id='com.chronicle.upgrade-drill.sentinel';")" "v1.0.5 mapping sentinel"
assert_equal "1" "$(sqlite_scalar "$OLD_DATABASE" "SELECT COUNT(*) FROM RawEvents WHERE payload='{\"drill\":true}';")" "v1.0.5 raw-event sentinel"
assert_equal "ok" "$(sqlite_scalar "$OLD_DATABASE" 'PRAGMA integrity_check;')" "v1.0.5 integrity"

cp -p "$OLD_DATABASE" "$PLAINTEXT_BACKUP"
chmod 600 "$PLAINTEXT_BACKUP"
BACKUP_SHA256="$(shasum -a 256 "$PLAINTEXT_BACKUP" | awk '{print $1}')"
assert_equal "$PLAIN_SQLITE_HEADER" "$(header_hex "$PLAINTEXT_BACKUP")" "rollback backup format"
echo "Created owner-only plaintext rollback backup (SHA-256 ${BACKUP_SHA256})."

echo "Building the current candidate as a real Debug app with a unique runtime identity..."
xcodebuild \
  -quiet \
  -project "$PROJECT_PATH" \
  -scheme Chronicle \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$CANDIDATE_DERIVED_DATA" \
  "${PACKAGE_ARGS[@]}" \
  CODE_SIGNING_ALLOWED=NO \
  PRODUCT_BUNDLE_IDENTIFIER="$CANDIDATE_BUNDLE_ID" \
  PRODUCT_NAME="$CANDIDATE_PRODUCT_NAME" \
  INFOPLIST_KEY_CFBundleName="$CANDIDATE_PRODUCT_NAME" \
  INFOPLIST_KEY_CFBundleDisplayName="$CANDIDATE_PRODUCT_NAME" \
  build

CANDIDATE_APP="$(find "${CANDIDATE_DERIVED_DATA}/Build/Products/Debug" -maxdepth 1 -type d -name '*.app' -print -quit)"
[[ -n "$CANDIDATE_APP" ]] || fail "could not locate the built candidate app"
CANDIDATE_EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${CANDIDATE_APP}/Contents/Info.plist")"
CANDIDATE_BUILT_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${CANDIDATE_APP}/Contents/Info.plist")"
CANDIDATE_APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${CANDIDATE_APP}/Contents/Info.plist")"
CANDIDATE_APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${CANDIDATE_APP}/Contents/Info.plist")"
assert_equal "$CANDIDATE_BUNDLE_ID" "$CANDIDATE_BUILT_BUNDLE_ID" "candidate bundle isolation"
CANDIDATE_FRAMEWORKS="${CANDIDATE_APP}/Contents/Frameworks"
SQLCIPHER_FRAMEWORK="${CANDIDATE_FRAMEWORKS}/SQLCipher.framework"
[[ -d "$SQLCIPHER_FRAMEWORK" ]] || fail "the candidate app does not contain SQLCipher.framework"
CANDIDATE_EXECUTABLE_SHA256="$(shasum -a 256 "${CANDIDATE_APP}/Contents/MacOS/${CANDIDATE_EXECUTABLE_NAME}" | awk '{print tolower($1)}')"
CANDIDATE_SQLCIPHER_BINARY="$(find "$SQLCIPHER_FRAMEWORK" -type f -name SQLCipher -print -quit)"
[[ -n "$CANDIDATE_SQLCIPHER_BINARY" ]] || fail "could not locate the candidate SQLCipher binary"
CANDIDATE_SQLCIPHER_SHA256="$(shasum -a 256 "$CANDIDATE_SQLCIPHER_BINARY" | awk '{print tolower($1)}')"

SQLCIPHER_HEADER=""
if [[ -n "$PACKAGE_CACHE" ]]; then
  SQLCIPHER_HEADER="$(find -L "$PACKAGE_CACHE" -path '*/macos-arm64_x86_64/SQLCipher.framework/Headers/sqlite3.h' -print -quit)"
fi
if [[ -z "$SQLCIPHER_HEADER" ]]; then
  SQLCIPHER_HEADER="$(find -L "${CANDIDATE_DERIVED_DATA}/SourcePackages" -path '*/macos-arm64_x86_64/SQLCipher.framework/Headers/sqlite3.h' -print -quit 2>/dev/null || true)"
fi
[[ -f "$SQLCIPHER_HEADER" ]] || fail "could not locate the resolved SQLCipher sqlite3.h for the independent inspector"
SQLCIPHER_HEADER_DIR="$(dirname "$SQLCIPHER_HEADER")"

xcrun clang \
  -std=c11 \
  -Wall \
  -Wextra \
  -Werror \
  -I "$SQLCIPHER_HEADER_DIR" \
  -F "$CANDIDATE_FRAMEWORKS" \
  -framework SQLCipher \
  -Wl,-rpath,"$CANDIDATE_FRAMEWORKS" \
  "$INSPECTOR_SOURCE" \
  -o "$INSPECTOR_BINARY"
if ! otool -L "$INSPECTOR_BINARY" | grep -q '@rpath/SQLCipher.framework/'; then
  fail "the independent inspector did not link SQLCipher.framework"
fi
if ! otool -l "$INSPECTOR_BINARY" | grep -Fq "$CANDIDATE_FRAMEWORKS"; then
  fail "the independent inspector does not carry the candidate app framework rpath"
fi

mkdir -p "$CANDIDATE_SUPPORT"
cp -p "$PLAINTEXT_BACKUP" "${CANDIDATE_SUPPORT}/activity.sqlite"
CANDIDATE_DATABASE="${CANDIDATE_SUPPORT}/activity.sqlite"
CANDIDATE_LOG="${TEMP_ROOT}/candidate-launch.log"

echo "Launching the candidate against a copied v1.0.5 archive through CHRONICLE_UI_TEST_APP_SUPPORT_DIR..."
env \
  CFFIXED_USER_HOME="$ISOLATED_HOME" \
  CHRONICLE_UI_TEST_MODE=1 \
  CHRONICLE_UI_TEST_RESET_STATE=1 \
  CHRONICLE_UI_TEST_LANGUAGE=en \
  CHRONICLE_UI_TEST_ROUTE=dashboard \
  CHRONICLE_UI_TEST_APP_SUPPORT_DIR="$CANDIDATE_SUPPORT" \
  CHRONICLE_UI_TEST_DEFAULTS_SUITE="$CANDIDATE_DEFAULTS_DOMAIN" \
  "${CANDIDATE_APP}/Contents/MacOS/${CANDIDATE_EXECUTABLE_NAME}" >"$CANDIDATE_LOG" 2>&1 &
CANDIDATE_PID=$!
wait_for_candidate_upgrade "$CANDIDATE_DATABASE" "$CANDIDATE_PID" "$CANDIDATE_FRAMEWORKS" "$CANDIDATE_LOG"
assert_equal "$BACKUP_SHA256" "$(shasum -a 256 "$PLAINTEXT_BACKUP" | awk '{print $1}')" "untouched rollback backup"
if [[ "$(header_hex "$CANDIDATE_DATABASE")" == "$PLAIN_SQLITE_HEADER" ]]; then
  fail "the candidate archive still has a plaintext SQLite header"
fi
if /usr/bin/sqlite3 -batch "$CANDIDATE_DATABASE" 'SELECT COUNT(*) FROM sqlite_master;' >/dev/null 2>&1; then
  fail "the system plaintext sqlite3 CLI unexpectedly read the encrypted candidate archive"
fi
gentle_stop "$CANDIDATE_PID" "candidate app" || fail "could not stop the candidate gently after upgrade verification"
CANDIDATE_PID=""
CANDIDATE_DATABASE_SHA256="$(shasum -a 256 "$CANDIDATE_DATABASE" | awk '{print tolower($1)}')"

echo "Restoring the untouched plaintext backup into the unique v1.0.5 safety-build data root..."
remove_exact_temporary_path "$OLD_SUPPORT"
mkdir -p "$OLD_SUPPORT"
cp -p "$PLAINTEXT_BACKUP" "$OLD_DATABASE"
assert_equal "$BACKUP_SHA256" "$(shasum -a 256 "$OLD_DATABASE" | awk '{print $1}')" "restored rollback copy"

ROLLBACK_LOG="${TEMP_ROOT}/v1.0.5-rollback-launch.log"
echo "Relaunching the exact-${PREVIOUS_TAG}-tag Release-source safety build against the restored rollback copy..."
env \
  CFFIXED_USER_HOME="$ISOLATED_HOME" \
  "${OLD_APP}/Contents/MacOS/${OLD_EXECUTABLE_NAME}" >"$ROLLBACK_LOG" 2>&1 &
OLD_PID=$!
wait_for_v105_schema "$OLD_DATABASE" "$OLD_PID" "$ROLLBACK_LOG"
for attempt in $(seq 1 300); do
  if [[ "$(sqlite_scalar "$OLD_DATABASE" "SELECT COUNT(*) FROM Activities WHERE bundle_id='com.chronicle.upgrade-drill.sentinel';" 2>/dev/null || true)" == "1" ]]; then
    break
  fi
  sleep 0.1
done
assert_equal "1" "$(sqlite_scalar "$OLD_DATABASE" "SELECT COUNT(*) FROM Activities WHERE bundle_id='com.chronicle.upgrade-drill.sentinel';")" "rollback activity readability"
assert_equal "1" "$(sqlite_scalar "$OLD_DATABASE" "SELECT COUNT(*) FROM Markers WHERE text='Chronicle upgrade drill marker';")" "rollback marker readability"
assert_equal "1" "$(sqlite_scalar "$OLD_DATABASE" "SELECT COUNT(*) FROM RawEvents WHERE payload='{\"drill\":true}';")" "rollback raw-event readability"
assert_equal "5" "$(sqlite_scalar "$OLD_DATABASE" 'SELECT COUNT(*) FROM SchemaMigrations;')" "rollback v1.0.5 migration set"
assert_equal "ok" "$(sqlite_scalar "$OLD_DATABASE" 'PRAGMA integrity_check;')" "rollback integrity"
gentle_stop "$OLD_PID" "v1.0.5 rollback app" || fail "could not stop v1.0.5 gently after rollback verification"
OLD_PID=""
assert_equal "$BACKUP_SHA256" "$(shasum -a 256 "$PLAINTEXT_BACKUP" | awk '{print $1}')" "rollback backup remained untouched"
assert_equal "$CANDIDATE_SOURCE_FINGERPRINT" "$(candidate_source_fingerprint)" "candidate source remained unchanged during drill"

echo "PASS: exact-${PREVIOUS_TAG}-tag Release-source safety-build schema and representative sample validated."
echo "PASS: current Debug app encrypted, migrated, preserved, and projected the copied archive."
echo "PASS: untouched plaintext backup restored, opened read-capably by the exact-${PREVIOUS_TAG}-tag safety-build relaunch, and independently verified readable."
echo "Evidence log: ${REPORT_PATH}"
DRILL_SUCCEEDED=1
