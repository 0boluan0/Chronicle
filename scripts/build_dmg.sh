#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/Chronicle.xcodeproj"
SCHEME="Chronicle"
CONFIGURATION="Release"
DERIVED_DATA="${DERIVED_DATA:-${ROOT_DIR}/build/dmg-release}"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/dist}"
DMG_VERSION="${DMG_VERSION:-dev}"
APP_NAME="Chronicle"
LICENSE_SOURCE="${ROOT_DIR}/LICENSE"
THIRD_PARTY_NOTICES_SOURCE="${ROOT_DIR}/Chronicle/Resources/ThirdPartyNotices.md"
REQUIRE_SIGNING="${REQUIRE_SIGNING:-0}"
REQUIRE_NOTARIZATION="${REQUIRE_NOTARIZATION:-0}"
CLONED_SOURCE_PACKAGES_DIR="${CLONED_SOURCE_PACKAGES_DIR:-}"
PACKAGE_CACHE_ARGS=()

canonical_build_path() {
  local candidate="$1"
  local parent
  local leaf

  if [[ -z "$candidate" || "$candidate" != /* || "$candidate" == *"/../"* || "$candidate" == */.. || "$candidate" == *"/./"* || "$candidate" == */. ]]; then
    echo "Refusing unsafe build path: ${candidate:-<empty>}" >&2
    return 1
  fi

  parent="$(dirname "$candidate")"
  leaf="$(basename "$candidate")"
  if [[ ! -d "$parent" ]]; then
    echo "Build path parent does not exist: ${parent}" >&2
    return 1
  fi
  parent="$(cd "$parent" && pwd -P)"
  printf '%s/%s\n' "$parent" "$leaf"
}

mkdir -p "${ROOT_DIR}/build"
DERIVED_DATA="$(canonical_build_path "$DERIVED_DATA")"
ROOT_BUILD_DIR="$(canonical_build_path "${ROOT_DIR}/build/placeholder")"
ROOT_BUILD_DIR="$(dirname "$ROOT_BUILD_DIR")"
TEMP_BUILD_DIR="$(cd "${TMPDIR:-/tmp}" && pwd -P)"

case "$DERIVED_DATA" in
  "${ROOT_BUILD_DIR}"/*|"${TEMP_BUILD_DIR}"/chronicle-*/*|/private/tmp/chronicle-*/*|/tmp/chronicle-*/*)
    ;;
  *)
    echo "Refusing to delete DERIVED_DATA outside Chronicle's build directory or a Chronicle temporary directory: ${DERIVED_DATA}" >&2
    exit 1
    ;;
esac

if [[ "$DERIVED_DATA" == "/" || "$DERIVED_DATA" == "$ROOT_DIR" || "$DERIVED_DATA" == "${HOME:-}" ]]; then
  echo "Refusing unsafe DERIVED_DATA target: ${DERIVED_DATA}" >&2
  exit 1
fi

if [[ "${REQUIRE_SIGNING}" == "1" && -z "${CODESIGN_IDENTITY:-}" ]]; then
  echo "CODESIGN_IDENTITY is required for this release build." >&2
  exit 1
fi

if [[ "${REQUIRE_NOTARIZATION}" == "1" ]] &&
   [[ -z "${NOTARY_KEYCHAIN_PROFILE:-}" ]] &&
   [[ -z "${NOTARYTOOL_KEY_PATH:-}" || -z "${NOTARYTOOL_KEY_ID:-}" || -z "${NOTARYTOOL_ISSUER_ID:-}" ]]; then
  echo "Notarization credentials are required for this release build." >&2
  exit 1
fi

if [[ ! -f "$LICENSE_SOURCE" || -L "$LICENSE_SOURCE" || ! -s "$LICENSE_SOURCE" ]]; then
  echo "Required project license is missing or unsafe: ${LICENSE_SOURCE}" >&2
  exit 1
fi

XCODEBUILD_ARGS=(
  -project "${PROJECT_PATH}"
  -scheme "${SCHEME}"
  -configuration "${CONFIGURATION}"
  -destination "generic/platform=macOS"
  -derivedDataPath "${DERIVED_DATA}"
)

if [[ -n "$CLONED_SOURCE_PACKAGES_DIR" ]]; then
  if [[ ! -d "$CLONED_SOURCE_PACKAGES_DIR" ]]; then
    echo "CLONED_SOURCE_PACKAGES_DIR is not a directory: $CLONED_SOURCE_PACKAGES_DIR" >&2
    exit 1
  fi
  PACKAGE_CACHE_ARGS+=(
    "-clonedSourcePackagesDirPath" "$CLONED_SOURCE_PACKAGES_DIR"
    "-disableAutomaticPackageResolution"
  )
  XCODEBUILD_ARGS+=("${PACKAGE_CACHE_ARGS[@]}")
fi

echo "Building ${APP_NAME} (${CONFIGURATION})..."
rm -rf "${DERIVED_DATA}"
xcodebuild \
  "${XCODEBUILD_ARGS[@]}" \
  CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-YES}" \
  clean build

APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
if [[ ! -d "${APP_PATH}" ]]; then
  echo "App not found at ${APP_PATH}"
  exit 1
fi

BUNDLED_RESOURCES="${APP_PATH}/Contents/Resources"
BUNDLED_LICENSE="${BUNDLED_RESOURCES}/LICENSE"
BUNDLED_THIRD_PARTY_NOTICES="${BUNDLED_RESOURCES}/ThirdPartyNotices.md"
if [[ ! -d "$BUNDLED_RESOURCES" || -L "$BUNDLED_RESOURCES" ]]; then
  echo "Built app has an unsafe Resources directory: ${BUNDLED_RESOURCES}" >&2
  exit 1
fi
if [[ -L "$BUNDLED_LICENSE" || ( -e "$BUNDLED_LICENSE" && ! -f "$BUNDLED_LICENSE" ) ]]; then
  echo "Built app has an unsafe project-license destination: ${BUNDLED_LICENSE}" >&2
  exit 1
fi
cp "$LICENSE_SOURCE" "$BUNDLED_LICENSE"
chmod 0644 "$BUNDLED_LICENSE"
if [[ ! -f "$BUNDLED_LICENSE" || -L "$BUNDLED_LICENSE" || ! -s "$BUNDLED_LICENSE" ]] ||
   ! cmp -s "$LICENSE_SOURCE" "$BUNDLED_LICENSE"; then
  echo "Built app project license does not match the reviewed source license." >&2
  exit 1
fi
if [[ ! -f "$THIRD_PARTY_NOTICES_SOURCE" || -L "$THIRD_PARTY_NOTICES_SOURCE" || ! -s "$THIRD_PARTY_NOTICES_SOURCE" ]]; then
  echo "Required source third-party notices are missing or unsafe: ${THIRD_PARTY_NOTICES_SOURCE}" >&2
  exit 1
fi
if [[ ! -f "$BUNDLED_THIRD_PARTY_NOTICES" || -L "$BUNDLED_THIRD_PARTY_NOTICES" || ! -s "$BUNDLED_THIRD_PARTY_NOTICES" ]]; then
  echo "Built app is missing its bundled third-party notices: ${BUNDLED_THIRD_PARTY_NOTICES}" >&2
  exit 1
fi
if ! cmp -s "$THIRD_PARTY_NOTICES_SOURCE" "$BUNDLED_THIRD_PARTY_NOTICES"; then
  echo "Bundled third-party notices do not match the reviewed source notice." >&2
  exit 1
fi

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  echo "Code signing with identity: ${CODESIGN_IDENTITY}"
  codesign --force --options runtime --deep --timestamp --sign "${CODESIGN_IDENTITY}" "${APP_PATH}"
  codesign --verify --deep --strict "${APP_PATH}"
else
  echo "CODESIGN_IDENTITY not set; skipping codesign."
fi

mkdir -p "${OUTPUT_DIR}"
DMG_NAME="${APP_NAME}-${DMG_VERSION}.dmg"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"

DMG_STAGE="${DERIVED_DATA}/dmg"
rm -rf "${DMG_STAGE}"
mkdir -p "${DMG_STAGE}"
cp -R "${APP_PATH}" "${DMG_STAGE}/"
cp "${LICENSE_SOURCE}" "${DMG_STAGE}/LICENSE"
cp "${THIRD_PARTY_NOTICES_SOURCE}" "${DMG_STAGE}/ThirdPartyNotices.md"
ln -s /Applications "${DMG_STAGE}/Applications"

echo "Creating DMG: ${DMG_PATH}"
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${DMG_STAGE}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

if [[ "${REQUIRE_NOTARIZATION}" != "1" ]]; then
  echo "Notarization disabled for this build; skipping submission."
elif [[ -n "${NOTARYTOOL_KEY_PATH:-}" && -n "${NOTARYTOOL_KEY_ID:-}" && -n "${NOTARYTOOL_ISSUER_ID:-}" ]]; then
  echo "Submitting DMG for notarization with App Store Connect API key..."
  xcrun notarytool submit "${DMG_PATH}" \
    --key "${NOTARYTOOL_KEY_PATH}" \
    --key-id "${NOTARYTOOL_KEY_ID}" \
    --issuer "${NOTARYTOOL_ISSUER_ID}" \
    --wait
  xcrun stapler staple "${DMG_PATH}"
  xcrun stapler validate "${DMG_PATH}"
elif [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  echo "Submitting DMG for notarization with stored keychain profile..."
  xcrun notarytool submit "${DMG_PATH}" \
    --keychain-profile "${NOTARY_KEYCHAIN_PROFILE}" \
    --wait
  xcrun stapler staple "${DMG_PATH}"
  xcrun stapler validate "${DMG_PATH}"
else
  echo "Notarization was required but no supported credentials were available." >&2
  exit 1
fi

echo "Verifying DMG image..."
hdiutil verify "${DMG_PATH}"

echo "Computing SHA-256 checksum..."
(
  cd "${OUTPUT_DIR}"
  shasum -a 256 "${DMG_NAME}" > "${DMG_NAME}.sha256"
)
CHECKSUM_VALUE="$(awk '{print $1}' "${DMG_PATH}.sha256")"
DMG_SIZE_BYTES="$(stat -f%z "${DMG_PATH}")"

echo "DMG ready: ${DMG_PATH}"
echo "Checksum ready: ${DMG_PATH}.sha256"
echo "SHA-256: ${CHECKSUM_VALUE}"
echo "Size bytes: ${DMG_SIZE_BYTES}"
