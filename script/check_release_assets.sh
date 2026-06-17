#!/usr/bin/env bash
set -euo pipefail

REPO="${RELEASE_REPO:-${GITHUB_REPOSITORY:-0boluan0/Chronicle}}"
TAG="${1:-}"

usage() {
  echo "Usage: $0 <release-tag>" >&2
  echo "Example: $0 v0.1.0-rc1" >&2
}

if [[ -z "$TAG" ]]; then
  usage
  exit 64
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required. Install and authenticate gh, then rerun this check." >&2
  exit 127
fi

gh_retry() {
  local attempt=1
  local max_attempts=3
  local status=0

  while true; do
    if gh "$@"; then
      return 0
    fi

    status=$?
    if [[ "$attempt" -ge "$max_attempts" ]]; then
      return "$status"
    fi

    echo "gh $* failed (attempt ${attempt}/${max_attempts}); retrying..." >&2
    attempt=$((attempt + 1))
    sleep 2
  done
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

RELEASE_JSON="${TMP_DIR}/release.json"
echo "Checking GitHub release: ${REPO} ${TAG}"
gh_retry release view "$TAG" \
  --repo "$REPO" \
  --json tagName,isDraft,isPrerelease,publishedAt,name,assets,url \
  > "$RELEASE_JSON"

echo "Reading release asset metadata..."
RELEASE_INFO="$(
  ruby -rjson -e '
    data = JSON.parse(File.read(ARGV.fetch(0)))
    assets = data.fetch("assets", [])
    dmg_assets = assets.select { |asset| asset.fetch("name", "").end_with?(".dmg") }
    abort("Expected exactly one .dmg asset, found #{dmg_assets.length}") unless dmg_assets.length == 1

    dmg = dmg_assets.fetch(0)
    checksum_name = "#{dmg.fetch("name")}.sha256"
    checksum = assets.find { |asset| asset.fetch("name", "") == checksum_name }
    abort("Missing checksum asset: #{checksum_name}") unless checksum

    digest = dmg.fetch("digest", "").sub(/\Asha256:/, "").downcase
    abort("DMG asset is missing a sha256 digest") if digest.empty?

    puts data.fetch("tagName")
    puts data.fetch("url")
    puts dmg.fetch("name")
    puts dmg.fetch("size")
    puts digest
    puts checksum.fetch("name")
  ' "$RELEASE_JSON"
)"

TAG_NAME="$(printf '%s\n' "$RELEASE_INFO" | sed -n '1p')"
RELEASE_URL="$(printf '%s\n' "$RELEASE_INFO" | sed -n '2p')"
DMG_NAME="$(printf '%s\n' "$RELEASE_INFO" | sed -n '3p')"
DMG_SIZE="$(printf '%s\n' "$RELEASE_INFO" | sed -n '4p')"
ASSET_DIGEST="$(printf '%s\n' "$RELEASE_INFO" | sed -n '5p')"
CHECKSUM_NAME="$(printf '%s\n' "$RELEASE_INFO" | sed -n '6p')"

if [[ "$TAG_NAME" != "$TAG" ]]; then
  echo "Release tag mismatch: requested ${TAG}, got ${TAG_NAME}" >&2
  exit 1
fi

if ! [[ "$DMG_SIZE" =~ ^[0-9]+$ ]] || [[ "$DMG_SIZE" -le 0 ]]; then
  echo "DMG asset has invalid size: ${DMG_SIZE:-<empty>}" >&2
  exit 1
fi

echo "Downloading checksum asset: ${CHECKSUM_NAME}"
gh_retry release download "$TAG" \
  --repo "$REPO" \
  --pattern "$CHECKSUM_NAME" \
  --dir "$TMP_DIR" \
  --clobber \
  >/dev/null

CHECKSUM_FILE="${TMP_DIR}/${CHECKSUM_NAME}"
if [[ ! -f "$CHECKSUM_FILE" ]]; then
  echo "Checksum download failed: ${CHECKSUM_NAME}" >&2
  exit 1
fi

PUBLISHED_CHECKSUM="$(awk 'NF { print tolower($1); exit }' "$CHECKSUM_FILE")"
PUBLISHED_FILE="$(awk 'NF { print $2; exit }' "$CHECKSUM_FILE")"

if [[ -z "$PUBLISHED_CHECKSUM" ]]; then
  echo "Checksum file is empty: ${CHECKSUM_NAME}" >&2
  exit 1
fi

if [[ "$PUBLISHED_CHECKSUM" != "$ASSET_DIGEST" ]]; then
  echo "Checksum mismatch for ${DMG_NAME}" >&2
  echo "GitHub asset digest: ${ASSET_DIGEST}" >&2
  echo "Published .sha256:    ${PUBLISHED_CHECKSUM}" >&2
  exit 1
fi

if [[ "$PUBLISHED_FILE" != "$DMG_NAME" ]]; then
  echo "Checksum file names ${PUBLISHED_FILE:-<empty>} but expected ${DMG_NAME}" >&2
  exit 1
fi

echo "Release asset check passed."
echo "Repo: ${REPO}"
echo "Tag: ${TAG_NAME}"
echo "URL: ${RELEASE_URL}"
echo "DMG: ${DMG_NAME}"
echo "Size bytes: ${DMG_SIZE}"
echo "SHA-256: ${ASSET_DIGEST}"
echo "Checksum asset: ${CHECKSUM_NAME}"
