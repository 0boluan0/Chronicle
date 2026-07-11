#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/Chronicle.xcodeproj"
SCHEME="Chronicle"
CONFIGURATION="Release"
DERIVED_DATA="${ROOT_DIR}/build/dmg-release"
OUTPUT_DIR="${ROOT_DIR}/dist"
DMG_VERSION="${DMG_VERSION:-dev}"
APP_NAME="Chronicle"
REQUIRE_SIGNING="${REQUIRE_SIGNING:-0}"
REQUIRE_NOTARIZATION="${REQUIRE_NOTARIZATION:-0}"

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

echo "Building ${APP_NAME} (${CONFIGURATION})..."
rm -rf "${DERIVED_DATA}"
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "generic/platform=macOS" \
  -derivedDataPath "${DERIVED_DATA}" \
  clean build

APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
if [[ ! -d "${APP_PATH}" ]]; then
  echo "App not found at ${APP_PATH}"
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
ln -s /Applications "${DMG_STAGE}/Applications"

echo "Creating DMG: ${DMG_PATH}"
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${DMG_STAGE}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

if [[ -n "${NOTARYTOOL_KEY_PATH:-}" && -n "${NOTARYTOOL_KEY_ID:-}" && -n "${NOTARYTOOL_ISSUER_ID:-}" ]]; then
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
  echo "Notarization credentials not set; keeping development/notarization-free DMG path."
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
