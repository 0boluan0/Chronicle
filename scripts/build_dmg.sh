#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/Chronicle.xcodeproj"
SCHEME="Chronicle"
CONFIGURATION="Release"
DERIVED_DATA="${ROOT_DIR}/build"
OUTPUT_DIR="${ROOT_DIR}/dist"
DMG_VERSION="${DMG_VERSION:-dev}"
APP_NAME="Chronicle"

echo "Building ${APP_NAME} (${CONFIGURATION})..."
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "platform=macOS" \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO \
  build

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

echo "DMG ready: ${DMG_PATH}"
