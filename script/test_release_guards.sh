#!/usr/bin/env bash
set -euo pipefail

fake_tool_main() {
  local tool_name
  local action
  local argument
  local mountpoint=""
  local target_path=""
  local architecture=""
  local endpoint=""
  local is_display=0

  tool_name="$(basename "$0")"
  case "$tool_name" in
    hdiutil)
      action="${1:-}"
      case "$action" in
        verify|detach)
          return 0
          ;;
        attach)
          shift
          while (( $# > 0 )); do
            if [[ "$1" == "-mountpoint" ]]; then
              shift
              mountpoint="${1:-}"
            fi
            shift || true
          done
          [[ -n "$mountpoint" ]]
          mkdir -p "$mountpoint"
          cp -R "$FIXTURE_APP_PATH" "$mountpoint/Chronicle.app"
          if [[ "${FIXTURE_MISSING_DMG_LICENSE:-0}" != "1" ]]; then
            cp "$FIXTURE_DMG_LICENSE_PATH" "$mountpoint/LICENSE"
          fi
          if [[ "${FIXTURE_MISSING_DMG_NOTICE:-0}" != "1" ]]; then
            cp "$FIXTURE_DMG_NOTICE_PATH" "$mountpoint/ThirdPartyNotices.md"
          fi
          return 0
          ;;
      esac
      ;;
    plutil)
      case "${2:-}" in
        CFBundleShortVersionString) printf '%s\n' "${FIXTURE_APP_VERSION:-9.9.9}" ;;
        CFBundleVersion) printf '%s\n' "${FIXTURE_APP_BUILD:-999}" ;;
        LSMinimumSystemVersion) printf '%s\n' "${FIXTURE_MINIMUM_MACOS:-14.0}" ;;
        *) return 1 ;;
      esac
      return 0
      ;;
    file)
      for argument in "$@"; do
        target_path="$argument"
      done
      if [[ "${FIXTURE_MAIN_NOT_MACHO:-0}" == "1" && "$target_path" == */Contents/MacOS/Chronicle ]]; then
        echo "ASCII text executable"
        return 0
      fi
      case "$target_path" in
        */Contents/MacOS/Chronicle|*/SQLCipher.framework/*/SQLCipher)
          echo "Mach-O universal binary with 2 architectures"
          ;;
        *)
          echo "ASCII text"
          ;;
      esac
      return 0
      ;;
    lipo)
      for argument in "$@"; do
        target_path="$argument"
      done
      if [[ "${FIXTURE_BAD_SQLCIPHER_ARCH:-0}" == "1" && "$target_path" == *"/SQLCipher.framework/"* ]]; then
        echo "arm64"
      else
        echo "x86_64 arm64"
      fi
      return 0
      ;;
    vtool)
      while (( $# > 0 )); do
        if [[ "$1" == "-arch" ]]; then
          shift
          architecture="${1:-}"
        else
          target_path="$1"
        fi
        shift || true
      done
      if [[ "${FIXTURE_BAD_SQLCIPHER_MINOS:-0}" == "1" && "$target_path" == *"/SQLCipher.framework/"* && "$architecture" == "x86_64" ]]; then
        echo "      platform MACOS"
        echo "         minos 15.0"
      elif [[ "${FIXTURE_COMPATIBLE_SQLCIPHER_MINOS:-0}" == "1" && "$target_path" == *"/SQLCipher.framework/"* && "$architecture" == "x86_64" ]]; then
        echo "          cmd LC_VERSION_MIN_MACOSX"
        echo "      version 10.13"
      elif [[ "${FIXTURE_COMPATIBLE_SQLCIPHER_MINOS:-0}" == "1" && "$target_path" == *"/SQLCipher.framework/"* ]]; then
        echo "      platform MACOS"
        echo "         minos 11.0"
      elif [[ "${FIXTURE_BAD_MAIN_MINOS:-0}" == "1" && "$target_path" == *"/Contents/MacOS/Chronicle"* ]]; then
        echo "      platform MACOS"
        echo "         minos 13.0"
      else
        echo "      platform MACOS"
        echo "         minos ${FIXTURE_MINIMUM_MACOS:-14.0}"
      fi
      return 0
      ;;
    xcrun)
      if [[ "${FIXTURE_UNSTAPLED:-0}" == "1" ]]; then
        echo "fixture does not have a ticket stapled to it" >&2
        return 1
      fi
      if [[ "${FIXTURE_SIGNED:-0}" == "1" || "${FIXTURE_STAPLED:-0}" == "1" ]]; then
        return 0
      fi
      echo "fixture does not have a ticket stapled to it" >&2
      return 1
      ;;
    codesign)
      for argument in "$@"; do
        if [[ "$argument" == "-d" ]]; then
          is_display=1
        fi
      done
      if [[ "$is_display" == "1" ]]; then
        if [[ "${FIXTURE_NO_DEVELOPER_ID:-0}" != "1" ]]; then
          echo "Authority=Developer ID Application: Fixture (${FIXTURE_TEAM_IDENTIFIER:-ABCDE12345})" >&2
        else
          echo "Authority=Apple Development: Fixture (${FIXTURE_TEAM_IDENTIFIER:-ABCDE12345})" >&2
        fi
        echo "TeamIdentifier=${FIXTURE_TEAM_IDENTIFIER:-ABCDE12345}" >&2
        if [[ "${FIXTURE_NO_HARDENED_RUNTIME:-0}" != "1" ]]; then
          echo "CodeDirectory v=20500 size=123 flags=0x10000(runtime) hashes=1+7 location=embedded" >&2
        else
          echo "CodeDirectory v=20500 size=123 flags=0x0(none) hashes=1+7 location=embedded" >&2
        fi
        if [[ "${FIXTURE_NO_TIMESTAMP:-0}" != "1" ]]; then
          echo "Timestamp=Jul 23, 2026 at 12:00:00" >&2
        fi
        return 0
      fi
      if [[ "${FIXTURE_SIGNED:-0}" == "1" ]]; then
        return 0
      fi
      echo "fixture has no valid Developer ID signature" >&2
      return 1
      ;;
    spctl)
      if [[ "${FIXTURE_SIGNED:-0}" == "1" && "${FIXTURE_GATEKEEPER_REJECTS:-0}" != "1" ]]; then
        echo "accepted"
        return 0
      fi
      echo "source=no usable signature" >&2
      return 1
      ;;
    xcodebuild)
      if [[ -n "${FIXTURE_ANALYZE_ARGS_PATH:-}" ]]; then
        printf '%s\n' "$@" > "$FIXTURE_ANALYZE_ARGS_PATH"
      fi
      if [[ "${FIXTURE_ANALYZE_FAIL:-0}" == "1" ]]; then
        echo "fixture Release Analyze failure"
        return 42
      fi
      echo "fixture universal Release Analyze"
      echo "** ANALYZE SUCCEEDED **"
      return 0
      ;;
    gh)
      for argument in "$@"; do
        case "$argument" in
          repos/*) endpoint="$argument" ;;
        esac
      done
      case "$endpoint" in
        *"/releases?per_page=100") cat "$FIXTURE_RELEASES_JSON" ;;
        *"/releases/assets/"*) cat "$FIXTURE_CHECKSUM_FILE" ;;
        *"/releases/latest") echo '{"tag_name":"v9.9.9"}' ;;
        *"/releases/"*) cat "$FIXTURE_EXACT_RELEASE_JSON" ;;
        *"/commits/"*) printf '%s\n' "${FIXTURE_SOURCE_COMMIT:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}" ;;
        *) echo "Unexpected fixture gh invocation: $*" >&2; return 1 ;;
      esac
      return 0
      ;;
  esac

  echo "Unknown release-guard fixture tool: ${tool_name}" >&2
  return 127
}

if [[ "${RELEASE_GUARD_FAKE_TOOL:-0}" == "1" ]]; then
  fake_tool_main "$@"
  exit $?
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/chronicle-release-guards.XXXXXX")"
FAKE_BIN="${TEMP_ROOT}/bin"
FIXTURE_APP_PATH="${TEMP_ROOT}/fixture/Chronicle.app"
FIXTURE_DMG="${TEMP_ROOT}/fixture.dmg"

cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

ruby "$ROOT_DIR/script/support/test_preferences_guard.rb" verify-source "$ROOT_DIR"
ruby "$ROOT_DIR/script/support/test_preferences_guard.rb" self-test

fail() {
  echo "release guard fixture failure: $*" >&2
  exit 1
}

expect_failure() {
  local expected_message="$1"
  local output_path="$2"
  shift 2
  if "$@" > "$output_path" 2>&1; then
    fail "command unexpectedly passed: $*"
  fi
  if ! grep -Fq "$expected_message" "$output_path"; then
    command cat "$output_path" >&2
    fail "expected failure message not found: $expected_message"
  fi
}

fingerprint_repo="${TEMP_ROOT}/fingerprint-repo"
mkdir -p "$fingerprint_repo/Chronicle" "$fingerprint_repo/script"
git -C "$fingerprint_repo" init -q
git -C "$fingerprint_repo" config user.name "Release Guard Fixture"
git -C "$fingerprint_repo" config user.email "release-guard@example.invalid"
printf 'tracked release input\n' > "$fingerprint_repo/README.md"
git -C "$fingerprint_repo" add README.md
git -C "$fingerprint_repo" commit -q -m fixture
fingerprint_base="$(ruby "$ROOT_DIR/script/support/release_source_fingerprint.rb" "$fingerprint_repo")"
printf 'unrelated personal document\n' > "$fingerprint_repo/Chronicle macOS notes.pdf"
fingerprint_with_pdf="$(ruby "$ROOT_DIR/script/support/release_source_fingerprint.rb" "$fingerprint_repo")"
[[ "$fingerprint_with_pdf" == "$fingerprint_base" ]] \
  || fail "untracked root PDF unexpectedly changed the release source fingerprint"
[[ "$(ruby "$ROOT_DIR/script/support/release_source_fingerprint.rb" "$fingerprint_repo" --dirty)" == "false" ]] \
  || fail "untracked root PDF unexpectedly made release inputs dirty"
printf 'untracked app source\n' > "$fingerprint_repo/Chronicle/UntrackedFixture.swift"
fingerprint_with_app="$(ruby "$ROOT_DIR/script/support/release_source_fingerprint.rb" "$fingerprint_repo")"
[[ "$fingerprint_with_app" != "$fingerprint_base" ]] \
  || fail "untracked Chronicle input did not change the release source fingerprint"
rm "$fingerprint_repo/Chronicle/UntrackedFixture.swift"
printf '#!/usr/bin/env bash\n' > "$fingerprint_repo/script/untracked-fixture.sh"
fingerprint_with_script="$(ruby "$ROOT_DIR/script/support/release_source_fingerprint.rb" "$fingerprint_repo")"
[[ "$fingerprint_with_script" != "$fingerprint_base" ]] \
  || fail "untracked script input did not change the release source fingerprint"
[[ "$(ruby "$ROOT_DIR/script/support/release_source_fingerprint.rb" "$fingerprint_repo" --dirty)" == "true" ]] \
  || fail "untracked release input did not make release inputs dirty"
rm "$fingerprint_repo/script/untracked-fixture.sh"
printf 'build/\n' > "$fingerprint_repo/.gitignore"
git -C "$fingerprint_repo" add .gitignore
git -C "$fingerprint_repo" commit -q -m ignore-build-output
fingerprint_before_ignored_source="$(ruby "$ROOT_DIR/script/support/release_source_fingerprint.rb" "$fingerprint_repo")"
mkdir -p "$fingerprint_repo/Chronicle/build"
printf 'ignored synchronized app source\n' > "$fingerprint_repo/Chronicle/build/IgnoredFixture.swift"
fingerprint_with_ignored_source="$(ruby "$ROOT_DIR/script/support/release_source_fingerprint.rb" "$fingerprint_repo")"
[[ "$fingerprint_with_ignored_source" != "$fingerprint_before_ignored_source" ]] \
  || fail "gitignored Chronicle synchronized source did not change the release source fingerprint"
[[ "$(ruby "$ROOT_DIR/script/support/release_source_fingerprint.rb" "$fingerprint_repo" --dirty)" == "true" ]] \
  || fail "gitignored Chronicle synchronized source did not make release inputs dirty"

upgrade_fixture_repo="${TEMP_ROOT}/upgrade-attestation-repo"
upgrade_fixture_dir="${TEMP_ROOT}/upgrade-attestation-fixtures"
upgrade_fixture_timestamp="20000101T000000Z"
upgrade_fixture_basename="previous-release-upgrade-drill-${upgrade_fixture_timestamp}"
upgrade_fixture_log="${upgrade_fixture_dir}/${upgrade_fixture_basename}.log"
upgrade_fixture_manifest_name="${upgrade_fixture_basename}.json"
upgrade_fixture_created_at="$(
  TZ=Asia/Shanghai /usr/bin/ruby -rtime -e \
    'puts Time.strptime(ARGV.fetch(0), "%Y%m%dT%H%M%S%z").utc.iso8601' \
    "$upgrade_fixture_timestamp"
)"
[[ "$upgrade_fixture_created_at" == "2000-01-01T00:00:00Z" ]] \
  || fail "upgrade attestation timestamp parsing is not independent of the local timezone"
grep -Fq \
  'Time.strptime(ENV.fetch("ATTESTATION_CREATED_AT"), "%Y%m%dT%H%M%S%z").utc.iso8601' \
  "$ROOT_DIR/script/run_previous_release_upgrade_drill.sh" \
  || fail "upgrade drill writer does not parse its UTC timestamp with an explicit timezone"
mkdir -p "$upgrade_fixture_repo/script/support" "$upgrade_fixture_dir"
cp "$ROOT_DIR/script/support/release_source_fingerprint.rb" \
  "$upgrade_fixture_repo/script/support/release_source_fingerprint.rb"
printf 'upgrade attestation fixture repository\n' > "$upgrade_fixture_repo/README.md"
git -C "$upgrade_fixture_repo" init -q
git -C "$upgrade_fixture_repo" config user.name "Upgrade Attestation Fixture"
git -C "$upgrade_fixture_repo" config user.email "upgrade-attestation@example.invalid"
git -C "$upgrade_fixture_repo" add README.md script/support/release_source_fingerprint.rb
git -C "$upgrade_fixture_repo" commit -q -m fixture
git -C "$upgrade_fixture_repo" tag fixture-v1
printf 'bounded upgrade drill fixture log\n' > "$upgrade_fixture_log"
upgrade_fixture_commit="$(git -C "$upgrade_fixture_repo" rev-parse HEAD)"
upgrade_fixture_tree="$(git -C "$upgrade_fixture_repo" rev-parse 'HEAD^{tree}')"
upgrade_fixture_branch="$(git -C "$upgrade_fixture_repo" symbolic-ref --short HEAD)"
upgrade_fixture_fingerprint="$(
  ruby "$upgrade_fixture_repo/script/support/release_source_fingerprint.rb" "$upgrade_fixture_repo"
)"
ruby -rjson -rdigest -e '
  log_path, output_dir, fingerprint, commit, tree, branch, created_at = ARGV
  digest = "a" * 64
  manifest = {
    "schema_version" => 1,
    "attestation_type" => "chronicle_previous_release_upgrade_drill",
    "status" => "passed",
    "pass" => true,
    "created_at" => created_at,
    "source" => {
      "fingerprint_schema" => "chronicle-release-source-fingerprint-v1",
      "fingerprint" => fingerprint,
      "commit" => commit,
      "branch" => branch,
      "dirty" => false
    },
    "previous_release" => {
      "tag" => "fixture-v1",
      "resolved_commit" => commit,
      "source" => {
        "mode" => "git_archive_resolved_commit_release_safety_build",
        "archive_commit" => commit,
        "tree_oid" => tree,
        "configuration" => "Release",
        "bundle_id" => "com.example.previous",
        "product_name" => "PreviousFixture",
        "sandbox_enabled" => false,
        "executable_sha256" => digest
      },
      "published_dmg" => { "used" => false, "path" => nil, "sha256" => nil }
    },
    "candidate" => {
      "mode" => "debug_ui_test_direct_app_support",
      "configuration" => "Debug",
      "signing" => "unsigned",
      "bundle_id" => "com.example.candidate",
      "product_name" => "CandidateFixture",
      "version" => "1.1.0",
      "build" => "7",
      "executable_sha256" => digest,
      "sqlcipher_framework_sha256" => digest,
      "upgraded_database_sha256" => digest,
      "uses_fixed_test_key" => true,
      "uses_app_support_override" => true
    },
    "database_schema" => {
      "previous_migration_count" => 5,
      "candidate_migration_count" => 11,
      "candidate_only_table_count" => 8,
      "preserved_sentinel_domains" => 7
    },
    "checks" => %w[
      previous_schema_created plaintext_to_sqlcipher_upgrade candidate_integrity
      candidate_projection rollback_backup_unchanged previous_source_rollback_read
      generated_preferences_cleaned temporary_data_removed
    ].to_h { |check| [check, true] },
    "log" => {
      "file" => File.basename(log_path),
      "size" => File.size(log_path),
      "sha256" => Digest::SHA256.file(log_path).hexdigest
    },
    "limitations" => ["bounded fixture", "source safety build", "not a clean-account gate"]
  }
  variants = {
    "valid" => manifest,
    "stale-migration-count" => Marshal.load(Marshal.dump(manifest)),
    "stale-table-count" => Marshal.load(Marshal.dump(manifest)),
    "stale-created-at" => Marshal.load(Marshal.dump(manifest)),
    "offset-created-at" => Marshal.load(Marshal.dump(manifest)),
    "fractional-created-at" => Marshal.load(Marshal.dump(manifest)),
    "mismatched-log-timestamp" => Marshal.load(Marshal.dump(manifest))
  }
  variants.fetch("stale-migration-count").fetch("database_schema")["candidate_migration_count"] = 10
  variants.fetch("stale-table-count").fetch("database_schema")["candidate_only_table_count"] = 7
  variants.fetch("stale-created-at")["created_at"] = "1999-12-31T16:00:00Z"
  variants.fetch("offset-created-at")["created_at"] = "2000-01-01T00:00:00+00:00"
  variants.fetch("fractional-created-at")["created_at"] = "2000-01-01T00:00:00.000Z"
  variants.fetch("mismatched-log-timestamp").fetch("log")["file"] =
    "previous-release-upgrade-drill-20000101T000001Z.log"
  variants.each do |name, value|
    variant_dir = File.join(output_dir, name)
    Dir.mkdir(variant_dir)
    File.binwrite(File.join(variant_dir, value.fetch("log").fetch("file")), File.binread(log_path))
    File.write(
      File.join(variant_dir, "previous-release-upgrade-drill-20000101T000000Z.json"),
      JSON.pretty_generate(value) << "\n"
    )
  end
' \
  "$upgrade_fixture_log" \
  "$upgrade_fixture_dir" \
  "$upgrade_fixture_fingerprint" \
  "$upgrade_fixture_commit" \
  "$upgrade_fixture_tree" \
  "$upgrade_fixture_branch" \
  "$upgrade_fixture_created_at"

run_upgrade_attestation_verifier() {
  env UPGRADE_DRILL_PREVIOUS_TAG=fixture-v1 \
    ruby "$ROOT_DIR/script/support/verify_upgrade_drill_attestation.rb" \
      "$upgrade_fixture_repo" "$1"
}
run_upgrade_attestation_verifier "$upgrade_fixture_dir/valid/$upgrade_fixture_manifest_name" \
  > "${TEMP_ROOT}/upgrade-attestation-positive.out"
cp \
  "$upgrade_fixture_dir/valid/$upgrade_fixture_manifest_name" \
  "$upgrade_fixture_dir/valid/unsafe-manifest-name.json"
expect_failure \
  'manifest file name is unsafe: unsafe-manifest-name.json' \
  "${TEMP_ROOT}/upgrade-attestation-unsafe-manifest-name.out" \
  run_upgrade_attestation_verifier \
    "$upgrade_fixture_dir/valid/unsafe-manifest-name.json"
invalid_calendar_fixture_dir="$upgrade_fixture_dir/invalid-calendar-token"
invalid_calendar_manifest_name="previous-release-upgrade-drill-20000230T000000Z.json"
mkdir -p "$invalid_calendar_fixture_dir"
cp \
  "$upgrade_fixture_dir/valid/$upgrade_fixture_manifest_name" \
  "$invalid_calendar_fixture_dir/$invalid_calendar_manifest_name"
expect_failure \
  "manifest file name has an invalid UTC timestamp: $invalid_calendar_manifest_name" \
  "${TEMP_ROOT}/upgrade-attestation-invalid-calendar-token.out" \
  run_upgrade_attestation_verifier \
    "$invalid_calendar_fixture_dir/$invalid_calendar_manifest_name"
expect_failure \
  'database_schema.candidate_migration_count mismatch: expected 11, got 10' \
  "${TEMP_ROOT}/upgrade-attestation-stale-migration.out" \
  run_upgrade_attestation_verifier \
    "$upgrade_fixture_dir/stale-migration-count/$upgrade_fixture_manifest_name"
expect_failure \
  'database_schema.candidate_only_table_count mismatch: expected 8, got 7' \
  "${TEMP_ROOT}/upgrade-attestation-stale-table.out" \
  run_upgrade_attestation_verifier \
    "$upgrade_fixture_dir/stale-table-count/$upgrade_fixture_manifest_name"
expect_failure \
  'created_at mismatch: expected 2000-01-01T00:00:00Z, got 1999-12-31T16:00:00Z' \
  "${TEMP_ROOT}/upgrade-attestation-stale-created-at.out" \
  run_upgrade_attestation_verifier \
    "$upgrade_fixture_dir/stale-created-at/$upgrade_fixture_manifest_name"
expect_failure \
  'created_at mismatch: expected 2000-01-01T00:00:00Z, got 2000-01-01T00:00:00+00:00' \
  "${TEMP_ROOT}/upgrade-attestation-offset-created-at.out" \
  run_upgrade_attestation_verifier \
    "$upgrade_fixture_dir/offset-created-at/$upgrade_fixture_manifest_name"
expect_failure \
  'created_at mismatch: expected 2000-01-01T00:00:00Z, got 2000-01-01T00:00:00.000Z' \
  "${TEMP_ROOT}/upgrade-attestation-fractional-created-at.out" \
  run_upgrade_attestation_verifier \
    "$upgrade_fixture_dir/fractional-created-at/$upgrade_fixture_manifest_name"
expect_failure \
  'log timestamp mismatch: attestation 20000101T000000Z, log 20000101T000001Z' \
  "${TEMP_ROOT}/upgrade-attestation-mismatched-log-timestamp.out" \
  run_upgrade_attestation_verifier \
    "$upgrade_fixture_dir/mismatched-log-timestamp/$upgrade_fixture_manifest_name"

dry_run_fixture_dir="${TEMP_ROOT}/dry-run-manifest-valid"
dry_run_artifact_version="fixture-unsigned"
dry_run_dmg_name="Chronicle-${dry_run_artifact_version}.dmg"
dry_run_checksum_name="${dry_run_dmg_name}.sha256"
dry_run_summary_name="Chronicle-${dry_run_artifact_version}.unit-test-summary.json"
dry_run_analyze_name="Chronicle-${dry_run_artifact_version}.release-analyze.log"
dry_run_analyze_receipt_name="Chronicle-${dry_run_artifact_version}.release-analyze.receipt.json"
dry_run_manifest_name="Chronicle-${dry_run_artifact_version}.dry-run-manifest.json"
dry_run_source_fingerprint="$(printf 'a%.0s' {1..64})"
dry_run_source_commit="$(printf 'b%.0s' {1..40})"
dry_run_release_tag="v9.9.9"
dry_run_app_version="9.9.9"
dry_run_app_build="999"
dry_run_source_dirty="false"
mkdir -p "$dry_run_fixture_dir"
printf 'verified unsigned dry-run fixture\n' > "$dry_run_fixture_dir/$dry_run_dmg_name"
dry_run_dmg_digest="$(shasum -a 256 "$dry_run_fixture_dir/$dry_run_dmg_name" | awk '{print tolower($1)}')"
printf '%s  %s\n' "$dry_run_dmg_digest" "$dry_run_dmg_name" \
  > "$dry_run_fixture_dir/$dry_run_checksum_name"
printf '%s\n' '{"result":"Passed","totalTestCount":3,"passedTests":3,"failedTests":0,"skippedTests":0,"expectedFailures":0}' \
  > "$dry_run_fixture_dir/$dry_run_summary_name"
ruby -rjson -rdigest -e '
  directory, artifact_version, source_fingerprint, dmg_name, checksum_name,
    summary_name, analyze_name, analyze_receipt_name, manifest_name = ARGV
  derived_data_path = File.join(directory, "analyze-derived-data")
  command = {
    "executable" => "xcodebuild",
    "project" => "Chronicle.xcodeproj",
    "scheme" => "Chronicle",
    "action" => "analyze",
    "configuration" => "Release",
    "destination" => "generic/platform=macOS",
    "architectures" => %w[arm64 x86_64],
    "only_active_arch" => false,
    "code_signing_allowed" => false,
    "derived_data_path" => derived_data_path,
    "cloned_source_packages_path" => nil,
    "argv" => [
      "-project", "Chronicle.xcodeproj",
      "-scheme", "Chronicle",
      "-configuration", "Release",
      "-destination", "generic/platform=macOS",
      "-derivedDataPath", derived_data_path,
      "ARCHS=arm64 x86_64", "ONLY_ACTIVE_ARCH=NO", "CODE_SIGNING_ALLOWED=NO",
      "clean", "analyze"
    ]
  }
  log_path = File.join(directory, analyze_name)
  File.binwrite(
    log_path,
    "CHRONICLE_RELEASE_ANALYZE_COMMAND #{JSON.generate(command)}\nfixture universal Release Analyze\n** ANALYZE SUCCEEDED **\n"
  )
  log_bytes = File.binread(log_path)
  receipt = {
    "schema_version" => 1,
    "receipt_type" => "chronicle_release_analyze_execution",
    "command" => command,
    "result" => {
      "exit_code" => 0,
      "started_at" => "2000-01-01T00:00:00.000000Z",
      "finished_at" => "2000-01-01T00:00:01.000000Z"
    },
    "source" => {
      "fingerprint_schema" => "chronicle-release-source-fingerprint-v1",
      "before" => source_fingerprint,
      "after" => source_fingerprint
    },
    "log" => {
      "name" => analyze_name,
      "size" => log_bytes.bytesize,
      "sha256" => Digest::SHA256.hexdigest(log_bytes)
    }
  }
  File.write(File.join(directory, analyze_receipt_name), JSON.pretty_generate(receipt) << "\n")
  evidence = lambda do |name|
    path = File.join(directory, name)
    { "name" => name, "size" => File.size(path), "sha256" => Digest::SHA256.file(path).hexdigest }
  end
  manifest = {
    "schema_version" => 3,
    "attestation_type" => "chronicle_unsigned_release_dry_run",
    "status" => "passed",
    "pass" => true,
    "authoritative_rehearsal" => true,
    "publishable" => false,
    "created_at" => "2000-01-01T00:00:00Z",
    "source" => {
      "fingerprint_schema" => "chronicle-release-source-fingerprint-v1",
      "fingerprint" => source_fingerprint,
      "commit" => "b" * 40,
      "branch" => "fixture",
      "dirty" => false
    },
    "release" => {
      "tag" => "v9.9.9",
      "artifact_version" => artifact_version,
      "app_version" => "9.9.9",
      "app_build" => "999"
    },
    "validation" => {
      "preflight" => { "status" => "passed" },
      "unit_tests" => {
        "executed" => true,
        "status" => "passed",
        "result_bundle_evidence" => "ChronicleTests.xcresult",
        "summary" => evidence.call(summary_name),
        "total" => 3,
        "passed" => 3,
        "failed" => 0,
        "skipped" => 0,
        "expected_failures" => 0
      },
      "release_analyze" => {
        "executed" => true,
        "status" => "passed",
        "log" => evidence.call(analyze_name),
        "receipt" => evidence.call(analyze_receipt_name)
      }
    },
    "artifact" => {
      "inspection_mode" => "rehearsal",
      "signing" => "unsigned",
      "notarized" => false,
      "stapled" => false,
      "dmg" => evidence.call(dmg_name),
      "checksum" => evidence.call(checksum_name)
    }
  }
  File.write(File.join(directory, manifest_name), JSON.pretty_generate(manifest) << "\n")
' \
  "$dry_run_fixture_dir" \
  "$dry_run_artifact_version" \
  "$dry_run_source_fingerprint" \
  "$dry_run_dmg_name" \
  "$dry_run_checksum_name" \
  "$dry_run_summary_name" \
  "$dry_run_analyze_name" \
  "$dry_run_analyze_receipt_name" \
  "$dry_run_manifest_name"

run_dry_run_manifest_verifier() {
  local expected_dirty="${2:-$dry_run_source_dirty}"
  ruby "$ROOT_DIR/script/support/verify_release_dry_run_manifest.rb" \
    "$1/$dry_run_manifest_name" \
    "$1" \
    "$dry_run_source_fingerprint" \
    "$dry_run_source_commit" \
    "$dry_run_release_tag" \
    "$dry_run_app_version" \
    "$dry_run_app_build" \
    "$expected_dirty" \
    --exact-files
}

mutate_dry_run_analyze_fixture() {
  local directory="$1"
  local mode="$2"
  ruby -rjson -rdigest -e '
    directory, mode, manifest_name, log_name, receipt_name = ARGV
    manifest_path = File.join(directory, manifest_name)
    log_path = File.join(directory, log_name)
    receipt_path = File.join(directory, receipt_name)
    manifest = JSON.parse(File.binread(manifest_path))
    receipt = JSON.parse(File.binread(receipt_path))
    command = receipt.fetch("command")
    rewrite_log = true

    case mode
    when "marker_only"
      log_bytes = "** ANALYZE SUCCEEDED **\n"
    when "missing_success"
      log_bytes = "CHRONICLE_RELEASE_ANALYZE_COMMAND #{JSON.generate(command)}\nAnalyze output without a success marker\n"
    when "debug"
      command["configuration"] = "Debug"
      index = command.fetch("argv").index("Release")
      command.fetch("argv")[index] = "Debug"
      log_bytes = "CHRONICLE_RELEASE_ANALYZE_COMMAND #{JSON.generate(command)}\n** ANALYZE SUCCEEDED **\n"
    when "single_arch"
      command["architectures"] = ["arm64"]
      index = command.fetch("argv").index("ARCHS=arm64 x86_64")
      command.fetch("argv")[index] = "ARCHS=arm64"
      log_bytes = "CHRONICLE_RELEASE_ANALYZE_COMMAND #{JSON.generate(command)}\n** ANALYZE SUCCEEDED **\n"
    when "conflicting_override"
      index = command.fetch("argv").index("clean")
      command.fetch("argv").insert(index, "ARCHS=arm64")
      log_bytes = "CHRONICLE_RELEASE_ANALYZE_COMMAND #{JSON.generate(command)}\n** ANALYZE SUCCEEDED **\n"
    when "failure_marker"
      log_bytes = "CHRONICLE_RELEASE_ANALYZE_COMMAND #{JSON.generate(command)}\n** ANALYZE FAILED **\n** ANALYZE SUCCEEDED **\n"
    when "receipt_tamper"
      receipt.fetch("result")["exit_code"] = 7
      rewrite_log = false
    when "receipt_log_mismatch"
      receipt.fetch("log")["sha256"] = "0" * 64
      rewrite_log = false
    else
      abort "unknown Analyze fixture mutation: #{mode}"
    end

    if rewrite_log
      File.binwrite(log_path, log_bytes)
      receipt["log"] = {
        "name" => log_name,
        "size" => log_bytes.bytesize,
        "sha256" => Digest::SHA256.hexdigest(log_bytes)
      }
    end
    File.write(receipt_path, JSON.pretty_generate(receipt) << "\n")

    evidence = lambda do |path, name|
      { "name" => name, "size" => File.size(path), "sha256" => Digest::SHA256.file(path).hexdigest }
    end
    analysis = manifest.fetch("validation").fetch("release_analyze")
    analysis["log"] = evidence.call(log_path, log_name)
    analysis["receipt"] = evidence.call(receipt_path, receipt_name)
    File.write(manifest_path, JSON.pretty_generate(manifest) << "\n")
  ' \
    "$directory" \
    "$mode" \
    "$dry_run_manifest_name" \
    "$dry_run_analyze_name" \
    "$dry_run_analyze_receipt_name"
}

run_dry_run_manifest_verifier "$dry_run_fixture_dir" \
  > "${TEMP_ROOT}/dry-run-manifest-positive.out"

dry_run_bound_dirty_dir="${TEMP_ROOT}/dry-run-manifest-bound-dirty"
cp -R "$dry_run_fixture_dir" "$dry_run_bound_dirty_dir"
ruby -rjson -e '
  manifest_path = ARGV.fetch(0)
  manifest = JSON.parse(File.binread(manifest_path))
  manifest.fetch("source")["dirty"] = true
  File.write(manifest_path, JSON.pretty_generate(manifest) << "\n")
' "$dry_run_bound_dirty_dir/$dry_run_manifest_name"
run_dry_run_manifest_verifier "$dry_run_bound_dirty_dir" true \
  > "${TEMP_ROOT}/dry-run-manifest-bound-dirty.out"

for metadata_case in \
  'wrong_commit|source.commit mismatch' \
  'wrong_dirty|source.dirty mismatch' \
  'wrong_tag|release.tag mismatch' \
  'wrong_version|release.app_version mismatch' \
  'wrong_build|release.app_build mismatch'; do
  metadata_mode="${metadata_case%%|*}"
  metadata_expected="${metadata_case#*|}"
  metadata_case_dir="${TEMP_ROOT}/dry-run-manifest-${metadata_mode}"
  cp -R "$dry_run_fixture_dir" "$metadata_case_dir"
  ruby -rjson -e '
    manifest_path, mode = ARGV
    manifest = JSON.parse(File.binread(manifest_path))
    case mode
    when "wrong_commit"
      manifest.fetch("source")["commit"] = "c" * 40
    when "wrong_dirty"
      manifest.fetch("source")["dirty"] = true
    when "wrong_tag"
      manifest.fetch("release")["tag"] = "v9.9.8"
    when "wrong_version"
      manifest.fetch("release")["app_version"] = "9.9.8"
    when "wrong_build"
      manifest.fetch("release")["app_build"] = "998"
    else
      abort "unknown metadata mutation: #{mode}"
    end
    File.write(manifest_path, JSON.pretty_generate(manifest) << "\n")
  ' "$metadata_case_dir/$dry_run_manifest_name" "$metadata_mode"
  expect_failure \
    "$metadata_expected" \
    "${TEMP_ROOT}/dry-run-manifest-${metadata_mode}.out" \
    run_dry_run_manifest_verifier "$metadata_case_dir"
done

dry_run_non_authoritative_dir="${TEMP_ROOT}/dry-run-manifest-non-authoritative"
cp -R "$dry_run_fixture_dir" "$dry_run_non_authoritative_dir"
ruby -rjson -e '
  manifest_path = ARGV.fetch(0)
  manifest = JSON.parse(File.binread(manifest_path))
  manifest["status"] = "completed_non_authoritative"
  manifest["pass"] = false
  manifest["authoritative_rehearsal"] = false
  manifest.fetch("validation")["unit_tests"] = {
    "executed" => false,
    "status" => "skipped_non_authoritative",
    "reason" => "explicit non-authoritative artifact rehearsal"
  }
  manifest.fetch("validation")["release_analyze"] = {
    "executed" => false,
    "status" => "skipped_non_authoritative",
    "reason" => "explicit non-authoritative artifact rehearsal"
  }
  File.write(manifest_path, JSON.pretty_generate(manifest) << "\n")
' "$dry_run_non_authoritative_dir/$dry_run_manifest_name"
rm "$dry_run_non_authoritative_dir/$dry_run_summary_name"
rm "$dry_run_non_authoritative_dir/$dry_run_analyze_name"
rm "$dry_run_non_authoritative_dir/$dry_run_analyze_receipt_name"
run_dry_run_manifest_verifier "$dry_run_non_authoritative_dir" \
  > "${TEMP_ROOT}/dry-run-manifest-non-authoritative.out"

dry_run_missing_analyze_dir="${TEMP_ROOT}/dry-run-manifest-missing-analyze"
cp -R "$dry_run_fixture_dir" "$dry_run_missing_analyze_dir"
ruby -rjson -e '
  manifest_path = ARGV.fetch(0)
  manifest = JSON.parse(File.binread(manifest_path))
  manifest.fetch("validation")["release_analyze"] = {
    "executed" => false,
    "status" => "skipped_non_authoritative",
    "reason" => "fixture attempted to bypass Analyze"
  }
  File.write(manifest_path, JSON.pretty_generate(manifest) << "\n")
' "$dry_run_missing_analyze_dir/$dry_run_manifest_name"
rm "$dry_run_missing_analyze_dir/$dry_run_analyze_name"
rm "$dry_run_missing_analyze_dir/$dry_run_analyze_receipt_name"
expect_failure \
  'authoritative manifest cannot omit Release Analyze' \
  "${TEMP_ROOT}/dry-run-manifest-missing-analyze.out" \
  run_dry_run_manifest_verifier "$dry_run_missing_analyze_dir"

dry_run_tampered_dmg_dir="${TEMP_ROOT}/dry-run-manifest-tampered-dmg"
cp -R "$dry_run_fixture_dir" "$dry_run_tampered_dmg_dir"
printf 'tampered\n' >> "$dry_run_tampered_dmg_dir/$dry_run_dmg_name"
expect_failure \
  'DMG size mismatch' \
  "${TEMP_ROOT}/dry-run-manifest-tampered-dmg.out" \
  run_dry_run_manifest_verifier "$dry_run_tampered_dmg_dir"

dry_run_tampered_checksum_dir="${TEMP_ROOT}/dry-run-manifest-tampered-checksum"
cp -R "$dry_run_fixture_dir" "$dry_run_tampered_checksum_dir"
printf '%s  %s\n' "$dry_run_dmg_digest" 'Other.dmg' \
  > "$dry_run_tampered_checksum_dir/$dry_run_checksum_name"
ruby -rjson -rdigest -e '
  manifest_path, checksum_path = ARGV
  manifest = JSON.parse(File.binread(manifest_path))
  evidence = manifest.fetch("artifact").fetch("checksum")
  evidence["size"] = File.size(checksum_path)
  evidence["sha256"] = Digest::SHA256.file(checksum_path).hexdigest
  File.write(manifest_path, JSON.pretty_generate(manifest) << "\n")
' \
  "$dry_run_tampered_checksum_dir/$dry_run_manifest_name" \
  "$dry_run_tampered_checksum_dir/$dry_run_checksum_name"
expect_failure \
  'checksum contents must be the exact DMG SHA-256 and basename' \
  "${TEMP_ROOT}/dry-run-manifest-tampered-checksum.out" \
  run_dry_run_manifest_verifier "$dry_run_tampered_checksum_dir"

dry_run_tampered_summary_dir="${TEMP_ROOT}/dry-run-manifest-tampered-summary"
cp -R "$dry_run_fixture_dir" "$dry_run_tampered_summary_dir"
printf '%s\n' '{"result":"Passed","totalTestCount":3,"passedTests":2,"failedTests":0,"skippedTests":0,"expectedFailures":0}' \
  > "$dry_run_tampered_summary_dir/$dry_run_summary_name"
ruby -rjson -rdigest -e '
  manifest_path, summary_path = ARGV
  manifest = JSON.parse(File.binread(manifest_path))
  evidence = manifest.fetch("validation").fetch("unit_tests").fetch("summary")
  evidence["size"] = File.size(summary_path)
  evidence["sha256"] = Digest::SHA256.file(summary_path).hexdigest
  File.write(manifest_path, JSON.pretty_generate(manifest) << "\n")
' \
  "$dry_run_tampered_summary_dir/$dry_run_manifest_name" \
  "$dry_run_tampered_summary_dir/$dry_run_summary_name"
expect_failure \
  'unit summary contents do not match manifest counts' \
  "${TEMP_ROOT}/dry-run-manifest-tampered-summary.out" \
  run_dry_run_manifest_verifier "$dry_run_tampered_summary_dir"

dry_run_tampered_analyze_dir="${TEMP_ROOT}/dry-run-manifest-tampered-analyze"
cp -R "$dry_run_fixture_dir" "$dry_run_tampered_analyze_dir"
mutate_dry_run_analyze_fixture "$dry_run_tampered_analyze_dir" missing_success
expect_failure \
  'Release Analyze log must contain exactly one success marker' \
  "${TEMP_ROOT}/dry-run-manifest-tampered-analyze.out" \
  run_dry_run_manifest_verifier "$dry_run_tampered_analyze_dir"

for analyze_case in \
  'marker_only|Release Analyze log must contain exactly one structured command record' \
  'debug|Release Analyze receipt.command.configuration mismatch' \
  'single_arch|Release Analyze receipt.command.architectures mismatch' \
  'conflicting_override|Release Analyze receipt.command.argv is not the exact canonical Release Analyze invocation' \
  'failure_marker|Release Analyze log contains a failure marker' \
  'receipt_tamper|Release Analyze receipt exit_code must be 0' \
  'receipt_log_mismatch|Release Analyze receipt log evidence does not match the bound log'; do
  analyze_mode="${analyze_case%%|*}"
  analyze_expected="${analyze_case#*|}"
  analyze_case_dir="${TEMP_ROOT}/dry-run-manifest-${analyze_mode}"
  cp -R "$dry_run_fixture_dir" "$analyze_case_dir"
  mutate_dry_run_analyze_fixture "$analyze_case_dir" "$analyze_mode"
  expect_failure \
    "$analyze_expected" \
    "${TEMP_ROOT}/dry-run-manifest-${analyze_mode}.out" \
    run_dry_run_manifest_verifier "$analyze_case_dir"
done

dry_run_extra_file_dir="${TEMP_ROOT}/dry-run-manifest-extra-file"
cp -R "$dry_run_fixture_dir" "$dry_run_extra_file_dir"
printf 'unexpected\n' > "$dry_run_extra_file_dir/unexpected.txt"
expect_failure \
  'exact artifact file set mismatch' \
  "${TEMP_ROOT}/dry-run-manifest-extra-file.out" \
  run_dry_run_manifest_verifier "$dry_run_extra_file_dir"

dry_run_aba_dir="${TEMP_ROOT}/dry-run-manifest-aba"
dry_run_aba_marker="${TEMP_ROOT}/dry-run-manifest-aba.ready"
dry_run_aba_release="${TEMP_ROOT}/dry-run-manifest-aba.release"
dry_run_aba_output="${TEMP_ROOT}/dry-run-manifest-aba.out"
dry_run_aba_original="${TEMP_ROOT}/dry-run-manifest-aba.original.dmg"
cp -R "$dry_run_fixture_dir" "$dry_run_aba_dir"
env \
  DRY_RUN_VERIFIER_TEST_SEAM='after_lstat:DMG' \
  "DRY_RUN_VERIFIER_TEST_MARKER=${dry_run_aba_marker}" \
  "DRY_RUN_VERIFIER_TEST_RELEASE=${dry_run_aba_release}" \
  ruby "$ROOT_DIR/script/support/verify_release_dry_run_manifest.rb" \
    "$dry_run_aba_dir/$dry_run_manifest_name" \
    "$dry_run_aba_dir" \
    "$dry_run_source_fingerprint" \
    "$dry_run_source_commit" \
    "$dry_run_release_tag" \
    "$dry_run_app_version" \
    "$dry_run_app_build" \
    "$dry_run_source_dirty" \
    --exact-files > "$dry_run_aba_output" 2>&1 &
dry_run_aba_pid=$!
for _ in {1..1000}; do
  [[ -f "$dry_run_aba_marker" ]] && break
  kill -0 "$dry_run_aba_pid" 2>/dev/null || break
  sleep 0.01
done
[[ -f "$dry_run_aba_marker" ]] || fail "dry-run verifier ABA seam was not reached"
mv "$dry_run_aba_dir/$dry_run_dmg_name" "$dry_run_aba_original"
cp "$dry_run_aba_original" "$dry_run_aba_dir/$dry_run_dmg_name"
printf 'continue\n' > "$dry_run_aba_release"
set +e
wait "$dry_run_aba_pid"
dry_run_aba_status=$?
set -e
[[ "$dry_run_aba_status" -ne 0 ]] || fail "dry-run verifier accepted a file identity replacement"
grep -Fq 'DMG identity changed between lstat and O_NOFOLLOW open' "$dry_run_aba_output" \
  || fail "dry-run verifier did not report its file identity replacement guard"

mkdir -p \
  "$FAKE_BIN" \
  "$FIXTURE_APP_PATH/Contents/MacOS" \
  "$FIXTURE_APP_PATH/Contents/Frameworks/SQLCipher.framework/Versions/A" \
  "$FIXTURE_APP_PATH/Contents/Resources"
printf 'fixture executable\n' > "$FIXTURE_APP_PATH/Contents/MacOS/Chronicle"
printf 'fixture framework\n' > "$FIXTURE_APP_PATH/Contents/Frameworks/SQLCipher.framework/Versions/A/SQLCipher"
printf 'fixture plist\n' > "$FIXTURE_APP_PATH/Contents/Info.plist"
printf 'not a Mach-O\n' > "$FIXTURE_APP_PATH/Contents/Resources/readme.txt"
cp "$ROOT_DIR/Chronicle/Resources/ThirdPartyNotices.md" "$FIXTURE_APP_PATH/Contents/Resources/ThirdPartyNotices.md"
cp "$ROOT_DIR/LICENSE" "$FIXTURE_APP_PATH/Contents/Resources/LICENSE"
printf 'fixture dmg\n' > "$FIXTURE_DMG"
chmod +x \
  "$FIXTURE_APP_PATH/Contents/MacOS/Chronicle" \
  "$FIXTURE_APP_PATH/Contents/Frameworks/SQLCipher.framework/Versions/A/SQLCipher"

for fake_tool in hdiutil plutil file lipo vtool xcrun codesign spctl xcodebuild gh; do
  ln -s "$ROOT_DIR/script/test_release_guards.sh" "$FAKE_BIN/$fake_tool"
done

analyze_fixture_args="${TEMP_ROOT}/release-analyze-args.txt"
analyze_fixture_log="${TEMP_ROOT}/release-analyze-passed.log"
analyze_fixture_receipt="${TEMP_ROOT}/release-analyze-passed.receipt.json"
analyze_fixture_derived="$(cd "$TEMP_ROOT" && pwd -P)/release-analyze-derived"
env \
  "PATH=${FAKE_BIN}:${PATH}" \
  RELEASE_GUARD_FAKE_TOOL=1 \
  "FIXTURE_ANALYZE_ARGS_PATH=${analyze_fixture_args}" \
  "RELEASE_ANALYZE_XCODEBUILD=${FAKE_BIN}/xcodebuild" \
  "RELEASE_ANALYZE_DERIVED_DATA_PATH=${TEMP_ROOT}/release-analyze-derived" \
  "RELEASE_ANALYZE_LOG_PATH=${analyze_fixture_log}" \
  "RELEASE_ANALYZE_RECEIPT_PATH=${analyze_fixture_receipt}" \
  bash "$ROOT_DIR/script/run_release_analyze.sh" \
  > "${TEMP_ROOT}/release-analyze-passed.out"
expected_analyze_args=(
  -project
  Chronicle.xcodeproj
  -scheme
  Chronicle
  -configuration
  Release
  -destination
  generic/platform=macOS
  -derivedDataPath
  "$analyze_fixture_derived"
  'ARCHS=arm64 x86_64'
  ONLY_ACTIVE_ARCH=NO
  CODE_SIGNING_ALLOWED=NO
  clean
  analyze
)
if ! diff -u <(printf '%s\n' "${expected_analyze_args[@]}") "$analyze_fixture_args"; then
  fail "Release Analyze wrapper did not pass the exact canonical argv"
fi
grep -Fq '** ANALYZE SUCCEEDED **' "$analyze_fixture_log" \
  || fail "Release Analyze wrapper did not preserve its passed log"
ruby -rjson -rdigest -e '
  receipt_path, log_path = ARGV
  receipt = JSON.parse(File.binread(receipt_path))
  abort "wrapper receipt schema mismatch" unless receipt["schema_version"] == 1
  abort "wrapper receipt exit mismatch" unless receipt.dig("result", "exit_code") == 0
  abort "wrapper receipt source mismatch" unless receipt.dig("source", "before") == receipt.dig("source", "after")
  log = receipt.fetch("log")
  abort "wrapper receipt log size mismatch" unless log["size"] == File.size(log_path)
  abort "wrapper receipt log hash mismatch" unless log["sha256"] == Digest::SHA256.file(log_path).hexdigest
' "$analyze_fixture_receipt" "$analyze_fixture_log"

analyze_failed_fixture_log="${TEMP_ROOT}/release-analyze-failed.log"
analyze_failed_fixture_receipt="${TEMP_ROOT}/release-analyze-failed.receipt.json"
expect_failure \
  'Release Analyze failed with status 42' \
  "${TEMP_ROOT}/release-analyze-failed.out" \
  env \
    "PATH=${FAKE_BIN}:${PATH}" \
    RELEASE_GUARD_FAKE_TOOL=1 \
    FIXTURE_ANALYZE_FAIL=1 \
    "RELEASE_ANALYZE_XCODEBUILD=${FAKE_BIN}/xcodebuild" \
    "RELEASE_ANALYZE_DERIVED_DATA_PATH=${TEMP_ROOT}/release-analyze-failed-derived" \
    "RELEASE_ANALYZE_LOG_PATH=${analyze_failed_fixture_log}" \
    "RELEASE_ANALYZE_RECEIPT_PATH=${analyze_failed_fixture_receipt}" \
    bash "$ROOT_DIR/script/run_release_analyze.sh"
grep -Fq 'fixture Release Analyze failure' "$analyze_failed_fixture_log" \
  || fail "Release Analyze wrapper did not preserve its failed log"
ruby -rjson -e '
  receipt = JSON.parse(File.binread(ARGV.fetch(0)))
  abort "failed wrapper receipt did not preserve exit 42" unless receipt.dig("result", "exit_code") == 42
' "$analyze_failed_fixture_receipt"

INSPECTOR_ENV=(
  env
  "PATH=${FAKE_BIN}:${PATH}"
  RELEASE_GUARD_FAKE_TOOL=1
  "FIXTURE_APP_PATH=${FIXTURE_APP_PATH}"
  "FIXTURE_DMG_LICENSE_PATH=${ROOT_DIR}/LICENSE"
  "FIXTURE_DMG_NOTICE_PATH=${ROOT_DIR}/Chronicle/Resources/ThirdPartyNotices.md"
  EXPECTED_APP_VERSION=9.9.9
  EXPECTED_APP_BUILD=999
  EXPECTED_MINIMUM_MACOS=14.0
)

rehearsal_output="${TEMP_ROOT}/rehearsal.out"
"${INSPECTOR_ENV[@]}" \
  FIXTURE_COMPATIBLE_SQLCIPHER_MINOS=1 \
  bash "$ROOT_DIR/script/inspect_release_artifact.sh" "$FIXTURE_DMG" rehearsal \
  > "$rehearsal_output" 2>&1
grep -Fq 'Mach-O verified: Contents/MacOS/Chronicle' "$rehearsal_output" \
  || fail "main Chronicle Mach-O was not inspected"
grep -Fq 'Mach-O verified: Contents/Frameworks/SQLCipher.framework/Versions/A/SQLCipher' "$rehearsal_output" \
  || fail "SQLCipher Mach-O was not inspected"
grep -Fq 'Mach-O files: 2 (main 1; SQLCipher.framework 1)' "$rehearsal_output" \
  || fail "Mach-O inventory summary is incorrect"
grep -Fq 'Third-party notices verified in Chronicle.app and at the DMG root.' "$rehearsal_output" \
  || fail "third-party notices were not verified"
grep -Fq 'Project license verified in Chronicle.app and at the DMG root.' "$rehearsal_output" \
  || fail "project license was not verified"

mv "$FIXTURE_APP_PATH/Contents/Resources/LICENSE" "$FIXTURE_APP_PATH/Contents/Resources/LICENSE.missing"
expect_failure \
  'Release artifact is missing a safe project license: Chronicle.app/Contents/Resources/LICENSE' \
  "${TEMP_ROOT}/missing-bundled-license.out" \
  "${INSPECTOR_ENV[@]}" \
  bash "$ROOT_DIR/script/inspect_release_artifact.sh" "$FIXTURE_DMG" rehearsal
mv "$FIXTURE_APP_PATH/Contents/Resources/LICENSE.missing" "$FIXTURE_APP_PATH/Contents/Resources/LICENSE"

expect_failure \
  'Release artifact is missing a safe project license: LICENSE' \
  "${TEMP_ROOT}/missing-dmg-license.out" \
  "${INSPECTOR_ENV[@]}" FIXTURE_MISSING_DMG_LICENSE=1 \
  bash "$ROOT_DIR/script/inspect_release_artifact.sh" "$FIXTURE_DMG" rehearsal

printf 'tampered project license\n' > "$FIXTURE_APP_PATH/Contents/Resources/LICENSE"
expect_failure \
  'Release artifact project license differs from the reviewed source: Chronicle.app/Contents/Resources/LICENSE' \
  "${TEMP_ROOT}/mismatched-bundled-license.out" \
  "${INSPECTOR_ENV[@]}" \
  bash "$ROOT_DIR/script/inspect_release_artifact.sh" "$FIXTURE_DMG" rehearsal
cp "$ROOT_DIR/LICENSE" "$FIXTURE_APP_PATH/Contents/Resources/LICENSE"

tampered_dmg_license="${TEMP_ROOT}/tampered-project-license"
printf 'tampered project license\n' > "$tampered_dmg_license"
expect_failure \
  'Release artifact project license differs from the reviewed source: LICENSE' \
  "${TEMP_ROOT}/mismatched-dmg-license.out" \
  "${INSPECTOR_ENV[@]}" "FIXTURE_DMG_LICENSE_PATH=${tampered_dmg_license}" \
  bash "$ROOT_DIR/script/inspect_release_artifact.sh" "$FIXTURE_DMG" rehearsal

mv "$FIXTURE_APP_PATH/Contents/Resources/ThirdPartyNotices.md" "$FIXTURE_APP_PATH/Contents/Resources/ThirdPartyNotices.md.missing"
expect_failure \
  'Release artifact is missing safe third-party notices: Chronicle.app/Contents/Resources/ThirdPartyNotices.md' \
  "${TEMP_ROOT}/missing-bundled-notice.out" \
  "${INSPECTOR_ENV[@]}" \
  bash "$ROOT_DIR/script/inspect_release_artifact.sh" "$FIXTURE_DMG" rehearsal
mv "$FIXTURE_APP_PATH/Contents/Resources/ThirdPartyNotices.md.missing" "$FIXTURE_APP_PATH/Contents/Resources/ThirdPartyNotices.md"

expect_failure \
  'Release artifact is missing safe third-party notices: ThirdPartyNotices.md' \
  "${TEMP_ROOT}/missing-dmg-notice.out" \
  "${INSPECTOR_ENV[@]}" FIXTURE_MISSING_DMG_NOTICE=1 \
  bash "$ROOT_DIR/script/inspect_release_artifact.sh" "$FIXTURE_DMG" rehearsal

printf 'tampered notice\n' > "$FIXTURE_APP_PATH/Contents/Resources/ThirdPartyNotices.md"
expect_failure \
  'Release artifact third-party notices differ from the reviewed source: Chronicle.app/Contents/Resources/ThirdPartyNotices.md' \
  "${TEMP_ROOT}/mismatched-bundled-notice.out" \
  "${INSPECTOR_ENV[@]}" \
  bash "$ROOT_DIR/script/inspect_release_artifact.sh" "$FIXTURE_DMG" rehearsal
cp "$ROOT_DIR/Chronicle/Resources/ThirdPartyNotices.md" "$FIXTURE_APP_PATH/Contents/Resources/ThirdPartyNotices.md"

expect_failure \
  'Chronicle main executable is not a real Mach-O file.' \
  "${TEMP_ROOT}/non-macho-main.out" \
  "${INSPECTOR_ENV[@]}" FIXTURE_MAIN_NOT_MACHO=1 \
  bash "$ROOT_DIR/script/inspect_release_artifact.sh" "$FIXTURE_DMG" rehearsal

expect_failure \
  'SQLCipher.framework/Versions/A/SQLCipher must contain exactly arm64 and x86_64' \
  "${TEMP_ROOT}/bad-arch.out" \
  "${INSPECTOR_ENV[@]}" FIXTURE_BAD_SQLCIPHER_ARCH=1 \
  bash "$ROOT_DIR/script/inspect_release_artifact.sh" "$FIXTURE_DMG" rehearsal

expect_failure \
  'SQLCipher.framework/Versions/A/SQLCipher x86_64 minimum macOS 15.0 exceeds compatibility target 14.0.' \
  "${TEMP_ROOT}/bad-minos.out" \
  "${INSPECTOR_ENV[@]}" FIXTURE_BAD_SQLCIPHER_MINOS=1 \
  bash "$ROOT_DIR/script/inspect_release_artifact.sh" "$FIXTURE_DMG" rehearsal

expect_failure \
  'Main executable arm64 minimum macOS mismatch: expected exactly 14.0, got 13.0.' \
  "${TEMP_ROOT}/bad-main-minos.out" \
  "${INSPECTOR_ENV[@]}" FIXTURE_BAD_MAIN_MINOS=1 \
  bash "$ROOT_DIR/script/inspect_release_artifact.sh" "$FIXTURE_DMG" rehearsal

expect_failure \
  'EXPECTED_TEAM_IDENTIFIER is required in release mode.' \
  "${TEMP_ROOT}/missing-team.out" \
  "${INSPECTOR_ENV[@]}" FIXTURE_SIGNED=1 \
  bash "$ROOT_DIR/script/inspect_release_artifact.sh" "$FIXTURE_DMG" release

expect_failure \
  'fixture does not have a ticket stapled to it' \
  "${TEMP_ROOT}/unstapled.out" \
  "${INSPECTOR_ENV[@]}" FIXTURE_SIGNED=1 FIXTURE_UNSTAPLED=1 EXPECTED_TEAM_IDENTIFIER=ABCDE12345 \
  bash "$ROOT_DIR/script/inspect_release_artifact.sh" "$FIXTURE_DMG" release

expect_failure \
  'fixture has no valid Developer ID signature' \
  "${TEMP_ROOT}/unsigned.out" \
  "${INSPECTOR_ENV[@]}" FIXTURE_STAPLED=1 EXPECTED_TEAM_IDENTIFIER=ABCDE12345 \
  bash "$ROOT_DIR/script/inspect_release_artifact.sh" "$FIXTURE_DMG" release

expect_failure \
  'Chronicle.app is not signed with a Developer ID Application certificate.' \
  "${TEMP_ROOT}/non-developer-id.out" \
  "${INSPECTOR_ENV[@]}" FIXTURE_SIGNED=1 FIXTURE_NO_DEVELOPER_ID=1 EXPECTED_TEAM_IDENTIFIER=ABCDE12345 \
  bash "$ROOT_DIR/script/inspect_release_artifact.sh" "$FIXTURE_DMG" release

expect_failure \
  'Chronicle.app does not have hardened runtime enabled.' \
  "${TEMP_ROOT}/no-hardened-runtime.out" \
  "${INSPECTOR_ENV[@]}" FIXTURE_SIGNED=1 FIXTURE_NO_HARDENED_RUNTIME=1 EXPECTED_TEAM_IDENTIFIER=ABCDE12345 \
  bash "$ROOT_DIR/script/inspect_release_artifact.sh" "$FIXTURE_DMG" release

expect_failure \
  'Chronicle.app signature does not contain a secure timestamp.' \
  "${TEMP_ROOT}/no-secure-timestamp.out" \
  "${INSPECTOR_ENV[@]}" FIXTURE_SIGNED=1 FIXTURE_NO_TIMESTAMP=1 EXPECTED_TEAM_IDENTIFIER=ABCDE12345 \
  bash "$ROOT_DIR/script/inspect_release_artifact.sh" "$FIXTURE_DMG" release

expect_failure \
  'Gatekeeper rejected Chronicle.app.' \
  "${TEMP_ROOT}/gatekeeper-rejected.out" \
  "${INSPECTOR_ENV[@]}" FIXTURE_SIGNED=1 FIXTURE_GATEKEEPER_REJECTS=1 EXPECTED_TEAM_IDENTIFIER=ABCDE12345 \
  bash "$ROOT_DIR/script/inspect_release_artifact.sh" "$FIXTURE_DMG" release

release_output="${TEMP_ROOT}/release.out"
"${INSPECTOR_ENV[@]}" \
  FIXTURE_SIGNED=1 \
  FIXTURE_TEAM_IDENTIFIER=ABCDE12345 \
  EXPECTED_TEAM_IDENTIFIER=ABCDE12345 \
  bash "$ROOT_DIR/script/inspect_release_artifact.sh" "$FIXTURE_DMG" release \
  > "$release_output" 2>&1
grep -Fq 'Team identifier: ABCDE12345' "$release_output" \
  || fail "release TeamIdentifier pin was not reported"

expect_failure \
  'TeamIdentifier mismatch: expected ZYXWV98765, got ABCDE12345.' \
  "${TEMP_ROOT}/wrong-team.out" \
  "${INSPECTOR_ENV[@]}" FIXTURE_SIGNED=1 FIXTURE_TEAM_IDENTIFIER=ABCDE12345 EXPECTED_TEAM_IDENTIFIER=ZYXWV98765 \
  bash "$ROOT_DIR/script/inspect_release_artifact.sh" "$FIXTURE_DMG" release

fixture_tag="v9.9.9"
fixture_release_id="424242"
fixture_source_commit="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
fixture_repository="fixture/repo"
fixture_staging_run_id="777777"
fixture_staging_run_attempt="1"
fixture_workflow_ref="fixture/repo/.github/workflows/release.yml@refs/heads/main"
fixture_provenance_args=(
  "$fixture_repository"
  "$fixture_staging_run_id"
  "$fixture_staging_run_attempt"
  "$fixture_source_commit"
  "$fixture_workflow_ref"
  "$fixture_source_commit"
)
fixture_dmg_name="Chronicle-${fixture_tag}.dmg"
fixture_checksum_name="${fixture_dmg_name}.sha256"
fixture_dmg_file="${TEMP_ROOT}/${fixture_dmg_name}"
fixture_checksum_file="${TEMP_ROOT}/${fixture_checksum_name}"
fixture_notes_file="${TEMP_ROOT}/release-notes.md"
fixture_releases_json="${TEMP_ROOT}/releases.json"
fixture_exact_json="${TEMP_ROOT}/release.json"
fixture_replaced_json="${TEMP_ROOT}/releases-replaced.json"
fixture_published_releases_json="${TEMP_ROOT}/releases-published.json"
fixture_published_exact_json="${TEMP_ROOT}/release-published.json"
fixture_tampered_body_releases_json="${TEMP_ROOT}/releases-tampered-body.json"
fixture_tampered_body_exact_json="${TEMP_ROOT}/release-tampered-body.json"
fixture_replaced_assets_releases_json="${TEMP_ROOT}/releases-replaced-assets.json"
fixture_replaced_assets_exact_json="${TEMP_ROOT}/release-replaced-assets.json"
fixture_wrong_size_exact_json="${TEMP_ROOT}/release-wrong-size.json"
fixture_wrong_digest_exact_json="${TEMP_ROOT}/release-wrong-digest.json"
fixture_dmg_upload_json="${TEMP_ROOT}/upload-dmg.json"
fixture_checksum_upload_json="${TEMP_ROOT}/upload-checksum.json"
fixture_binding_manifest="${TEMP_ROOT}/release-binding-manifest.json"

printf 'fixture release dmg\n' > "$fixture_dmg_file"
printf '# Fixture release notes\n\nExact workflow-built notes.\n' > "$fixture_notes_file"
fixture_dmg_digest="$(shasum -a 256 "$fixture_dmg_file" | awk '{print tolower($1)}')"
printf '%s  %s\n' "$fixture_dmg_digest" "$fixture_dmg_name" > "$fixture_checksum_file"

ruby -rjson -rdigest -rtime -e '
  tag, release_id, dmg_path, checksum_path, notes_path,
    releases_path, exact_path, replaced_path,
    published_releases_path, published_exact_path,
    tampered_body_releases_path, tampered_body_exact_path,
    replaced_assets_releases_path, replaced_assets_exact_path,
    wrong_size_exact_path, wrong_digest_exact_path,
    dmg_upload_path, checksum_upload_path = ARGV
  release_id = Integer(release_id, 10)
  dmg_name = File.basename(dmg_path)
  checksum_name = File.basename(checksum_path)
  dmg_digest = Digest::SHA256.file(dmg_path).hexdigest
  checksum_digest = Digest::SHA256.file(checksum_path).hexdigest
  dmg_asset = {
    "id" => 11,
    "name" => dmg_name,
    "size" => File.size(dmg_path),
    "state" => "uploaded",
    "digest" => "sha256:#{dmg_digest}"
  }
  checksum_asset = {
    "id" => 12,
    "name" => checksum_name,
    "size" => File.size(checksum_path),
    "state" => "uploaded",
    "digest" => "sha256:#{checksum_digest}"
  }
  release = {
    "id" => release_id,
    "tag_name" => tag,
    "name" => tag,
    "body" => File.binread(notes_path),
    "draft" => true,
    "prerelease" => false,
    "published_at" => nil,
    "html_url" => "https://example.invalid/releases/tag/#{tag}",
    "assets" => [dmg_asset, checksum_asset]
  }
  published = release.merge("draft" => false, "published_at" => "2026-07-23T03:00:00Z")
  tampered_body = release.merge("body" => release.fetch("body") + "\nTampered after upload.\n")
  replaced_assets = release.merge(
    "assets" => release.fetch("assets").map { |asset| asset.merge("id" => asset.fetch("id") + 100) }
  )
  wrong_size = release.merge(
    "assets" => release.fetch("assets").map do |asset|
      asset.fetch("name") == dmg_name ? asset.merge("size" => asset.fetch("size") + 1) : asset
    end
  )
  wrong_digest = release.merge(
    "assets" => release.fetch("assets").map do |asset|
      asset.fetch("name") == dmg_name ? asset.merge("digest" => "sha256:#{"b" * 64}") : asset
    end
  )

  File.write(releases_path, JSON.generate([[release]]))
  File.write(exact_path, JSON.generate(release))
  File.write(replaced_path, JSON.generate([[release.merge("id" => release_id + 1)]]))
  File.write(published_releases_path, JSON.generate([[published]]))
  File.write(published_exact_path, JSON.generate(published))
  File.write(tampered_body_releases_path, JSON.generate([[tampered_body]]))
  File.write(tampered_body_exact_path, JSON.generate(tampered_body))
  File.write(replaced_assets_releases_path, JSON.generate([[replaced_assets]]))
  File.write(replaced_assets_exact_path, JSON.generate(replaced_assets))
  File.write(wrong_size_exact_path, JSON.generate(wrong_size))
  File.write(wrong_digest_exact_path, JSON.generate(wrong_digest))
  File.write(dmg_upload_path, JSON.generate(dmg_asset))
  File.write(checksum_upload_path, JSON.generate(checksum_asset))
' \
  "$fixture_tag" \
  "$fixture_release_id" \
  "$fixture_dmg_file" \
  "$fixture_checksum_file" \
  "$fixture_notes_file" \
  "$fixture_releases_json" \
  "$fixture_exact_json" \
  "$fixture_replaced_json" \
  "$fixture_published_releases_json" \
  "$fixture_published_exact_json" \
  "$fixture_tampered_body_releases_json" \
  "$fixture_tampered_body_exact_json" \
  "$fixture_replaced_assets_releases_json" \
  "$fixture_replaced_assets_exact_json" \
  "$fixture_wrong_size_exact_json" \
  "$fixture_wrong_digest_exact_json" \
  "$fixture_dmg_upload_json" \
  "$fixture_checksum_upload_json"

ruby "$ROOT_DIR/script/support/release_binding_manifest.rb" create \
  "$fixture_binding_manifest" \
  "$fixture_release_id" \
  "$fixture_tag" \
  "$fixture_source_commit" \
  "$fixture_notes_file" \
  "$fixture_repository" \
  "$fixture_staging_run_id" \
  "$fixture_staging_run_attempt" \
  "$fixture_source_commit" \
  "$fixture_workflow_ref" \
  "$fixture_source_commit" \
  "$fixture_dmg_file" \
  "$fixture_dmg_upload_json" \
  "$fixture_checksum_file" \
  "$fixture_checksum_upload_json" \
  > "${TEMP_ROOT}/manifest-create.out"

checker_output="${TEMP_ROOT}/checker.out"
env \
  "PATH=${FAKE_BIN}:${PATH}" \
  RELEASE_GUARD_FAKE_TOOL=1 \
  RELEASE_REPO=fixture/repo \
  "FIXTURE_RELEASES_JSON=${fixture_releases_json}" \
  "FIXTURE_EXACT_RELEASE_JSON=${fixture_exact_json}" \
  "FIXTURE_CHECKSUM_FILE=${fixture_checksum_file}" \
  bash "$ROOT_DIR/script/check_release_assets.sh" "$fixture_tag" draft ignore "$fixture_release_id" "$fixture_binding_manifest" gate "$fixture_source_commit" "${fixture_provenance_args[@]}" \
  > "$checker_output" 2>&1
grep -Fq "Release ID: ${fixture_release_id}" "$checker_output" \
  || fail "asset checker did not report its bound release ID"
grep -Fq "Release binding manifest verified: release ${fixture_release_id}, 2 assets" "$checker_output" \
  || fail "asset checker did not verify the local release binding manifest"
grep -Fq 'Gate-qualified: yes' "$checker_output" \
  || fail "bound Draft checker was not gate-qualified"
grep -Fq 'Verification mode: gate' "$checker_output" \
  || fail "bound Draft checker did not report gate mode"

expect_failure \
  'manifest staging provenance mismatch' \
  "${TEMP_ROOT}/wrong-staging-provenance.out" \
  env \
    "PATH=${FAKE_BIN}:${PATH}" \
    RELEASE_GUARD_FAKE_TOOL=1 \
    RELEASE_REPO=fixture/repo \
    "FIXTURE_RELEASES_JSON=${fixture_releases_json}" \
    "FIXTURE_EXACT_RELEASE_JSON=${fixture_exact_json}" \
    "FIXTURE_CHECKSUM_FILE=${fixture_checksum_file}" \
    bash "$ROOT_DIR/script/check_release_assets.sh" \
      "$fixture_tag" draft ignore "$fixture_release_id" "$fixture_binding_manifest" gate "$fixture_source_commit" \
      "$fixture_repository" "$fixture_staging_run_id" 2 "$fixture_source_commit" "$fixture_workflow_ref" "$fixture_source_commit"

expect_failure \
  "Remote tag ${fixture_tag} resolves to bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, expected bound source ${fixture_source_commit}." \
  "${TEMP_ROOT}/wrong-source-commit.out" \
  env \
    "PATH=${FAKE_BIN}:${PATH}" \
    RELEASE_GUARD_FAKE_TOOL=1 \
    RELEASE_REPO=fixture/repo \
    FIXTURE_SOURCE_COMMIT=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
    "FIXTURE_RELEASES_JSON=${fixture_releases_json}" \
    "FIXTURE_EXACT_RELEASE_JSON=${fixture_exact_json}" \
    "FIXTURE_CHECKSUM_FILE=${fixture_checksum_file}" \
    bash "$ROOT_DIR/script/check_release_assets.sh" "$fixture_tag" draft ignore "$fixture_release_id" "$fixture_binding_manifest" gate "$fixture_source_commit" "${fixture_provenance_args[@]}"

expect_failure \
  'Gate verification requires an exact release ID, binding manifest, source commit, and all six staging provenance expectations.' \
  "${TEMP_ROOT}/published-gate-without-provenance.out" \
  bash "$ROOT_DIR/script/check_release_assets.sh" \
    "$fixture_tag" published ignore "$fixture_release_id" "$fixture_binding_manifest" gate "$fixture_source_commit"

published_checker_output="${TEMP_ROOT}/checker-published-bound.out"
env \
  "PATH=${FAKE_BIN}:${PATH}" \
  RELEASE_GUARD_FAKE_TOOL=1 \
  RELEASE_REPO=fixture/repo \
  "FIXTURE_RELEASES_JSON=${fixture_published_releases_json}" \
  "FIXTURE_EXACT_RELEASE_JSON=${fixture_published_exact_json}" \
  "FIXTURE_CHECKSUM_FILE=${fixture_checksum_file}" \
  bash "$ROOT_DIR/script/check_release_assets.sh" \
    "$fixture_tag" published ignore "$fixture_release_id" "$fixture_binding_manifest" gate "$fixture_source_commit" \
    "${fixture_provenance_args[@]}" \
  > "$published_checker_output" 2>&1
grep -Fq "Release binding manifest verified: release ${fixture_release_id}, 2 assets" "$published_checker_output" \
  || fail "published checker did not reuse the Draft binding manifest"
grep -Fq 'Gate-qualified: yes' "$published_checker_output" \
  || fail "bound published checker was not gate-qualified"

unbound_checker_output="${TEMP_ROOT}/checker-unbound.out"
env \
  "PATH=${FAKE_BIN}:${PATH}" \
  RELEASE_GUARD_FAKE_TOOL=1 \
  RELEASE_REPO=fixture/repo \
  "FIXTURE_RELEASES_JSON=${fixture_releases_json}" \
  "FIXTURE_EXACT_RELEASE_JSON=${fixture_exact_json}" \
  "FIXTURE_CHECKSUM_FILE=${fixture_checksum_file}" \
  bash "$ROOT_DIR/script/check_release_assets.sh" "$fixture_tag" draft ignore \
  > "$unbound_checker_output" 2>&1
grep -Fq "Release ID: ${fixture_release_id}" "$unbound_checker_output" \
  || fail "asset checker no-ID compatibility path regressed"
grep -Fq 'NON-GATE release observation completed.' "$unbound_checker_output" \
  || fail "unbound checker did not identify itself as non-gate"
grep -Fq 'Gate-qualified: no' "$unbound_checker_output" \
  || fail "unbound checker incorrectly reported gate qualification"
grep -Fq 'Verification mode: observe' "$unbound_checker_output" \
  || fail "unbound checker did not report observe mode"

expect_failure \
  'Gate verification requires an exact release ID, binding manifest, source commit, and all six staging provenance expectations.' \
  "${TEMP_ROOT}/gate-without-binding.out" \
  bash "$ROOT_DIR/script/check_release_assets.sh" "$fixture_tag" draft ignore "" "" gate

expect_failure \
  'Gate verification requires an exact release ID, binding manifest, source commit, and all six staging provenance expectations.' \
  "${TEMP_ROOT}/gate-without-source.out" \
  bash "$ROOT_DIR/script/check_release_assets.sh" "$fixture_tag" draft ignore "$fixture_release_id" "$fixture_binding_manifest" gate

expect_failure \
  "now resolves to release ID $((fixture_release_id + 1)), expected ${fixture_release_id}" \
  "${TEMP_ROOT}/replaced-release.out" \
  env \
    "PATH=${FAKE_BIN}:${PATH}" \
    RELEASE_GUARD_FAKE_TOOL=1 \
    RELEASE_REPO=fixture/repo \
    "FIXTURE_RELEASES_JSON=${fixture_replaced_json}" \
    "FIXTURE_EXACT_RELEASE_JSON=${fixture_exact_json}" \
    "FIXTURE_CHECKSUM_FILE=${fixture_checksum_file}" \
    bash "$ROOT_DIR/script/check_release_assets.sh" "$fixture_tag" draft ignore "$fixture_release_id" "$fixture_binding_manifest" gate "$fixture_source_commit" "${fixture_provenance_args[@]}"

expect_failure \
  'release body does not match binding manifest' \
  "${TEMP_ROOT}/tampered-release-body.out" \
  env \
    "PATH=${FAKE_BIN}:${PATH}" \
    RELEASE_GUARD_FAKE_TOOL=1 \
    RELEASE_REPO=fixture/repo \
    "FIXTURE_RELEASES_JSON=${fixture_tampered_body_releases_json}" \
    "FIXTURE_EXACT_RELEASE_JSON=${fixture_tampered_body_exact_json}" \
    "FIXTURE_CHECKSUM_FILE=${fixture_checksum_file}" \
    bash "$ROOT_DIR/script/check_release_assets.sh" "$fixture_tag" draft ignore "$fixture_release_id" "$fixture_binding_manifest" gate "$fixture_source_commit" "${fixture_provenance_args[@]}"

expect_failure \
  "asset ${fixture_dmg_name} ID does not match binding manifest" \
  "${TEMP_ROOT}/replaced-release-assets.out" \
  env \
    "PATH=${FAKE_BIN}:${PATH}" \
    RELEASE_GUARD_FAKE_TOOL=1 \
    RELEASE_REPO=fixture/repo \
    "FIXTURE_RELEASES_JSON=${fixture_replaced_assets_releases_json}" \
    "FIXTURE_EXACT_RELEASE_JSON=${fixture_replaced_assets_exact_json}" \
    "FIXTURE_CHECKSUM_FILE=${fixture_checksum_file}" \
    bash "$ROOT_DIR/script/check_release_assets.sh" "$fixture_tag" draft ignore "$fixture_release_id" "$fixture_binding_manifest" gate "$fixture_source_commit" "${fixture_provenance_args[@]}"

fixture_candidate_dir="${TEMP_ROOT}/candidate-artifact"
fixture_candidate_artifact="chronicle-release-candidate-${fixture_tag}-${fixture_staging_run_attempt}"
mkdir -p "$fixture_candidate_dir"
cp "$fixture_dmg_file" "$fixture_candidate_dir/$fixture_dmg_name"
cp "$fixture_checksum_file" "$fixture_candidate_dir/$fixture_checksum_name"
cp "$fixture_notes_file" "$fixture_candidate_dir/release-notes.md"
ruby "$ROOT_DIR/script/support/release_candidate_manifest.rb" metadata \
  "$fixture_candidate_dir/candidate-metadata.json" \
  "$fixture_tag" "$fixture_source_commit" "$fixture_repository" \
  > "${TEMP_ROOT}/candidate-metadata-create.out"
ruby "$ROOT_DIR/script/support/release_candidate_manifest.rb" create \
  "$fixture_candidate_dir/candidate-manifest.json" \
  "$fixture_candidate_dir" \
  "$fixture_candidate_artifact" \
  "$fixture_tag" \
  "$fixture_source_commit" \
  "$fixture_repository" \
  "$fixture_staging_run_id" \
  "$fixture_staging_run_attempt" \
  "$fixture_source_commit" \
  "$fixture_workflow_ref" \
  "$fixture_source_commit" \
  > "${TEMP_ROOT}/candidate-manifest-create.out"
ruby "$ROOT_DIR/script/support/release_candidate_manifest.rb" verify \
  "$fixture_candidate_dir/candidate-manifest.json" \
  "$fixture_candidate_dir" \
  "$fixture_candidate_artifact" \
  "$fixture_tag" \
  "$fixture_source_commit" \
  "$fixture_repository" \
  "$fixture_staging_run_id" \
  "$fixture_staging_run_attempt" \
  "$fixture_source_commit" \
  "$fixture_workflow_ref" \
  "$fixture_source_commit" \
  > "${TEMP_ROOT}/candidate-manifest-positive.out"

fixture_previous_dmg="${TEMP_ROOT}/Chronicle-v1.0.5.dmg"
fixture_previous_release_json="${TEMP_ROOT}/release-v1.0.5.json"
fixture_wrong_previous_release_json="${TEMP_ROOT}/release-v1.0.5-wrong.json"
fixture_clean_payload="${TEMP_ROOT}/clean-account-payload.json"
fixture_tampered_clean_payload="${TEMP_ROOT}/clean-account-payload-tampered.json"
fixture_uncanonical_clean_payload="${TEMP_ROOT}/clean-account-payload-uncanonical.json"
fixture_clean_private_key="${TEMP_ROOT}/clean-account-ed25519-private.pem"
fixture_clean_public_key="${TEMP_ROOT}/clean-account-ed25519-public.pem"
fixture_wrong_private_key="${TEMP_ROOT}/wrong-clean-account-ed25519-private.pem"
fixture_wrong_public_key="${TEMP_ROOT}/wrong-clean-account-ed25519-public.pem"
fixture_clean_signature="${TEMP_ROOT}/clean-account-payload.sig"
fixture_uncanonical_clean_signature="${TEMP_ROOT}/clean-account-payload-uncanonical.sig"
fixture_manifest_sha="$(shasum -a 256 "$fixture_candidate_dir/candidate-manifest.json" | awk '{print tolower($1)}')"
fixture_candidate_artifact_id=990001
fixture_candidate_artifact_digest="$(printf 'a%.0s' {1..64})"
fixture_clean_nonce="chronicle:${fixture_repository}:${fixture_staging_run_id}:${fixture_staging_run_attempt}:${fixture_candidate_artifact_id}:${fixture_candidate_artifact}:${fixture_manifest_sha}"
resolve_ed25519_openssl() {
  local candidate
  for candidate in \
    "$(command -v openssl 2>/dev/null || true)" \
    /opt/homebrew/opt/openssl@3/bin/openssl \
    /usr/local/opt/openssl@3/bin/openssl; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    if "$candidate" list -public-key-algorithms 2>/dev/null | grep -qi ED25519; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}
OPENSSL_BIN="$(resolve_ed25519_openssl)" \
  || fail "OpenSSL 3 with Ed25519 support is required for release guard fixtures"
printf 'published v1.0.5 fixture dmg\n' > "$fixture_previous_dmg"
ruby -rjson -rdigest -rtime -e '
  previous_dmg, previous_json, wrong_previous_json, candidate_dir,
    payload_dir, repository, nonce, artifact_name, artifact_id, artifact_digest,
    run_id, run_attempt = ARGV
  previous_sha = Digest::SHA256.file(previous_dmg).hexdigest
  previous_release = {
    "id" => 105105,
    "tag_name" => "v1.0.5",
    "draft" => false,
    "published_at" => "2026-07-20T12:00:00Z",
    "assets" => [{
      "id" => 105001,
      "name" => "Chronicle-v1.0.5.dmg",
      "size" => File.size(previous_dmg),
      "state" => "uploaded",
      "digest" => "sha256:#{previous_sha}"
    }]
  }
  File.write(previous_json, JSON.generate(previous_release))
  File.write(wrong_previous_json, JSON.generate(previous_release.merge("tag_name" => "v1.0.4")))
  manifest = JSON.parse(File.binread(File.join(candidate_dir, "candidate-manifest.json")))
  metadata = JSON.parse(File.binread(File.join(candidate_dir, "candidate-metadata.json")))
  candidate_dmg = manifest.fetch("files").find { |file| file.fetch("name") == metadata.fetch("dmg_name") }
  manifest_sha = Digest::SHA256.file(File.join(candidate_dir, "candidate-manifest.json")).hexdigest
  now = Time.now.utc
  attestation = {
    "schema_version" => 3,
    "attestation_type" => "chronicle_clean_account_release_gate",
    "status" => "passed",
    "pass" => true,
    "repository" => repository,
    "nonce" => nonce,
    "issued_at" => (now - 60).iso8601,
    "expires_at" => (now + 3600).iso8601,
    "environment" => {
      "clean_macos_account" => true,
      "macos_version" => "macOS fixture",
      "tester" => "release guard fixture"
    },
    "previous_release" => {
      "tag" => "v1.0.5",
      "release_id" => previous_release.fetch("id"),
      "dmg" => {
        "id" => previous_release.dig("assets", 0, "id"),
        "name" => previous_release.dig("assets", 0, "name"),
        "size" => previous_release.dig("assets", 0, "size"),
        "sha256" => previous_sha
      }
    },
    "candidate" => {
      "tag" => manifest.fetch("tag_name"),
      "source_commit" => manifest.fetch("source_commit"),
      "signed_and_notarized" => true,
      "actions_artifact" => {
        "id" => Integer(artifact_id, 10),
        "name" => artifact_name,
        "archive_sha256" => artifact_digest,
        "run_id" => Integer(run_id, 10),
        "run_attempt" => Integer(run_attempt, 10),
        "manifest_sha256" => manifest_sha
      },
      "dmg" => {
        "name" => candidate_dmg.fetch("name"),
        "size" => candidate_dmg.fetch("size"),
        "sha256" => candidate_dmg.fetch("sha256")
      }
    },
    "checks" => %w[upgrade relaunch preferences bookmark export rollback permission uninstall]
      .to_h { |check| [check, true] }
  }
  canonical = lambda do |value|
    case value
    when Hash
      value.keys.sort.to_h { |key| [key, canonical.call(value.fetch(key))] }
    when Array
      value.map { |item| canonical.call(item) }
    else
      value
    end
  end
  write_canonical = ->(path, value) { File.binwrite(path, JSON.generate(canonical.call(value)) << "\n") }
  variants = {
    "clean" => attestation,
    "failed-check" => Marshal.load(Marshal.dump(attestation)),
    "expired" => Marshal.load(Marshal.dump(attestation)),
    "future" => Marshal.load(Marshal.dump(attestation)),
    "overlong" => Marshal.load(Marshal.dump(attestation)),
    "wrong-repo" => Marshal.load(Marshal.dump(attestation)),
    "wrong-artifact" => Marshal.load(Marshal.dump(attestation)),
    "wrong-artifact-id" => Marshal.load(Marshal.dump(attestation)),
    "wrong-artifact-digest" => Marshal.load(Marshal.dump(attestation)),
    "wrong-run" => Marshal.load(Marshal.dump(attestation)),
    "wrong-manifest" => Marshal.load(Marshal.dump(attestation)),
    "wrong-tag" => Marshal.load(Marshal.dump(attestation)),
    "wrong-source" => Marshal.load(Marshal.dump(attestation)),
    "wrong-dmg-size" => Marshal.load(Marshal.dump(attestation)),
    "wrong-dmg-digest" => Marshal.load(Marshal.dump(attestation)),
    "wrong-previous-id" => Marshal.load(Marshal.dump(attestation))
  }
  variants.fetch("failed-check").fetch("checks")["permission"] = false
  variants.fetch("expired")["issued_at"] = (now - 7200).iso8601
  variants.fetch("expired")["expires_at"] = (now - 3600).iso8601
  variants.fetch("future")["issued_at"] = (now + 3600).iso8601
  variants.fetch("future")["expires_at"] = (now + 7200).iso8601
  overlong_issued_at = now - 60
  variants.fetch("overlong")["issued_at"] = overlong_issued_at.iso8601
  variants.fetch("overlong")["expires_at"] = (overlong_issued_at + 86_401).iso8601
  variants.fetch("wrong-repo")["repository"] = "other/repository"
  variants.fetch("wrong-artifact").dig("candidate", "actions_artifact")["name"] = "chronicle-release-candidate-v9.9.8-1"
  variants.fetch("wrong-artifact-id").dig("candidate", "actions_artifact")["id"] += 1
  variants.fetch("wrong-artifact-digest").dig("candidate", "actions_artifact")["archive_sha256"] = "b" * 64
  variants.fetch("wrong-run").dig("candidate", "actions_artifact")["run_attempt"] = 2
  variants.fetch("wrong-manifest").dig("candidate", "actions_artifact")["manifest_sha256"] = "b" * 64
  variants.fetch("wrong-tag").fetch("candidate")["tag"] = "v9.9.8"
  variants.fetch("wrong-source").fetch("candidate")["source_commit"] = "b" * 40
  variants.fetch("wrong-dmg-size").fetch("candidate").fetch("dmg")["size"] += 1
  variants.fetch("wrong-dmg-digest").fetch("candidate").fetch("dmg")["sha256"] = "b" * 64
  variants.fetch("wrong-previous-id").fetch("previous_release")["release_id"] += 1
  Dir.mkdir(payload_dir)
  variants.each { |name, value| write_canonical.call(File.join(payload_dir, "#{name}.json"), value) }
  File.binwrite(File.join(payload_dir, "uncanonical.json"), JSON.generate(attestation) << "\n")
  tampered = Marshal.load(Marshal.dump(attestation))
  tampered.fetch("environment")["tester"] = "tampered after signing"
  write_canonical.call(File.join(payload_dir, "tampered.json"), tampered)
' \
  "$fixture_previous_dmg" \
  "$fixture_previous_release_json" \
  "$fixture_wrong_previous_release_json" \
  "$fixture_candidate_dir" \
  "${TEMP_ROOT}/clean-payloads" \
  "$fixture_repository" \
  "$fixture_clean_nonce" \
  "$fixture_candidate_artifact" \
  "$fixture_candidate_artifact_id" \
  "$fixture_candidate_artifact_digest" \
  "$fixture_staging_run_id" \
  "$fixture_staging_run_attempt"

fixture_clean_payload="${TEMP_ROOT}/clean-payloads/clean.json"
fixture_tampered_clean_payload="${TEMP_ROOT}/clean-payloads/tampered.json"
fixture_uncanonical_clean_payload="${TEMP_ROOT}/clean-payloads/uncanonical.json"

"$OPENSSL_BIN" genpkey -algorithm ED25519 -out "$fixture_clean_private_key"
"$OPENSSL_BIN" pkey -in "$fixture_clean_private_key" -pubout -out "$fixture_clean_public_key"
"$OPENSSL_BIN" genpkey -algorithm ED25519 -out "$fixture_wrong_private_key"
"$OPENSSL_BIN" pkey -in "$fixture_wrong_private_key" -pubout -out "$fixture_wrong_public_key"
sign_clean_payload() {
  "$OPENSSL_BIN" pkeyutl -sign -inkey "$fixture_clean_private_key" -rawin -in "$1" -out "$2"
}
for payload in "${TEMP_ROOT}"/clean-payloads/*.json; do
  signature="${payload%.json}.sig"
  sign_clean_payload "$payload" "$signature"
done
cp "${TEMP_ROOT}/clean-payloads/clean.sig" "$fixture_clean_signature"
cp "${TEMP_ROOT}/clean-payloads/uncanonical.sig" "$fixture_uncanonical_clean_signature"

run_clean_verifier() {
  local payload="$1"
  local signature="$2"
  local public_key="$3"
  local candidate_dir="${4:-$fixture_candidate_dir}"
  local previous_json="${5:-$fixture_previous_release_json}"
  local nonce="${6:-$fixture_clean_nonce}"
  local artifact_name="${7:-$fixture_candidate_artifact}"
  local run_attempt="${8:-$fixture_staging_run_attempt}"
  local artifact_id="${9:-$fixture_candidate_artifact_id}"
  local artifact_digest="${10:-$fixture_candidate_artifact_digest}"
  env OPENSSL_BIN="$OPENSSL_BIN" ruby "$ROOT_DIR/script/support/verify_clean_account_release_attestation.rb" \
    "$payload" "$signature" "$public_key" \
    "$candidate_dir/candidate-manifest.json" "$candidate_dir" \
    "$previous_json" "$fixture_previous_dmg" \
    "$fixture_tag" "$fixture_source_commit" "$fixture_repository" "$nonce" \
    "$artifact_name" "$artifact_id" "$artifact_digest" \
    "$fixture_staging_run_id" "$run_attempt" \
    "$fixture_source_commit" "$fixture_workflow_ref" "$fixture_source_commit"
}

run_clean_verifier \
  "$fixture_clean_payload" "$fixture_clean_signature" "$fixture_clean_public_key" \
  > "${TEMP_ROOT}/clean-account-positive.out"

expect_signed_payload_failure() {
  local variant="$1"
  local expected_message="$2"
  expect_failure "$expected_message" "${TEMP_ROOT}/clean-account-${variant}.out" \
    run_clean_verifier \
      "${TEMP_ROOT}/clean-payloads/${variant}.json" \
      "${TEMP_ROOT}/clean-payloads/${variant}.sig" \
      "$fixture_clean_public_key"
}

expect_signed_payload_failure failed-check 'required clean-account check did not pass: permission'
expect_signed_payload_failure expired 'attestation has expired'
expect_signed_payload_failure future 'issued_at is too far in the future'
expect_signed_payload_failure overlong 'attestation lifetime exceeds 86400 seconds'
expect_signed_payload_failure wrong-repo 'attestation repository mismatch'
expect_signed_payload_failure wrong-artifact 'attested candidate Actions artifact name mismatch'
expect_signed_payload_failure wrong-artifact-id 'attested candidate Actions artifact ID mismatch'
expect_signed_payload_failure wrong-artifact-digest 'attested candidate Actions artifact archive SHA-256 mismatch'
expect_signed_payload_failure wrong-run 'attested candidate Actions artifact run attempt mismatch'
expect_signed_payload_failure wrong-manifest 'attested candidate manifest SHA-256 mismatch'
expect_signed_payload_failure wrong-tag 'attested candidate tag mismatch'
expect_signed_payload_failure wrong-source 'attested candidate source commit mismatch'
expect_signed_payload_failure wrong-dmg-size 'attested candidate DMG size mismatch'
expect_signed_payload_failure wrong-dmg-digest 'attested candidate DMG SHA-256 mismatch'
expect_signed_payload_failure wrong-previous-id 'attested previous release ID mismatch'

expect_failure \
  'detached Ed25519 signature verification failed' \
  "${TEMP_ROOT}/clean-account-tampered-payload.out" \
  run_clean_verifier \
    "$fixture_tampered_clean_payload" "$fixture_clean_signature" "$fixture_clean_public_key"

expect_failure \
  'detached Ed25519 signature verification failed' \
  "${TEMP_ROOT}/clean-account-wrong-public-key.out" \
  run_clean_verifier \
    "$fixture_clean_payload" "$fixture_clean_signature" "$fixture_wrong_public_key"

expect_failure \
  'previous release tag must be v1.0.5' \
  "${TEMP_ROOT}/clean-account-wrong-previous-release.out" \
  run_clean_verifier \
    "$fixture_clean_payload" "$fixture_clean_signature" "$fixture_clean_public_key" \
    "$fixture_candidate_dir" "$fixture_wrong_previous_release_json"

expect_failure \
  'candidate manifest staging provenance mismatch' \
  "${TEMP_ROOT}/clean-account-wrong-run-provenance.out" \
  run_clean_verifier \
    "$fixture_clean_payload" "$fixture_clean_signature" "$fixture_clean_public_key" \
    "$fixture_candidate_dir" "$fixture_previous_release_json" "$fixture_clean_nonce" \
    "$fixture_candidate_artifact" 2

expect_failure \
  'candidate Actions artifact name mismatch' \
  "${TEMP_ROOT}/clean-account-wrong-artifact-name.out" \
  run_clean_verifier \
    "$fixture_clean_payload" "$fixture_clean_signature" "$fixture_clean_public_key" \
    "$fixture_candidate_dir" "$fixture_previous_release_json" "$fixture_clean_nonce" \
    "chronicle-release-candidate-v9.9.8-1"

expect_failure \
  'attested candidate Actions artifact archive SHA-256 mismatch' \
  "${TEMP_ROOT}/clean-account-wrong-expected-artifact-digest.out" \
  run_clean_verifier \
    "$fixture_clean_payload" "$fixture_clean_signature" "$fixture_clean_public_key" \
    "$fixture_candidate_dir" "$fixture_previous_release_json" "$fixture_clean_nonce" \
    "$fixture_candidate_artifact" "$fixture_staging_run_attempt" "$fixture_candidate_artifact_id" \
    "$(printf 'b%.0s' {1..64})"

fixture_wrong_size_dir="${TEMP_ROOT}/candidate-wrong-size"
cp -R "$fixture_candidate_dir" "$fixture_wrong_size_dir"
printf 'x' >> "$fixture_wrong_size_dir/$fixture_dmg_name"
expect_failure \
  "candidate file size mismatch: ${fixture_dmg_name}" \
  "${TEMP_ROOT}/clean-account-wrong-file-size.out" \
  run_clean_verifier \
    "$fixture_clean_payload" "$fixture_clean_signature" "$fixture_clean_public_key" "$fixture_wrong_size_dir"

fixture_wrong_digest_dir="${TEMP_ROOT}/candidate-wrong-digest"
cp -R "$fixture_candidate_dir" "$fixture_wrong_digest_dir"
ruby -e 'path = ARGV.fetch(0); bytes = File.binread(path); bytes.setbyte(0, bytes.getbyte(0) ^ 1); File.binwrite(path, bytes)' \
  "$fixture_wrong_digest_dir/$fixture_dmg_name"
expect_failure \
  "candidate file SHA-256 mismatch: ${fixture_dmg_name}" \
  "${TEMP_ROOT}/clean-account-wrong-file-digest.out" \
  run_clean_verifier \
    "$fixture_clean_payload" "$fixture_clean_signature" "$fixture_clean_public_key" "$fixture_wrong_digest_dir"

expect_failure \
  'expected nonce does not match the exact candidate artifact identity' \
  "${TEMP_ROOT}/clean-account-replayed-nonce.out" \
  run_clean_verifier \
    "$fixture_clean_payload" "$fixture_clean_signature" "$fixture_clean_public_key" \
    "$fixture_candidate_dir" "$fixture_previous_release_json" "${fixture_clean_nonce}:replay"

expect_failure \
  'signed payload is not canonical compact JSON with one trailing LF' \
  "${TEMP_ROOT}/clean-account-uncanonical.out" \
  run_clean_verifier \
    "$fixture_uncanonical_clean_payload" "$fixture_uncanonical_clean_signature" "$fixture_clean_public_key"

workflow_path="$ROOT_DIR/.github/workflows/release.yml"
publish_workflow_path="$ROOT_DIR/.github/workflows/publish-release.yml"
dry_run_workflow_path="$ROOT_DIR/.github/workflows/release-dry-run.yml"
[[ -f "$publish_workflow_path" && ! -L "$publish_workflow_path" ]] \
  || fail "manual publish workflow is missing or unsafe"
[[ -f "$dry_run_workflow_path" && ! -L "$dry_run_workflow_path" ]] \
  || fail "unsigned dry-run workflow is missing or unsafe"
ruby -ryaml -e '
  class WorkflowAuditError < StandardError; end

  PINNED_ACTION = /\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.\/-]+@[0-9a-f]{40}\z/

  def reject(message)
    raise WorkflowAuditError, message
  end

  def steps(workflow)
    workflow.fetch("jobs").values.flat_map { |job| Array(job["steps"]) }
  end

  def assert_read_only_github_token(workflow, path)
    top_permissions = workflow["permissions"]
    unless top_permissions.is_a?(Hash) && top_permissions["contents"] == "read"
      reject "#{path}: top-level GITHUB_TOKEN contents permission must be read"
    end
    if top_permissions.value?("write")
      reject "#{path}: top-level GITHUB_TOKEN has a write permission"
    end
    workflow.fetch("jobs").each do |job_name, job|
      permissions = job["permissions"]
      next if permissions.nil?
      reject "#{path}: job #{job_name} permissions must be a map" unless permissions.is_a?(Hash)
      contents = permissions["contents"]
      if permissions.value?("write") || (!contents.nil? && contents != "read")
        reject "#{path}: job #{job_name} elevates a GITHUB_TOKEN permission"
      end
    end
  end

  def normalized(command)
    command.gsub(/\\\n\s*/, " ").gsub(/\s+/, " ")
  end

  def assert_pinned_action(step, label)
    uses = step["uses"]
    reject "#{label} must use a commit-pinned action" unless uses.is_a?(String) && uses.match?(PINNED_ACTION)
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end

  def audit_release(release, path)
    assert_read_only_github_token(release, path)
    serialized = YAML.dump(release)
    if serialized.match?(/RELEASE_(?:STAGING|PUBLISH)_TOKEN/)
      reject "staging workflow must not reference a release write token"
    end
    run_text = steps(release).map { |step| step["run"].to_s }.join("\n")
    forbidden_writes = [
      /\bgh\s+release\s+(?:create|upload|edit|delete)\b/,
      /\bgh\s+api\b.*?(?:--method|--request|-X)\s+(?:POST|PATCH|PUT|DELETE)\b/m,
      /\bcurl\b.*?(?:-X|--request)\s*(?:POST|PATCH|PUT|DELETE)\b/m,
      /Net::HTTP::(?:Post|Patch|Put|Delete)\b/,
      /github_request\(\s*["\x27](?:POST|PATCH|PUT|DELETE)["\x27]/
    ]
    reject "staging workflow contains a remote mutation" if forbidden_writes.any? { |pattern| run_text.match?(pattern) }

    jobs = release.fetch("jobs")
    stage = jobs["stage-candidate-artifact"]
    reject "staging workflow is missing stage-candidate-artifact" unless stage.is_a?(Hash)
    reject "candidate staging must depend on the validated signed build" unless Array(stage["needs"]).sort == %w[build-dmg validate-release-tag]
    reject "candidate staging contents permission must remain read-only" unless stage["permissions"] == { "contents" => "read" }
    stage_steps = Array(stage["steps"])
    stage_steps.select { |step| step.key?("uses") }.each { |step| assert_pinned_action(step, "candidate staging") }
    uploads = stage_steps.select { |step| step["uses"].to_s.start_with?("actions/upload-artifact@") }
    downloads = stage_steps.select { |step| step["uses"].to_s.start_with?("actions/download-artifact@") }
    reject "candidate staging must upload exactly one immutable candidate artifact" unless uploads.length == 1
    reject "candidate staging must download exactly one signed payload artifact" unless downloads.length == 1
    upload = uploads.fetch(0).fetch("with")
    reject "candidate artifact name must come from the bound candidate identity" unless upload["name"] == "${{ env.CANDIDATE_ARTIFACT_NAME }}"
    reject "candidate artifact path mismatch" unless upload["path"] == "build/release-candidate/"
    command = stage_steps.map { |step| step["run"].to_s }.join("\n")
    %w[metadata create verify].each do |mode|
      reject "candidate staging is missing manifest #{mode}" unless command.include?("release_candidate_manifest.rb #{mode}")
    end
    %w[
      $GITHUB_REPOSITORY $GITHUB_RUN_ID $GITHUB_RUN_ATTEMPT
      $GITHUB_SHA $GITHUB_WORKFLOW_REF $GITHUB_WORKFLOW_SHA
    ].each do |field|
      reject "candidate manifest is missing provenance field #{field}" unless command.include?(field)
    end
    reject "legacy release observation must not be a formal staging gate" if command.include?("check_release_assets.sh")
  end

  def audit_publish(publish, path)
    assert_read_only_github_token(publish, path)
    expected_concurrency = {
      "group" => "chronicle-release-publication",
      "cancel-in-progress" => false
    }
    reject "publish workflow must use one non-cancelling repository-scoped concurrency group" unless publish["concurrency"] == expected_concurrency
    jobs = publish.fetch("jobs")
    reject "publish workflow must contain only validation and mutation jobs" unless jobs.keys.sort == %w[publish-candidate validate-candidate]
    validation = jobs.fetch("validate-candidate")
    mutation = jobs.fetch("publish-candidate")
    reject "validation job is not protected by the publish environment" unless validation["environment"] == "chronicle-release-publish"
    reject "mutation job is not protected by the publish environment" unless mutation["environment"] == "chronicle-release-publish"
    reject "mutation job must consume only validated outputs" unless mutation["needs"] == "validate-candidate"

    validation_yaml = YAML.dump(validation)
    reject "validation job must never receive the publication token" if validation_yaml.include?("RELEASE_PUBLISH_TOKEN")
    validation_steps = Array(validation["steps"])
    validation_steps.select { |step| step.key?("uses") }.each { |step| assert_pinned_action(step, "publication validation") }
    checkouts = validation_steps.select { |step| step["uses"].to_s.start_with?("actions/checkout@") }
    reject "validation must have exactly one independent trusted checkout" unless checkouts.length == 1
    checkout = checkouts.fetch(0).fetch("with")
    expected_checkout = {
      "fetch-depth" => 0,
      "fetch-tags" => true,
      "ref" => "${{ github.workflow_sha }}",
      "path" => "trusted-tools",
      "persist-credentials" => false
    }
    reject "trusted checkout must be the workflow SHA in an isolated path" unless checkout == expected_checkout
    validation_run = validation_steps.map { |step| step["run"].to_s }.join("\n")
    if validation_run.match?(/\bgh\s+api\b.*?(?:--method|--request|-X)\s+(?:POST|PATCH|PUT|DELETE)\b/m)
      reject "validation job contains a GitHub mutation"
    end
    if validation_run.match?(/Net::HTTP::(?:Post|Patch|Put|Delete)\b/)
      reject "validation job contains a direct HTTP mutation"
    end
    trusted_manifest = "$GITHUB_WORKSPACE/trusted-tools/script/support/release_candidate_manifest.rb"
    trusted_attestation = "$GITHUB_WORKSPACE/trusted-tools/script/support/verify_clean_account_release_attestation.rb"
    reject "validation does not use the independent trusted candidate verifier" unless validation_run.scan(trusted_manifest).length >= 2
    reject "validation does not use the independent trusted attestation verifier" unless validation_run.include?(trusted_attestation)
    reject "validation does not bind the actual published v1.0.5 release" unless validation_run.include?("releases/tags/v1.0.5")
    reject "validation does not resolve the exact candidate through the run artifacts API" unless validation_run.include?("actions/runs/${STAGING_RUN_ID}/artifacts")
    reject "validation does not fail closed for an expired candidate artifact" unless validation_run.include?("candidate artifact is expired")
    reject "validation does not bind the Actions artifact ID and archive digest" unless validation_run.include?("CANDIDATE_ARTIFACT_ID") && validation_run.include?("CANDIDATE_ARTIFACT_DIGEST")
    %w[
      $GITHUB_REPOSITORY $STAGING_RUN_ID $STAGING_RUN_ATTEMPT
      $STAGING_RUN_HEAD_SHA $STAGING_WORKFLOW_REF $STAGING_WORKFLOW_SHA
    ].each do |field|
      reject "validation is missing provenance field #{field}" unless validation_run.include?(field)
    end
    candidate_downloads = validation_steps.select { |step| step["uses"].to_s.start_with?("actions/download-artifact@") }
    reject "validation must download exactly one selected staging artifact" unless candidate_downloads.length == 1
    candidate_download = candidate_downloads.fetch(0).fetch("with")
    reject "validation artifact download is not bound to the selected run" unless candidate_download["run-id"] == "${{ inputs.staging_run_id }}"
    reject "validation artifact download is not bound to the resolved immutable ID" unless candidate_download["artifact-ids"] == "${{ steps.provenance.outputs.candidate_artifact_id }}"
    reject "validation artifact download must not fall back to a mutable name selector" if candidate_download.key?("name")
    reject "validation artifact download must use only the read-only token" unless candidate_download["github-token"] == "${{ github.token }}"
    validation_secrets = validation_yaml.scan(/\$\{\{\s*secrets\.([A-Z0-9_]+)\s*\}\}/).flatten.sort
    expected_validation_secrets = %w[CLEAN_ACCOUNT_ATTESTATION_PAYLOAD_BASE64 CLEAN_ACCOUNT_ATTESTATION_SIGNATURE_BASE64]
    reject "validation secret surface changed: #{validation_secrets.inspect}" unless validation_secrets == expected_validation_secrets
    required_outputs = %w[
      candidate_artifact candidate_artifact_id candidate_artifact_digest manifest_sha256 release_tag source_commit
      staging_run_id staging_run_attempt staging_head_sha staging_workflow_ref staging_workflow_sha
      dmg_name dmg_size dmg_sha256 checksum_name checksum_size checksum_sha256
      notes_size notes_sha256 metadata_size metadata_sha256 prerelease make_latest
    ]
    outputs = validation.fetch("outputs", {})
    reject "validation outputs do not bind the complete publish-ready identity" unless (required_outputs - outputs.keys).empty?

    mutation_steps = Array(mutation["steps"])
    reject "mutation job must have exactly one artifact transfer and one isolated mutation step" unless mutation_steps.length == 2
    mutation_uses = mutation_steps.select { |step| step.key?("uses") }
    reject "mutation job may use only one download-artifact action" unless mutation_uses.length == 1 && mutation_uses.fetch(0)["uses"].to_s.start_with?("actions/download-artifact@")
    assert_pinned_action(mutation_uses.fetch(0), "publication mutation")
    reject "mutation job must not checkout any repository" if mutation_steps.any? { |step| step["uses"].to_s.start_with?("actions/checkout@") }
    token_steps = mutation_steps.select do |step|
      step.fetch("env", {}).values.include?("${{ secrets.RELEASE_PUBLISH_TOKEN }}")
    end
    reject "exactly one mutation run step may receive the publication token" unless token_steps.length == 1
    token_step = token_steps.fetch(0)
    reject "publication token step must receive no other step secret or token alias" unless token_step["env"] == { "RELEASE_PUBLISH_TOKEN" => "${{ secrets.RELEASE_PUBLISH_TOKEN }}" }
    reject "publication token must be attached to an inline run step" unless token_step.key?("run") && !token_step.key?("uses")
    serialized = YAML.dump(publish)
    reject "publication token reference must occur exactly once" unless serialized.scan("${{ secrets.RELEASE_PUBLISH_TOKEN }}").length == 1
    command = token_step.fetch("run")
    reject "isolated mutation must use an inline absolute-system Ruby program" unless command.include?("/usr/bin/ruby <<'"'"'RUBY'"'"'")
    forbidden_mutation_features = [
      /\bgh\b/,
      /\bcurl\b/,
      /GITHUB_PATH/,
      /(?:^|\s)(?:\.\/)?(?:script|scripts)\//,
      /trusted-tools/,
      /\b(?:system|exec|spawn)\s*\(/,
      /Open3/,
      /%x\s*[({]/,
      /`/
    ]
    reject "isolated mutation invokes an external or candidate-controlled helper" if forbidden_mutation_features.any? { |pattern| command.match?(pattern) }
    %w[Net::HTTP::Get Net::HTTP::Post Net::HTTP::Patch].each do |proof|
      reject "isolated mutation is missing #{proof}" unless command.include?(proof)
    end
    reject "isolated mutation must not rely on an undocumented If-Match precondition" if command.match?(/if-match/i)
    weak_validator_rewrites = [
      /(?:etag|entity_tag).{0,120}(?:sub|gsub|delete_prefix|delete_suffix).{0,80}W\//im,
      /W\/.{0,80}(?:etag|entity_tag)/im,
      /W\/.{0,120}(?:sub|gsub|delete_prefix|delete_suffix)/im
    ]
    if weak_validator_rewrites.any? { |pattern| command.match?(pattern) }
      reject "isolated mutation must not normalize a weak entity tag into a publication precondition"
    end
    reject "isolated mutation must fail closed if a release already exists" unless command.include?("refusing to edit or overwrite it")
    reject "isolated mutation must enumerate authenticated release inventory, including Drafts, before creation" unless command.include?(%q{/releases?per_page=100&page=#{release_page_number}})
    reject "isolated mutation release inventory scan must be bounded" unless command.include?("repository release inventory exceeds the bounded duplicate-tag scan")
    reject "isolated mutation must parse release inventory as an array of objects" unless command.include?("parse_json_array_response")
    reject "isolated mutation must not rely on the published-only release-by-tag endpoint for duplicate detection" if command.match?(/\/releases\/tags\/#\{tag\}/)
    reject "isolated mutation does not consume the validated artifact ID/digest scalars" unless command.include?("EXPECTED_CANDIDATE_ARTIFACT_ID") && command.include?("EXPECTED_CANDIDATE_ARTIFACT_DIGEST")
    reject "isolated mutation must require GitHub asset digests on upload and every re-read" unless command.scan("required_remote_sha256").length >= 3 && !command.include?("digest.empty?")
    %w[download_release_asset_bytes read_uploaded_asset_bytes application/octet-stream remote_bytes_sha256 release_updated_at asset_updated_at].each do |proof|
      reject "isolated mutation is missing full remote-byte snapshot proof #{proof}" unless command.include?(proof)
    end
    create_pattern = /github_request\(\s*"POST"\s*,\s*api_base\s*\+\s*"\/repos\/#\{repo\}\/releases"/
    patch_pattern = /github_request\(\s*"PATCH"\s*,\s*exact_uri/
    reject "isolated mutation must create the Draft itself" unless command.match?(create_pattern)
    create_body_start = command.index("create_body = JSON.generate(")
    create_request_start = create_body_start && command.index("create_response = github_request(", create_body_start)
    reject "isolated mutation is missing the exact Draft creation body" unless create_body_start && create_request_start
    create_body_command = command[create_body_start...create_request_start]
    reject "Draft creation must set the final prerelease state" unless create_body_command.include?("\"prerelease\" => prerelease")
    reject "Draft creation must not try to set latest status" if create_body_command.include?("\"make_latest\"")
    reject "isolated mutation must publish the exact release ID" unless command.match?(patch_pattern)
    reject "isolated mutation must issue exactly one publication PATCH" unless command.scan(patch_pattern).length == 1
    reject "publication PATCH body must not use a reassignable intermediate" if command.match?(/\bpatch_body\b/)
    patch_request_pattern = /patch_response\s*=\s*github_request\(\s*"PATCH"\s*,\s*exact_uri\s*,\s*token\s*,\s*body:\s*JSON\.generate\(\s*"draft"\s*=>\s*false\s*\)\s*,\s*headers:\s*\{\s*"Content-Type"\s*=>\s*"application\/json"\s*\}\s*,\s*allowed:\s*\[200\]\s*\)/m
    reject "publication PATCH must send only the exact draft-state body and content type" unless command.match?(patch_request_pattern)

    snapshot_markers = [
      "draft_response = github_request(\"GET\", exact_uri, token)",
      "trusted_draft_snapshot = validate_release.call(draft, true)",
      "pre_patch_asset_bytes = read_uploaded_asset_bytes.call",
      "pre_patch_response = github_request(\"GET\", exact_uri, token)",
      "pre_patch_draft_snapshot = validate_release.call(pre_patch_draft, true, pre_patch_asset_bytes)",
      "exact Draft drifted between trusted snapshots"
    ]
    snapshot_positions = snapshot_markers.map { |marker| command.index(marker) }
    patch_position = snapshot_positions.last && command.index("patch_response = github_request(", snapshot_positions.last)
    unless snapshot_positions.all? && snapshot_positions.each_cons(2).all? { |left, right| left < right } && patch_position && snapshot_positions.last < patch_position
      reject "publication PATCH must follow two ordered full exact-release Draft snapshots and a drift comparison"
    end
    second_get_marker = snapshot_markers.fetch(3)
    between_second_get_and_patch = command[(snapshot_positions.fetch(3) + second_get_marker.length)...patch_position]
    if between_second_get_and_patch.match?(/github_request\(|download_release_asset_bytes|http\.request/)
      reject "second exact-release GET must be the final network request before publication PATCH"
    end
    reject "isolated mutation must final-GET the exact release" unless command.include?("final_response = github_request(\"GET\", exact_uri")
    reject "isolated mutation must exact-GET for read-only PATCH recovery" unless command.include?("recovery_response = github_request(\"GET\", exact_uri, token)")
    recovery_index = command.index("rescue StandardError => error")
    reject "isolated mutation is missing explicit unknown-result recovery" unless recovery_index
    recovery_command = command[recovery_index..]
    if recovery_command.match?(/github_request\(\s*"(?:POST|PATCH|PUT|DELETE)"/)
      reject "unknown publication recovery must be read-only"
    end
    reject "unknown publication recovery must post-verify the exact transition" unless recovery_command.include?("validate_publication_transition.call(recovery_snapshot, pre_patch_draft_snapshot)")
    if command.match?(/Net::HTTP::Delete\b|github_request\(\s*["\x27]DELETE["\x27]/)
      reject "isolated mutation must never auto-delete a release"
    end
  end

  def audit_publication_texts(documents)
    forbidden_claims = [
      [/if-match/i, "undocumented conditional request header"],
      [/\betag\b/i, "entity-tag publication claim"],
      [/\bcas\b/i, "CAS publication claim"],
      [/\batomic(?:ally)?\b.{0,80}\b(?:publish|publication|release|update)/i, "atomic publication claim"]
    ]
    documents.each do |path, text|
      forbidden_claims.each do |pattern, label|
        reject "#{path}: documentation contains #{label}" if text.match?(pattern)
      end
    end
    combined = documents.values.join("\n")
    %w[cooperative single-writer repository-scoped].each do |phrase|
      reject "publication documentation is missing #{phrase}" unless combined.include?(phrase)
    end
    unless combined.include?("does not provide a server-enforced strong precondition") || combined.include?("provides no server-enforced strong precondition")
      reject "publication documentation must state the API precondition limitation honestly"
    end
    unless combined.include?("must not create a same-tag Release or edit the workflow-created Draft")
      reject "publication documentation must prohibit same-tag creation and Draft edits during the cooperative single-writer window"
    end
  end

  def audit_publication_docs(paths)
    audit_publication_texts(paths.to_h { |path| [path, File.read(path)] })
  end

  def audit(release, publish, release_path, publish_path)
    audit_release(release, release_path)
    audit_publish(publish, publish_path)
  end

  def expect_rejected(label)
    begin
      yield
    rescue WorkflowAuditError
      return
    end
    abort "semantic workflow audit accepted bypass fixture: #{label}"
  end

  release_path, publish_path, *publication_doc_paths = ARGV
  release = YAML.load_file(release_path)
  publish = YAML.load_file(publish_path)
  audit(release, publish, release_path, publish_path)
  audit_publication_docs(publication_doc_paths)

  bad_release = deep_copy(release)
  bad_release.fetch("jobs").fetch("stage-candidate-artifact").fetch("steps") << {
    "name" => "renamed remote writer",
    "run" => "gh api -X PATCH repos/example/chronicle/releases/1"
  }
  expect_rejected("alternate gh PATCH spelling") { audit_release(bad_release, "fixture-release") }

  bad_publish = deep_copy(publish)
  bad_publish.fetch("jobs").fetch("validate-candidate").fetch("steps") << {
    "name" => "action receives write token",
    "uses" => "example/remote-writer@#{"a" * 40}",
    "with" => { "token" => "${{ secrets.RELEASE_PUBLISH_TOKEN }}" }
  }
  expect_rejected("write token passed to an action") { audit_publish(bad_publish, "fixture-publish") }

  bad_publish = deep_copy(publish)
  token_step = bad_publish.fetch("jobs").fetch("publish-candidate").fetch("steps").find { |step| step.key?("run") }
  token_step["run"] = "set -euo pipefail\n/usr/bin/ruby mutate_release.rb\n"
  expect_rejected("external mutation script") { audit_publish(bad_publish, "fixture-publish") }

  bad_publish = deep_copy(publish)
  token_step = bad_publish.fetch("jobs").fetch("publish-candidate").fetch("steps").find { |step| step.key?("run") }
  token_step["run"] = token_step.fetch("run").sub("/usr/bin/ruby <<'"'"'RUBY'"'"'", "curl -X PATCH https://api.github.com/\n/usr/bin/ruby <<'"'"'RUBY'"'"'")
  expect_rejected("shell mutation added before inline validator") { audit_publish(bad_publish, "fixture-publish") }

  bad_publish = deep_copy(publish)
  token_step = bad_publish.fetch("jobs").fetch("publish-candidate").fetch("steps").find { |step| step.key?("run") }
  token_step["run"] = token_step.fetch("run").sub("require \"uri\"", "require \"uri\"\n          system(\"./candidate-publish-helper\")")
  expect_rejected("candidate helper launched from mutation") { audit_publish(bad_publish, "fixture-publish") }

  bad_publish = deep_copy(publish)
  bad_publish.delete("concurrency")
  expect_rejected("missing repository-scoped publication concurrency") { audit_publish(bad_publish, "fixture-publish") }

  bad_publish = deep_copy(publish)
  token_step = bad_publish.fetch("jobs").fetch("publish-candidate").fetch("steps").find { |step| step.key?("run") }
  token_step["run"] = token_step.fetch("run").sub(
    %q{/repos/#{repo}/releases?per_page=100&page=#{release_page_number}},
    %q{/repos/#{repo}/releases/tags/#{tag}}
  )
  expect_rejected("published-only duplicate release lookup misses Drafts") { audit_publish(bad_publish, "fixture-publish") }

  bad_publish = deep_copy(publish)
  token_step = bad_publish.fetch("jobs").fetch("publish-candidate").fetch("steps").find { |step| step.key?("run") }
  token_step["run"] = token_step.fetch("run").sub(
    "body: JSON.generate(\"draft\" => false),\n    headers: { \"Content-Type\" => \"application/json\" },",
    "body: JSON.generate(\"draft\" => false),\n    headers: { \"Content-Type\" => \"application/json\", \"If-Match\" => \"unsafe\" },"
  )
  expect_rejected("undocumented If-Match publication precondition") { audit_publish(bad_publish, "fixture-publish") }

  bad_publish = deep_copy(publish)
  token_step = bad_publish.fetch("jobs").fetch("publish-candidate").fetch("steps").find { |step| step.key?("run") }
  token_step["run"] = token_step.fetch("run").sub(
    "publication_attempted = true",
    "weak_entity_tag = \"W/unsafe\".sub(/\\AW\\//, \"\")\n            publication_attempted = true"
  )
  expect_rejected("weak entity-tag stripping") { audit_publish(bad_publish, "fixture-publish") }

  bad_publish = deep_copy(publish)
  token_step = bad_publish.fetch("jobs").fetch("publish-candidate").fetch("steps").find { |step| step.key?("run") }
  token_step["run"] = token_step.fetch("run").sub(
    "pre_patch_response = github_request(\"GET\", exact_uri, token)",
    "pre_patch_response = draft_response"
  )
  expect_rejected("missing second exact-release GET") { audit_publish(bad_publish, "fixture-publish") }

  bad_publish = deep_copy(publish)
  token_step = bad_publish.fetch("jobs").fetch("publish-candidate").fetch("steps").find { |step| step.key?("run") }
  token_step["run"] = token_step.fetch("run").sub(
    "body: JSON.generate(\"draft\" => false),",
    "body: JSON.generate(\"draft\" => false, \"prerelease\" => prerelease),"
  )
  expect_rejected("publication PATCH changes more than Draft state") { audit_publish(bad_publish, "fixture-publish") }

  bad_publish = deep_copy(publish)
  token_step = bad_publish.fetch("jobs").fetch("publish-candidate").fetch("steps").find { |step| step.key?("run") }
  token_step["run"] = token_step.fetch("run")
    .sub(
      "publication_attempted = true",
      "patch_body = JSON.generate(\"draft\" => false)\n            patch_body = JSON.generate(\"draft\" => false, \"prerelease\" => prerelease)\n            publication_attempted = true"
    )
    .sub("body: JSON.generate(\"draft\" => false),", "body: patch_body,")
  expect_rejected("safe PATCH body reassigned before use") { audit_publish(bad_publish, "fixture-publish") }

  bad_publish = deep_copy(publish)
  token_step = bad_publish.fetch("jobs").fetch("publish-candidate").fetch("steps").find { |step| step.key?("run") }
  token_step["run"] = token_step.fetch("run").sub(
    "recovery_response = github_request(\"GET\", exact_uri, token)",
    "github_request(\"PATCH\", exact_uri, token, body: JSON.generate(\"draft\" => false))\n                recovery_response = github_request(\"GET\", exact_uri, token)"
  )
  expect_rejected("publication PATCH retry during recovery") { audit_publish(bad_publish, "fixture-publish") }

  wrong_claim = publication_doc_paths.to_h { |path| [path, File.read(path)] }
  wrong_claim[publication_doc_paths.fetch(0)] += "\nThe release update provides atomic publication across competing writers.\n"
  expect_rejected("false atomic publication claim") { audit_publication_texts(wrong_claim) }
' "$workflow_path" "$publish_workflow_path" "$ROOT_DIR/README.md" "$ROOT_DIR/docs/stable-release-checklist.md" "$ROOT_DIR/docs/releases/v1.1.0.md"

if grep -Eq 'RELEASE_(STAGING|PUBLISH)_TOKEN|gh release (create|upload|edit)|--(method|request) (POST|PATCH)' "$workflow_path"; then
  fail "read-only staging workflow contains a release write capability"
fi
grep -Fq 'release_candidate_manifest.rb create' "$workflow_path" \
  || fail "release workflow does not create canonical candidate evidence"
grep -Fq 'chronicle-release-candidate-${{ github.event_name' "$workflow_path" \
  || fail "release workflow does not name the immutable candidate artifact by tag and attempt"
grep -Fq 'run_previous_release_upgrade_drill.sh' "$workflow_path" \
  || fail "release workflow does not run the bounded upgrade drill on the exact-tag UI runner"
if [[ "$(grep -Fc 'chronicle-upgrade-drill-${{ env.RELEASE_TAG }}-${{ github.run_attempt }}' "$workflow_path")" -lt 2 ]]; then
  fail "release workflow does not transfer passed upgrade-drill evidence into build-dmg"
fi
grep -Fq 'EXPECTED_TEAM_IDENTIFIER: ${{ secrets.APPLE_TEAM_ID }}' "$workflow_path" \
  || fail "release workflow does not pass the pinned Apple Team ID"
grep -Fq 'APPLE_API_ISSUER_ID APPLE_TEAM_ID; do' "$workflow_path" \
  || fail "release readiness does not require the pinned Apple Team ID"
if grep -Fq 'contents: write' "$workflow_path"; then
  fail "release workflow must keep every GITHUB_TOKEN read-only"
fi
if [[ "$(grep -Fc 'release_source_fingerprint.rb . --dirty' "$workflow_path")" -lt 4 ]]; then
  fail "release workflow does not pin clean source through preflight, tests, and signed build"
fi
if [[ "$(grep -Fc 'bash script/run_release_analyze.sh' "$workflow_path")" -ne 1 ]]; then
  fail "release workflow must invoke the shared Release Analyze wrapper exactly once"
fi
grep -Fq "steps.release_analyze.outcome == 'success'" "$workflow_path" \
  || fail "release workflow does not upload passed Release Analyze evidence"
grep -Fq "steps.release_analyze.outcome == 'failure'" "$workflow_path" \
  || fail "release workflow does not preserve failed Release Analyze diagnostics"
grep -Fq 'Release inputs changed during tests or Release Analyze.' "$workflow_path" \
  || fail "release workflow does not re-check source identity after Release Analyze"

dry_run_script="$ROOT_DIR/script/run_release_dry_run.sh"
if [[ "$(grep -Fc 'bash "$RELEASE_ANALYZE_SCRIPT"' "$dry_run_script")" -ne 1 ]]; then
  fail "authoritative dry-run must invoke the shared Release Analyze wrapper exactly once"
fi
if [[ "$(grep -Fc 'DRY_RUN_SOURCE_DIRTY=' "$dry_run_script")" -ne 1 ]]; then
  fail "dry-run manifest must bind DRY_RUN_SOURCE_DIRTY exactly once"
fi
if grep -Eq 'DRY_RUN_UNIT_RESULT_PATH|"result_bundle"[[:space:]]*=>' "$dry_run_script"; then
  fail "dry-run manifest still embeds a runner-absolute XCTest result path"
fi
grep -Fq '"schema_version" => 3' "$dry_run_script" \
  || fail "dry-run manifest did not advance to the portable Analyze-bound schema"
grep -Fq '"receipt" =>' "$dry_run_script" \
  || fail "dry-run manifest does not bind the structured Release Analyze receipt"
grep -Fq 'assert_source_unchanged "after manifest finalization"' "$dry_run_script" \
  || fail "dry-run does not re-check source identity after manifest finalization"
grep -Fq 'assert_source_unchanged "after verified evidence installation"' "$dry_run_script" \
  || fail "dry-run does not perform its final source identity check"
grep -Fq -- '--exact-files' "$dry_run_script" \
  || fail "dry-run does not verify an exact clean upload payload"
grep -Fq 'dist/dry-run/*.release-analyze.log' "$dry_run_workflow_path" \
  || fail "dry-run workflow does not preserve failed Release Analyze diagnostics"

ruby -ryaml -rrexml/document -rrexml/xpath -e '
  release_path, dry_run_path, scheme_path = ARGV
  release = YAML.load_file(release_path)
  steps = release.fetch("jobs").fetch("build-dmg").fetch("steps")
  names = steps.map { |step| step.fetch("name", "") }
  analyze_index = names.index("Run universal Release Analyze")
  import_index = names.index("Import signing certificate")
  abort "Release Analyze must run before signing credentials are imported" unless analyze_index && import_index && analyze_index < import_index

  dry_run = YAML.load_file(dry_run_path)
  dry_run_jobs = dry_run.fetch("jobs")
  upload_job = dry_run_jobs.fetch("unsigned-release-dry-run")
  expected_outputs = {
    "artifact_id" => "${{ steps.upload_candidate.outputs.artifact-id }}"
  }
  abort "Dry-run upload job outputs must expose only the uploaded artifact ID" unless upload_job.fetch("outputs") == expected_outputs
  upload = upload_job.fetch("steps").find do |step|
    step["name"] == "Upload candidate unsigned dry-run artifact"
  end
  abort "Missing candidate dry-run upload step" unless upload
  expected_paths = %w[
    build/dry-run-upload/*.dmg
    build/dry-run-upload/*.dmg.sha256
    build/dry-run-upload/*.dry-run-manifest.json
    build/dry-run-upload/*.unit-test-summary.json
    build/dry-run-upload/*.release-analyze.log
    build/dry-run-upload/*.release-analyze.receipt.json
  ]
  actual_paths = upload.fetch("with").fetch("path").lines.map(&:strip).reject(&:empty?)
  abort "Candidate dry-run upload paths changed" unless actual_paths == expected_paths
  abort "Candidate dry-run upload must expose an artifact ID" unless upload["id"] == "upload_candidate"

  immutable_job = dry_run_jobs.fetch("verify-immutable-dry-run-artifact")
  abort "Immutable verification must depend on the upload job" unless immutable_job["needs"] == "unsigned-release-dry-run"
  download = immutable_job.fetch("steps").find { |step| step["name"] == "Download immutable dry-run artifact by ID" }
  abort "Missing immutable artifact download" unless download
  expected_download = {
    "artifact-ids" => "${{ needs.unsigned-release-dry-run.outputs.artifact_id }}",
    "path" => "build/immutable-dry-run-evidence"
  }
  abort "Immutable verifier must download only the upload output artifact ID" unless download.fetch("with") == expected_download
  remote_verify = immutable_job.fetch("steps").find { |step| step["name"] == "Re-verify downloaded exact payload" }
  abort "Missing downloaded payload verifier" unless remote_verify
  remote_run = remote_verify.fetch("run")
  abort "Downloaded payload must use --exact-files" unless remote_run.include?("verify_release_dry_run_manifest.rb") && remote_run.include?("--exact-files")
  expected_remote_invocation = <<~'"'"'SHELL'"'"'
    ruby script/support/verify_release_dry_run_manifest.rb \
      "${manifests[0]}" \
      build/immutable-dry-run-evidence \
      "$fingerprint" \
      "$GITHUB_SHA" \
      "$expected_tag" \
      "$app_version" \
      "$app_build" \
      false \
      --exact-files
  SHELL
  abort "Downloaded payload must bind exact checkout and release metadata" unless remote_run.include?(expected_remote_invocation)

  verify_scheme = lambda do |xml|
    scheme = REXML::Document.new(xml)
    actions = REXML::XPath.match(scheme, "/Scheme/AnalyzeAction")
    raise "Chronicle shared scheme must use Release Analyze" unless actions.length == 1 && actions.fetch(0).attributes["buildConfiguration"] == "Release"
    entries = REXML::XPath.match(scheme, "/Scheme/BuildAction/BuildActionEntries/BuildActionEntry").select do |entry|
      reference = entry.elements["BuildableReference"]
      reference && reference.attributes["BlueprintName"] == "Chronicle" && reference.attributes["BuildableName"] == "Chronicle.app"
    end
    raise "Chronicle app must be the unique Analyze build entry" unless entries.length == 1 && entries.fetch(0).attributes["buildForAnalyzing"] == "YES"
  end
  scheme_xml = File.read(scheme_path)
  verify_scheme.call(scheme_xml)
  begin
    verify_scheme.call(scheme_xml.sub(%q{buildForAnalyzing = "YES"}, %q{buildForAnalyzing = "NO"}))
  rescue RuntimeError
    # Expected: the negative scheme fixture must be rejected.
  else
    abort "Scheme fixture accepted Chronicle buildForAnalyzing != YES"
  end
' "$workflow_path" "$dry_run_workflow_path" "$ROOT_DIR/Chronicle.xcodeproj/xcshareddata/xcschemes/Chronicle.xcscheme"

grep -Fq 'Open3.capture3(' "$ROOT_DIR/script/run_release_preflight.sh" \
  || fail "release-note freshness does not invoke git through argv-safe Open3"
if grep -Fq '`git rev-list #{base_tag}' "$ROOT_DIR/script/run_release_preflight.sh"; then
  fail "release-note freshness still shell-interpolates the documented base tag"
fi

grep -Fq 'environment: chronicle-release-publish' "$publish_workflow_path" \
  || fail "manual publication is not protected by its dedicated environment"
grep -Fq 'GITHUB_REF" != "refs/heads/main' "$publish_workflow_path" \
  || fail "manual publication does not reject non-main dispatch refs"
if grep -Fq 'contents: write' "$publish_workflow_path"; then
  fail "publish workflow must keep GITHUB_TOKEN read-only"
fi
grep -Fq 'run-id: ${{ inputs.staging_run_id }}' "$publish_workflow_path" \
  || fail "manual publication does not download evidence from the selected staging run"
grep -Fq 'CLEAN_ACCOUNT_ATTESTATION_PAYLOAD_BASE64: ${{ secrets.CLEAN_ACCOUNT_ATTESTATION_PAYLOAD_BASE64 }}' "$publish_workflow_path" \
  || fail "manual publication does not require the protected signed clean-account payload"
grep -Fq 'CLEAN_ACCOUNT_ATTESTATION_SIGNATURE_BASE64: ${{ secrets.CLEAN_ACCOUNT_ATTESTATION_SIGNATURE_BASE64 }}' "$publish_workflow_path" \
  || fail "manual publication does not require a detached clean-account signature"
grep -Fq 'clean-account-ed25519-public.pem' "$publish_workflow_path" \
  || fail "manual publication is not pinned to the reviewed clean-account public key"
grep -Fq 'RELEASE_PUBLISH_TOKEN: ${{ secrets.RELEASE_PUBLISH_TOKEN }}' "$publish_workflow_path" \
  || fail "manual publication does not isolate its remote write token"
grep -Fq 'STAGING_RUN_ATTEMPT' "$publish_workflow_path" \
  || fail "manual publication does not bind staging run attempt provenance"
grep -Fq 'verify_clean_account_release_attestation.rb' "$publish_workflow_path" \
  || fail "manual publication does not verify the clean-account attestation"
grep -Fq 'releases/tags/v1.0.5' "$publish_workflow_path" \
  || fail "manual publication does not bind the actual published v1.0.5 release"
grep -Fq 'group: chronicle-release-publication' "$publish_workflow_path" \
  || fail "manual publication does not serialize all tags in one repository-scoped group"
grep -Fq 'cancel-in-progress: false' "$publish_workflow_path" \
  || fail "manual publication concurrency may cancel an in-progress release"
if grep -Eqi 'if-match|etag' "$publish_workflow_path"; then
  fail "manual publication relies on an undocumented conditional-update mechanism"
fi
grep -Fq 'pre_patch_response = github_request("GET", exact_uri, token)' "$publish_workflow_path" \
  || fail "manual publication does not perform its second exact-release GET"
grep -Fq 'releases?per_page=100&page=#{release_page_number}' "$publish_workflow_path" \
  || fail "manual publication does not enumerate Draft and published releases before creation"
grep -Fq 'body: JSON.generate("draft" => false),' "$publish_workflow_path" \
  || fail "manual publication PATCH changes more than Draft state"
if grep -Eq '\bpatch_body\b' "$publish_workflow_path"; then
  fail "manual publication uses a reassignable PATCH body"
fi
grep -Fq 'recovery_response = github_request("GET", exact_uri, token)' "$publish_workflow_path" \
  || fail "manual publication does not use read-only exact-release recovery"
grep -Fq 'final_response = github_request("GET", exact_uri' "$publish_workflow_path" \
  || fail "manual publication does not final-verify the exact published release"
echo "Release guard fixture tests passed."
echo "Verified: read-only staging, canonical candidate bytes, immutable artifact ID/digest plus full run provenance, detached Ed25519 clean-account evidence, and an isolated cooperative single-writer publication mutation."
