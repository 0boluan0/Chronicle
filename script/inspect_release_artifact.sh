#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="${ROOT_DIR}/Chronicle.xcodeproj/project.pbxproj"
DMG_INPUT="${1:-}"
INSPECTION_MODE="${2:-release}"
EXPECTED_MINIMUM_MACOS="${EXPECTED_MINIMUM_MACOS:-14.0}"

usage() {
  echo "Usage: $0 <path-to-dmg> [release|rehearsal]" >&2
  echo "  release: require Developer ID, hardened runtime, secure timestamp, stapling, and Gatekeeper acceptance" >&2
  echo "  rehearsal: run the same structural checks while allowing ad hoc/unsigned and unnotarized artifacts" >&2
}

if [[ -z "$DMG_INPUT" ]]; then
  usage
  exit 64
fi

case "$INSPECTION_MODE" in
  release|rehearsal)
    ;;
  *)
    usage
    echo "Unknown inspection mode: $INSPECTION_MODE" >&2
    exit 64
    ;;
esac

for required_command in hdiutil plutil lipo vtool codesign xcrun spctl ruby file find cmp; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Required artifact inspection command is unavailable: $required_command" >&2
    exit 127
  fi
done

if [[ "$INSPECTION_MODE" == "release" ]]; then
  EXPECTED_TEAM_IDENTIFIER="${EXPECTED_TEAM_IDENTIFIER:-}"
  if [[ -z "$EXPECTED_TEAM_IDENTIFIER" ]]; then
    echo "EXPECTED_TEAM_IDENTIFIER is required in release mode." >&2
    exit 64
  fi
  if ! [[ "$EXPECTED_TEAM_IDENTIFIER" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "EXPECTED_TEAM_IDENTIFIER must be an exact 10-character Apple Team ID." >&2
    exit 64
  fi
fi

if [[ "$DMG_INPUT" == /* ]]; then
  DMG_PATH="$DMG_INPUT"
else
  DMG_PATH="${PWD}/${DMG_INPUT}"
fi

if [[ ! -f "$DMG_PATH" || -L "$DMG_PATH" || ! -s "$DMG_PATH" ]]; then
  echo "DMG must be a non-symlink, non-empty regular file: $DMG_PATH" >&2
  exit 1
fi

DMG_DIRECTORY="$(cd "$(dirname "$DMG_PATH")" && pwd -P)"
DMG_PATH="${DMG_DIRECTORY}/$(basename "$DMG_PATH")"

project_value() {
  local setting="$1"
  ruby -e '
    setting = ARGV.fetch(0)
    project = File.read(ARGV.fetch(1))
    values = project.scan(/^\s*#{Regexp.escape(setting)} = ([^;]+);/).flatten.map(&:strip).uniq
    abort("Expected one #{setting}, found #{values.inspect}") unless values.length == 1
    puts values.fetch(0)
  ' "$setting" "$PROJECT_FILE"
}

EXPECTED_APP_VERSION="${EXPECTED_APP_VERSION:-$(project_value MARKETING_VERSION)}"
EXPECTED_APP_BUILD="${EXPECTED_APP_BUILD:-$(project_value CURRENT_PROJECT_VERSION)}"

normalize_macos_version() {
  local raw="$1"
  local major=""
  local minor=""
  local patch=""
  local extra=""

  if ! [[ "$raw" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
    echo "Invalid macOS version: $raw" >&2
    return 1
  fi

  IFS=. read -r major minor patch extra <<< "$raw"
  minor="${minor:-0}"
  patch="${patch:-0}"
  if [[ -n "$extra" ]]; then
    echo "Invalid macOS version: $raw" >&2
    return 1
  fi
  printf '%d.%d.%d\n' "$((10#$major))" "$((10#$minor))" "$((10#$patch))"
}

macos_version_is_at_most() {
  local actual_normalized
  local maximum_normalized
  local actual_major
  local actual_minor
  local actual_patch
  local maximum_major
  local maximum_minor
  local maximum_patch

  actual_normalized="$(normalize_macos_version "$1")"
  maximum_normalized="$(normalize_macos_version "$2")"
  IFS=. read -r actual_major actual_minor actual_patch <<< "$actual_normalized"
  IFS=. read -r maximum_major maximum_minor maximum_patch <<< "$maximum_normalized"

  if (( actual_major != maximum_major )); then
    if (( actual_major < maximum_major )); then
      return 0
    fi
    return 1
  fi
  if (( actual_minor != maximum_minor )); then
    if (( actual_minor < maximum_minor )); then
      return 0
    fi
    return 1
  fi
  if (( actual_patch <= maximum_patch )); then
    return 0
  fi
  return 1
}

EXPECTED_MINIMUM_NORMALIZED="$(normalize_macos_version "$EXPECTED_MINIMUM_MACOS")"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/chronicle-artifact-inspection.XXXXXX")"
MOUNT_DIR="${TEMP_ROOT}/mounted-dmg"
IS_MOUNTED=0

cleanup() {
  if [[ "$IS_MOUNTED" == "1" ]]; then
    hdiutil detach "$MOUNT_DIR" -quiet || true
  fi
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

echo "Verifying DMG image: $DMG_PATH"
hdiutil verify "$DMG_PATH"

if [[ "$INSPECTION_MODE" == "release" ]]; then
  echo "Validating stapled notarization ticket..."
  xcrun stapler validate "$DMG_PATH"
else
  if staple_output="$(xcrun stapler validate "$DMG_PATH" 2>&1)"; then
    echo "Rehearsal artifact has a valid stapled ticket."
  else
    echo "Rehearsal allows an unstapled DMG: ${staple_output##*$'\n'}"
  fi
fi

mkdir -p "$MOUNT_DIR"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_DIR" "$DMG_PATH" >/dev/null
IS_MOUNTED=1

APP_PATH="${MOUNT_DIR}/Chronicle.app"
INFO_PLIST="${APP_PATH}/Contents/Info.plist"
BINARY_PATH="${APP_PATH}/Contents/MacOS/Chronicle"
SOURCE_LICENSE="${ROOT_DIR}/LICENSE"
BUNDLED_LICENSE="${APP_PATH}/Contents/Resources/LICENSE"
DMG_LICENSE="${MOUNT_DIR}/LICENSE"
SOURCE_THIRD_PARTY_NOTICES="${ROOT_DIR}/Chronicle/Resources/ThirdPartyNotices.md"
BUNDLED_THIRD_PARTY_NOTICES="${APP_PATH}/Contents/Resources/ThirdPartyNotices.md"
DMG_THIRD_PARTY_NOTICES="${MOUNT_DIR}/ThirdPartyNotices.md"

if [[ ! -d "$APP_PATH" || -L "$APP_PATH" ]]; then
  echo "DMG does not contain a safe Chronicle.app bundle." >&2
  exit 1
fi
if [[ ! -f "$INFO_PLIST" || -L "$INFO_PLIST" ]]; then
  echo "DMG does not contain a safe Chronicle.app Info.plist." >&2
  exit 1
fi
if [[ ! -f "$BINARY_PATH" || -L "$BINARY_PATH" || ! -x "$BINARY_PATH" ]]; then
  echo "DMG does not contain a safe executable Chronicle binary." >&2
  exit 1
fi
if [[ "$(LC_ALL=C file -b "$BINARY_PATH")" != *"Mach-O"* ]]; then
  echo "Chronicle main executable is not a real Mach-O file." >&2
  exit 1
fi

if [[ ! -f "$SOURCE_LICENSE" || -L "$SOURCE_LICENSE" || ! -s "$SOURCE_LICENSE" ]]; then
  echo "Reviewed source project license is missing or unsafe: ${SOURCE_LICENSE}" >&2
  exit 1
fi
for license_path in "$BUNDLED_LICENSE" "$DMG_LICENSE"; do
  if [[ ! -f "$license_path" || -L "$license_path" || ! -s "$license_path" ]]; then
    echo "Release artifact is missing a safe project license: ${license_path#"$MOUNT_DIR"/}" >&2
    exit 1
  fi
  if ! cmp -s "$SOURCE_LICENSE" "$license_path"; then
    echo "Release artifact project license differs from the reviewed source: ${license_path#"$MOUNT_DIR"/}" >&2
    exit 1
  fi
done
echo "Project license verified in Chronicle.app and at the DMG root."

if [[ ! -f "$SOURCE_THIRD_PARTY_NOTICES" || -L "$SOURCE_THIRD_PARTY_NOTICES" || ! -s "$SOURCE_THIRD_PARTY_NOTICES" ]]; then
  echo "Reviewed source third-party notices are missing or unsafe: ${SOURCE_THIRD_PARTY_NOTICES}" >&2
  exit 1
fi
for notice_path in "$BUNDLED_THIRD_PARTY_NOTICES" "$DMG_THIRD_PARTY_NOTICES"; do
  if [[ ! -f "$notice_path" || -L "$notice_path" || ! -s "$notice_path" ]]; then
    echo "Release artifact is missing safe third-party notices: ${notice_path#"$MOUNT_DIR"/}" >&2
    exit 1
  fi
  if ! cmp -s "$SOURCE_THIRD_PARTY_NOTICES" "$notice_path"; then
    echo "Release artifact third-party notices differ from the reviewed source: ${notice_path#"$MOUNT_DIR"/}" >&2
    exit 1
  fi
done
echo "Third-party notices verified in Chronicle.app and at the DMG root."

BUNDLED_VERSION="$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")"
BUNDLED_BUILD="$(plutil -extract CFBundleVersion raw "$INFO_PLIST")"
BUNDLED_MINIMUM_MACOS="$(plutil -extract LSMinimumSystemVersion raw "$INFO_PLIST")"

if [[ "$BUNDLED_VERSION" != "$EXPECTED_APP_VERSION" ]]; then
  echo "Bundle version mismatch: expected ${EXPECTED_APP_VERSION}, got ${BUNDLED_VERSION}." >&2
  exit 1
fi
if [[ "$BUNDLED_BUILD" != "$EXPECTED_APP_BUILD" ]]; then
  echo "Bundle build mismatch: expected ${EXPECTED_APP_BUILD}, got ${BUNDLED_BUILD}." >&2
  exit 1
fi
if [[ "$(normalize_macos_version "$BUNDLED_MINIMUM_MACOS")" != "$EXPECTED_MINIMUM_NORMALIZED" ]]; then
  echo "Info.plist minimum macOS mismatch: expected ${EXPECTED_MINIMUM_MACOS}, got ${BUNDLED_MINIMUM_MACOS}." >&2
  exit 1
fi

validate_macho_binary() {
  local macho_path="$1"
  local relative_path="${macho_path#"$APP_PATH"/}"
  local architectures
  local -a architecture_list=()
  local required_arch
  local build_info
  local platform
  local minimum_macos

  architectures="$(lipo -archs "$macho_path")"
  read -r -a architecture_list <<< "$architectures"
  if [[ "${#architecture_list[@]}" -ne 2 ]]; then
    echo "Mach-O ${relative_path} must contain exactly arm64 and x86_64; got: ${architectures}" >&2
    return 1
  fi

  for required_arch in arm64 x86_64; do
    if [[ " ${architectures} " != *" ${required_arch} "* ]]; then
      echo "Mach-O ${relative_path} is missing required architecture ${required_arch}: ${architectures}" >&2
      return 1
    fi

    build_info="$(vtool -arch "$required_arch" -show-build "$macho_path")"
    platform="$(
      printf '%s\n' "$build_info" \
        | awk '$1 == "platform" { print $2 } $1 == "cmd" && $2 == "LC_VERSION_MIN_MACOSX" { print "MACOS" }' \
        | sort -u
    )"
    minimum_macos="$(
      printf '%s\n' "$build_info" \
        | awk '
            $1 == "cmd" { legacy_macos = ($2 == "LC_VERSION_MIN_MACOSX") }
            $1 == "minos" { print $2 }
            legacy_macos && $1 == "version" { print $2 }
          ' \
        | sort -u
    )"
    if [[ "$platform" != "MACOS" ]]; then
      echo "Mach-O ${relative_path} ${required_arch} slice has unexpected platform metadata: ${platform:-<missing>}" >&2
      return 1
    fi
    if [[ -z "$minimum_macos" || "$minimum_macos" == *$'\n'* ]]; then
      echo "Mach-O ${relative_path} ${required_arch} slice must contain exactly one minimum macOS version; got: ${minimum_macos:-<missing>}" >&2
      return 1
    fi
    if [[ "$macho_path" == "$BINARY_PATH" ]]; then
      if [[ "$(normalize_macos_version "$minimum_macos")" != "$EXPECTED_MINIMUM_NORMALIZED" ]]; then
        echo "Main executable ${required_arch} minimum macOS mismatch: expected exactly ${EXPECTED_MINIMUM_MACOS}, got ${minimum_macos}." >&2
        return 1
      fi
    elif ! macos_version_is_at_most "$minimum_macos" "$EXPECTED_MINIMUM_MACOS"; then
      echo "Nested Mach-O ${relative_path} ${required_arch} minimum macOS ${minimum_macos} exceeds compatibility target ${EXPECTED_MINIMUM_MACOS}." >&2
      return 1
    fi
  done

  if [[ "$macho_path" == "$BINARY_PATH" ]]; then
    echo "Mach-O verified: ${relative_path} (${architectures}, macOS exactly ${EXPECTED_MINIMUM_MACOS})"
  else
    echo "Mach-O verified: ${relative_path} (${architectures}, min macOS <= ${EXPECTED_MINIMUM_MACOS})"
  fi
}

MACHO_COUNT=0
MAIN_MACHO_COUNT=0
SQLCIPHER_MACHO_COUNT=0
while IFS= read -r -d '' candidate_path; do
  file_description="$(LC_ALL=C file -b "$candidate_path")"
  if [[ "$file_description" != *"Mach-O"* ]]; then
    continue
  fi

  validate_macho_binary "$candidate_path"
  MACHO_COUNT=$((MACHO_COUNT + 1))
  if [[ "$candidate_path" == "$BINARY_PATH" ]]; then
    MAIN_MACHO_COUNT=$((MAIN_MACHO_COUNT + 1))
  fi
  if [[ "$candidate_path" == "$APP_PATH"/Contents/Frameworks/SQLCipher.framework/* ]]; then
    SQLCIPHER_MACHO_COUNT=$((SQLCIPHER_MACHO_COUNT + 1))
  fi
done < <(find "$APP_PATH" -type f -print0)

if [[ "$MACHO_COUNT" -eq 0 ]]; then
  echo "Chronicle.app does not contain any real Mach-O files." >&2
  exit 1
fi
if [[ "$MAIN_MACHO_COUNT" -ne 1 ]]; then
  echo "Chronicle.app must contain exactly one inspected main Mach-O executable; found ${MAIN_MACHO_COUNT}." >&2
  exit 1
fi
if [[ "$SQLCIPHER_MACHO_COUNT" -eq 0 ]]; then
  echo "Chronicle.app does not contain a real Mach-O inside SQLCipher.framework." >&2
  exit 1
fi

if [[ "$INSPECTION_MODE" == "release" ]]; then
  echo "Validating Developer ID signature and hardened runtime..."
  codesign --verify --deep --strict --verbose=4 "$APP_PATH"
  SIGNATURE_DETAILS="$(codesign -d --verbose=4 "$APP_PATH" 2>&1)"

  if [[ "$SIGNATURE_DETAILS" != *"Authority=Developer ID Application:"* ]]; then
    echo "Chronicle.app is not signed with a Developer ID Application certificate." >&2
    printf '%s\n' "$SIGNATURE_DETAILS" >&2
    exit 1
  fi
  if [[ "$SIGNATURE_DETAILS" == *"Signature=adhoc"* || "$SIGNATURE_DETAILS" == *"TeamIdentifier=not set"* ]]; then
    echo "Chronicle.app has an ad hoc or unidentified signature." >&2
    exit 1
  fi
  ACTUAL_TEAM_IDENTIFIER="$(printf '%s\n' "$SIGNATURE_DETAILS" | sed -n 's/^TeamIdentifier=//p' | sort -u)"
  if [[ "$ACTUAL_TEAM_IDENTIFIER" != "$EXPECTED_TEAM_IDENTIFIER" ]]; then
    echo "Chronicle.app TeamIdentifier mismatch: expected ${EXPECTED_TEAM_IDENTIFIER}, got ${ACTUAL_TEAM_IDENTIFIER:-<missing>}." >&2
    exit 1
  fi
  if ! printf '%s\n' "$SIGNATURE_DETAILS" | grep -Eq '^CodeDirectory .*flags=.*\(.*runtime.*\)'; then
    echo "Chronicle.app does not have hardened runtime enabled." >&2
    exit 1
  fi
  if ! printf '%s\n' "$SIGNATURE_DETAILS" | grep -Eq '^Timestamp='; then
    echo "Chronicle.app signature does not contain a secure timestamp." >&2
    exit 1
  fi

  echo "Running Gatekeeper assessment..."
  if ! GATEKEEPER_OUTPUT="$(LC_ALL=C spctl --assess --type execute --verbose=4 "$APP_PATH" 2>&1)"; then
    printf '%s\n' "$GATEKEEPER_OUTPUT" >&2
    echo "Gatekeeper rejected Chronicle.app." >&2
    exit 1
  fi
  printf '%s\n' "$GATEKEEPER_OUTPUT"
else
  if codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1; then
    SIGNATURE_DETAILS="$(codesign -d --verbose=4 "$APP_PATH" 2>&1 || true)"
    if [[ "$SIGNATURE_DETAILS" == *"Authority=Developer ID Application:"* ]]; then
      echo "Rehearsal artifact contains a valid Developer ID signature."
    else
      echo "Rehearsal artifact contains a valid ad hoc/non-distribution signature."
    fi
  else
    echo "Rehearsal allows an unsigned app bundle."
  fi

  if GATEKEEPER_OUTPUT="$(LC_ALL=C spctl --assess --type execute --verbose=4 "$APP_PATH" 2>&1)"; then
    echo "Gatekeeper accepted the rehearsal artifact."
    printf '%s\n' "$GATEKEEPER_OUTPUT"
  else
    echo "Rehearsal allows Gatekeeper rejection: ${GATEKEEPER_OUTPUT##*$'\n'}"
  fi
fi

hdiutil detach "$MOUNT_DIR" -quiet
IS_MOUNTED=0

echo "Release artifact inspection passed."
echo "Mode: ${INSPECTION_MODE}"
echo "Version: ${BUNDLED_VERSION} (${BUNDLED_BUILD})"
echo "Mach-O files: ${MACHO_COUNT} (main ${MAIN_MACHO_COUNT}; SQLCipher.framework ${SQLCIPHER_MACHO_COUNT})"
echo "Minimum macOS policy: main executable and Info.plist exactly ${EXPECTED_MINIMUM_MACOS}; nested Mach-O <= ${EXPECTED_MINIMUM_MACOS}"
if [[ "$INSPECTION_MODE" == "release" ]]; then
  echo "Team identifier: ${EXPECTED_TEAM_IDENTIFIER}"
fi
echo "DMG: ${DMG_PATH}"
