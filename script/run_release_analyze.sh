#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/Chronicle.xcodeproj"
PROJECT_ARGUMENT="Chronicle.xcodeproj"
DERIVED_DATA_INPUT="${RELEASE_ANALYZE_DERIVED_DATA_PATH:-${ROOT_DIR}/build/release-analyze}"
LOG_INPUT="${RELEASE_ANALYZE_LOG_PATH:-${ROOT_DIR}/build/release-evidence/release-analyze.log}"
RECEIPT_INPUT="${RELEASE_ANALYZE_RECEIPT_PATH:-${LOG_INPUT%.log}.receipt.json}"
CLONED_SOURCE_PACKAGES_DIR="${RELEASE_ANALYZE_CLONED_SOURCE_PACKAGES_DIR:-}"
EXPECTED_SOURCE_FINGERPRINT="${RELEASE_ANALYZE_SOURCE_FINGERPRINT:-}"
SOURCE_FINGERPRINT_TOOL="${ROOT_DIR}/script/support/release_source_fingerprint.rb"
XCODEBUILD_BIN="${RELEASE_ANALYZE_XCODEBUILD:-xcodebuild}"
XCODEBUILD_ARGS=()
LOG_STAGING=""
RECEIPT_STAGING=""

absolute_path() {
  /usr/bin/ruby -e 'puts File.expand_path(ARGV.fetch(0), ARGV.fetch(1))' "$1" "$ROOT_DIR"
}

prepare_derived_data_path() {
  local expanded
  local parent
  local physical_parent
  local leaf

  expanded="$(absolute_path "$DERIVED_DATA_INPUT")"
  parent="$(dirname "$expanded")"
  leaf="$(basename "$expanded")"
  if [[ ! "$leaf" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "RELEASE_ANALYZE_DERIVED_DATA_PATH must have a safe basename: ${expanded}" >&2
    return 1
  fi
  mkdir -p "$parent"
  physical_parent="$(cd "$parent" && pwd -P)"
  DERIVED_DATA_PATH="${physical_parent}/${leaf}"
  if [[ "$DERIVED_DATA_PATH" == "/" || "$DERIVED_DATA_PATH" == "$ROOT_DIR" || "$DERIVED_DATA_PATH" == "${HOME:-}" ]]; then
    echo "Refusing unsafe Release Analyze DerivedData path: ${DERIVED_DATA_PATH}" >&2
    return 1
  fi
  if [[ -L "$DERIVED_DATA_PATH" || ( -e "$DERIVED_DATA_PATH" && ! -d "$DERIVED_DATA_PATH" ) ]]; then
    echo "Release Analyze DerivedData path must be a non-symlink directory or absent: ${DERIVED_DATA_PATH}" >&2
    return 1
  fi
}

prepare_evidence_paths() {
  local log_expanded
  local log_parent
  local physical_parent
  local log_leaf
  local receipt_expanded
  local receipt_leaf

  log_expanded="$(absolute_path "$LOG_INPUT")"
  log_parent="$(dirname "$log_expanded")"
  log_leaf="$(basename "$log_expanded")"
  if [[ ! "$log_leaf" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*[.]log$ ]]; then
    echo "RELEASE_ANALYZE_LOG_PATH must have a safe .log basename: ${log_expanded}" >&2
    return 1
  fi
  mkdir -p "$log_parent"
  physical_parent="$(cd "$log_parent" && pwd -P)"
  LOG_PATH="${physical_parent}/${log_leaf}"

  receipt_expanded="$(absolute_path "$RECEIPT_INPUT")"
  receipt_leaf="$(basename "$receipt_expanded")"
  if [[ "$(cd "$(dirname "$receipt_expanded")" && pwd -P)" != "$physical_parent" ||
        ! "$receipt_leaf" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*[.]receipt[.]json$ ]]; then
    echo "RELEASE_ANALYZE_RECEIPT_PATH must be a safe .receipt.json sibling of the log: ${receipt_expanded}" >&2
    return 1
  fi
  RECEIPT_PATH="${physical_parent}/${receipt_leaf}"

  for evidence_path in "$LOG_PATH" "$RECEIPT_PATH"; do
    if [[ -L "$evidence_path" || ( -e "$evidence_path" && ! -f "$evidence_path" ) ]]; then
      echo "Release Analyze evidence path must be a non-symlink regular file or absent: ${evidence_path}" >&2
      return 1
    fi
  done

  LOG_STAGING="$(mktemp "${physical_parent}/.${log_leaf}.tmp.XXXXXX")"
  RECEIPT_STAGING="$(mktemp "${physical_parent}/.${receipt_leaf}.tmp.XXXXXX")"
  chmod 600 "$LOG_STAGING" "$RECEIPT_STAGING"
}

finalize_log() {
  if [[ -z "$LOG_STAGING" || ! -e "$LOG_STAGING" ]]; then
    return 0
  fi
  if [[ -L "$LOG_PATH" || ( -e "$LOG_PATH" && ! -f "$LOG_PATH" ) ]]; then
    echo "Release Analyze log destination became unsafe; preserving diagnostics at ${LOG_STAGING}" >&2
    return 1
  fi
  mv -f -- "$LOG_STAGING" "$LOG_PATH"
  LOG_STAGING=""
}

finalize_receipt() {
  if [[ -z "$RECEIPT_STAGING" || ! -e "$RECEIPT_STAGING" ]]; then
    return 0
  fi
  if [[ -L "$RECEIPT_PATH" || ( -e "$RECEIPT_PATH" && ! -f "$RECEIPT_PATH" ) ]]; then
    echo "Release Analyze receipt destination became unsafe; preserving receipt at ${RECEIPT_STAGING}" >&2
    return 1
  fi
  mv -f -- "$RECEIPT_STAGING" "$RECEIPT_PATH"
  RECEIPT_STAGING=""
}

cleanup() {
  finalize_log || true
  if [[ -n "$RECEIPT_STAGING" && -f "$RECEIPT_STAGING" && ! -L "$RECEIPT_STAGING" ]]; then
    rm -f -- "$RECEIPT_STAGING"
  fi
}
trap cleanup EXIT

if [[ ! -d "$PROJECT_PATH" || -L "$PROJECT_PATH" ]]; then
  echo "Chronicle Xcode project is missing or unsafe: ${PROJECT_PATH}" >&2
  exit 1
fi
if [[ ! -f "$SOURCE_FINGERPRINT_TOOL" || -L "$SOURCE_FINGERPRINT_TOOL" ]]; then
  echo "Release source fingerprint tool is missing or unsafe: ${SOURCE_FINGERPRINT_TOOL}" >&2
  exit 1
fi
if ! command -v "$XCODEBUILD_BIN" >/dev/null 2>&1; then
  echo "Release Analyze requires xcodebuild: ${XCODEBUILD_BIN}" >&2
  exit 127
fi
if [[ "$(basename "$XCODEBUILD_BIN")" != "xcodebuild" ]]; then
  echo "RELEASE_ANALYZE_XCODEBUILD must resolve to an executable named xcodebuild: ${XCODEBUILD_BIN}" >&2
  exit 1
fi

prepare_derived_data_path
prepare_evidence_paths

XCODEBUILD_ARGS=(
  -project "$PROJECT_ARGUMENT"
  -scheme Chronicle
  -configuration Release
  -destination 'generic/platform=macOS'
  -derivedDataPath "$DERIVED_DATA_PATH"
)

if [[ -n "$CLONED_SOURCE_PACKAGES_DIR" ]]; then
  if [[ ! -d "$CLONED_SOURCE_PACKAGES_DIR" || -L "$CLONED_SOURCE_PACKAGES_DIR" ]]; then
    echo "RELEASE_ANALYZE_CLONED_SOURCE_PACKAGES_DIR must be a non-symlink directory: ${CLONED_SOURCE_PACKAGES_DIR}" >&2
    exit 1
  fi
  CLONED_SOURCE_PACKAGES_DIR="$(cd "$CLONED_SOURCE_PACKAGES_DIR" && pwd -P)"
  XCODEBUILD_ARGS+=(
    -clonedSourcePackagesDirPath "$CLONED_SOURCE_PACKAGES_DIR"
    -disableAutomaticPackageResolution
  )
fi

XCODEBUILD_ARGS+=(
  'ARCHS=arm64 x86_64'
  ONLY_ACTIVE_ARCH=NO
  CODE_SIGNING_ALLOWED=NO
  clean
  analyze
)

COMMAND_JSON="$(
  /usr/bin/ruby -rjson -e '
    executable, derived_data_path, cloned_source_packages_path, *argv = ARGV
    command = {
      "executable" => File.basename(executable),
      "project" => "Chronicle.xcodeproj",
      "scheme" => "Chronicle",
      "action" => "analyze",
      "configuration" => "Release",
      "destination" => "generic/platform=macOS",
      "architectures" => %w[arm64 x86_64],
      "only_active_arch" => false,
      "code_signing_allowed" => false,
      "derived_data_path" => derived_data_path,
      "cloned_source_packages_path" => cloned_source_packages_path.empty? ? nil : cloned_source_packages_path,
      "argv" => argv
    }
    puts JSON.generate(command)
  ' "$XCODEBUILD_BIN" "$DERIVED_DATA_PATH" "$CLONED_SOURCE_PACKAGES_DIR" "${XCODEBUILD_ARGS[@]}"
)"

SOURCE_FINGERPRINT_BEFORE="$(/usr/bin/ruby "$SOURCE_FINGERPRINT_TOOL" "$ROOT_DIR")"
if [[ -n "$EXPECTED_SOURCE_FINGERPRINT" && "$SOURCE_FINGERPRINT_BEFORE" != "$EXPECTED_SOURCE_FINGERPRINT" ]]; then
  echo "Release Analyze source fingerprint does not match the caller's expected source." >&2
  exit 1
fi
STARTED_AT="$(/usr/bin/ruby -rtime -e 'puts Time.now.utc.iso8601(6)')"

echo "Running Chronicle Release Analyze for arm64 and x86_64..."
echo "Release Analyze log: ${LOG_PATH}"
echo "Release Analyze receipt: ${RECEIPT_PATH}"

cd "$ROOT_DIR"
set +e
{
  printf 'CHRONICLE_RELEASE_ANALYZE_COMMAND %s\n' "$COMMAND_JSON"
  "$XCODEBUILD_BIN" "${XCODEBUILD_ARGS[@]}"
} 2>&1 | tee "$LOG_STAGING"
analyze_status=$?
set -e
FINISHED_AT="$(/usr/bin/ruby -rtime -e 'puts Time.now.utc.iso8601(6)')"
SOURCE_FINGERPRINT_AFTER="$(/usr/bin/ruby "$SOURCE_FINGERPRINT_TOOL" "$ROOT_DIR")"

if ! finalize_log; then
  exit 1
fi

RELEASE_ANALYZE_COMMAND_JSON="$COMMAND_JSON" \
RELEASE_ANALYZE_STARTED_AT="$STARTED_AT" \
RELEASE_ANALYZE_FINISHED_AT="$FINISHED_AT" \
RELEASE_ANALYZE_EXIT_CODE="$analyze_status" \
RELEASE_ANALYZE_SOURCE_BEFORE="$SOURCE_FINGERPRINT_BEFORE" \
RELEASE_ANALYZE_SOURCE_AFTER="$SOURCE_FINGERPRINT_AFTER" \
RELEASE_ANALYZE_LOG_PATH_VALUE="$LOG_PATH" \
RELEASE_ANALYZE_RECEIPT_STAGING="$RECEIPT_STAGING" \
  /usr/bin/ruby -rdigest -rjson -e '
    log_path = ENV.fetch("RELEASE_ANALYZE_LOG_PATH_VALUE")
    flags = File::RDONLY | File::NOFOLLOW
    log_bytes = File.open(log_path, flags) do |file|
      before = file.stat
      abort "Release Analyze log is not a single-link regular file" unless before.file? && before.nlink == 1
      bytes = file.read
      after = file.stat
      identity = ->(stat) { [stat.dev, stat.ino, stat.size, stat.mtime.to_r, stat.ctime.to_r, stat.nlink] }
      abort "Release Analyze log changed while creating its receipt" unless identity.call(before) == identity.call(after)
      bytes
    end
    receipt = {
      "schema_version" => 1,
      "receipt_type" => "chronicle_release_analyze_execution",
      "command" => JSON.parse(ENV.fetch("RELEASE_ANALYZE_COMMAND_JSON")),
      "result" => {
        "exit_code" => Integer(ENV.fetch("RELEASE_ANALYZE_EXIT_CODE"), 10),
        "started_at" => ENV.fetch("RELEASE_ANALYZE_STARTED_AT"),
        "finished_at" => ENV.fetch("RELEASE_ANALYZE_FINISHED_AT")
      },
      "source" => {
        "fingerprint_schema" => "chronicle-release-source-fingerprint-v1",
        "before" => ENV.fetch("RELEASE_ANALYZE_SOURCE_BEFORE"),
        "after" => ENV.fetch("RELEASE_ANALYZE_SOURCE_AFTER")
      },
      "log" => {
        "name" => File.basename(log_path),
        "size" => log_bytes.bytesize,
        "sha256" => Digest::SHA256.hexdigest(log_bytes)
      }
    }
    path = ENV.fetch("RELEASE_ANALYZE_RECEIPT_STAGING")
    path_before = File.lstat(path)
    abort "Release Analyze receipt staging path is unsafe" unless path_before.file? && !path_before.symlink? && path_before.nlink == 1 && path_before.size.zero?
    receipt_bytes = JSON.pretty_generate(receipt) << "\n"
    File.open(path, File::RDWR | File::NOFOLLOW) do |file|
      fd_before = file.stat
      identity = ->(stat) { [stat.dev, stat.ino, stat.mode, stat.nlink] }
      abort "Release Analyze receipt staging identity changed before open" unless identity.call(path_before) == identity.call(fd_before)
      file.rewind
      file.write(receipt_bytes)
      file.truncate(receipt_bytes.bytesize)
      file.flush
      file.fsync
      fd_after = file.stat
      abort "Release Analyze receipt staging identity changed while writing" unless identity.call(fd_before) == identity.call(fd_after)
    end
    path_after = File.lstat(path)
    unless [path_after.dev, path_after.ino, path_after.mode, path_after.nlink] == [path_before.dev, path_before.ino, path_before.mode, path_before.nlink] && path_after.size == receipt_bytes.bytesize
      abort "Release Analyze receipt staging path changed after writing"
    end
  '

if ! finalize_receipt; then
  exit 1
fi
trap - EXIT

if [[ "$analyze_status" -ne 0 ]]; then
  echo "Release Analyze failed with status ${analyze_status}; diagnostics remain at ${LOG_PATH} and ${RECEIPT_PATH}" >&2
  exit "$analyze_status"
fi
if [[ "$SOURCE_FINGERPRINT_BEFORE" != "$SOURCE_FINGERPRINT_AFTER" ]]; then
  echo "Release inputs changed during Release Analyze." >&2
  echo "Before: ${SOURCE_FINGERPRINT_BEFORE}" >&2
  echo "After: ${SOURCE_FINGERPRINT_AFTER}" >&2
  exit 1
fi
if [[ ! -s "$LOG_PATH" || -L "$LOG_PATH" || ! -s "$RECEIPT_PATH" || -L "$RECEIPT_PATH" ]]; then
  echo "Release Analyze did not produce safe, non-empty log and receipt evidence." >&2
  exit 1
fi
if ! grep -Fxq '** ANALYZE SUCCEEDED **' "$LOG_PATH"; then
  echo "Release Analyze log is missing the exact success marker: ${LOG_PATH}" >&2
  exit 1
fi
if grep -Fq '** ANALYZE FAILED **' "$LOG_PATH"; then
  echo "Release Analyze log contains a failure marker: ${LOG_PATH}" >&2
  exit 1
fi

echo "Release Analyze passed for Release arm64 and x86_64."
echo "Release Analyze SHA-256: $(shasum -a 256 "$LOG_PATH" | awk '{print tolower($1)}')"
echo "Release Analyze receipt installed last as the evidence commit marker."
