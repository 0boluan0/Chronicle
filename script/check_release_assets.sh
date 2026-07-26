#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${RELEASE_REPO:-${GITHUB_REPOSITORY:-0boluan0/Chronicle}}"
TAG="${1:-}"
EXPECTED_STATE="${2:-published}"
EXPECTED_LATEST="${3:-ignore}"
EXPECTED_RELEASE_ID="${4:-}"
BINDING_MANIFEST="${5:-}"
VERIFICATION_MODE="${6:-auto}"
EXPECTED_SOURCE_COMMIT="${7:-}"
EXPECTED_STAGING_REPOSITORY="${8:-}"
EXPECTED_STAGING_RUN_ID="${9:-}"
EXPECTED_STAGING_RUN_ATTEMPT="${10:-}"
EXPECTED_STAGING_HEAD_SHA="${11:-}"
EXPECTED_STAGING_WORKFLOW_REF="${12:-}"
EXPECTED_STAGING_WORKFLOW_SHA="${13:-}"

usage() {
  echo "Usage: $0 <release-tag> [draft|published] [latest|ignore] [release-id] [binding-manifest] [gate|observe] [source-commit] [staging-repository] [staging-run-id] [staging-run-attempt] [staging-head-sha] [staging-workflow-ref] [staging-workflow-sha]" >&2
  echo "Gate example: $0 v1.1.0 published latest 123456789 /tmp/release-binding.json gate 0123456789abcdef0123456789abcdef01234567 owner/repo 987654321 1 fedcba9876543210fedcba9876543210fedcba98 owner/repo/.github/workflows/release.yml@refs/heads/main fedcba9876543210fedcba9876543210fedcba98" >&2
  echo "Observation example: $0 v1.1.0 published latest '' '' observe" >&2
}

if [[ -z "$TAG" ]]; then
  usage
  exit 64
fi

case "$EXPECTED_STATE" in
  draft|published)
    ;;
  *)
    usage
    echo "Expected release state must be draft or published, got: $EXPECTED_STATE" >&2
    exit 64
    ;;
esac

case "$EXPECTED_LATEST" in
  latest|ignore)
    ;;
  *)
    usage
    echo "Latest-release expectation must be latest or ignore, got: $EXPECTED_LATEST" >&2
    exit 64
    ;;
esac

if [[ "$EXPECTED_STATE" == "draft" && "$EXPECTED_LATEST" == "latest" ]]; then
  echo "A Draft release cannot be expected to be latest." >&2
  exit 64
fi

if [[ -n "$EXPECTED_RELEASE_ID" ]] && ! [[ "$EXPECTED_RELEASE_ID" =~ ^[1-9][0-9]*$ ]]; then
  echo "Expected release ID must be numeric, got: $EXPECTED_RELEASE_ID" >&2
  exit 64
fi

if [[ -n "$BINDING_MANIFEST" ]]; then
  if [[ -z "$EXPECTED_RELEASE_ID" ]]; then
    echo "A binding manifest requires an exact release ID." >&2
    exit 64
  fi
  if [[ ! -f "$BINDING_MANIFEST" || -L "$BINDING_MANIFEST" ]]; then
    echo "Binding manifest must be a non-symlink regular file: $BINDING_MANIFEST" >&2
    exit 64
  fi
fi

if [[ -n "$EXPECTED_SOURCE_COMMIT" ]] && ! [[ "$EXPECTED_SOURCE_COMMIT" =~ ^[0-9a-f]{40,64}$ ]]; then
  echo "Expected source commit must be a full lowercase Git object ID, got: $EXPECTED_SOURCE_COMMIT" >&2
  exit 64
fi

case "$VERIFICATION_MODE" in
  auto)
    if [[ -n "$EXPECTED_RELEASE_ID" || -n "$BINDING_MANIFEST" || -n "$EXPECTED_SOURCE_COMMIT" ||
          -n "$EXPECTED_STAGING_REPOSITORY" || -n "$EXPECTED_STAGING_RUN_ID" ||
          -n "$EXPECTED_STAGING_RUN_ATTEMPT" || -n "$EXPECTED_STAGING_HEAD_SHA" ||
          -n "$EXPECTED_STAGING_WORKFLOW_REF" || -n "$EXPECTED_STAGING_WORKFLOW_SHA" ]]; then
      VERIFICATION_MODE="gate"
    else
      VERIFICATION_MODE="observe"
    fi
    ;;
  gate|observe)
    ;;
  *)
    usage
    echo "Verification mode must be gate or observe, got: $VERIFICATION_MODE" >&2
    exit 64
    ;;
esac

if [[ "$VERIFICATION_MODE" == "gate" ]]; then
  if [[ -z "$EXPECTED_RELEASE_ID" || -z "$BINDING_MANIFEST" || -z "$EXPECTED_SOURCE_COMMIT" ||
        -z "$EXPECTED_STAGING_REPOSITORY" || -z "$EXPECTED_STAGING_RUN_ID" ||
        -z "$EXPECTED_STAGING_RUN_ATTEMPT" || -z "$EXPECTED_STAGING_HEAD_SHA" ||
        -z "$EXPECTED_STAGING_WORKFLOW_REF" || -z "$EXPECTED_STAGING_WORKFLOW_SHA" ]]; then
    echo "Gate verification requires an exact release ID, binding manifest, source commit, and all six staging provenance expectations." >&2
    exit 64
  fi
  [[ "$EXPECTED_STAGING_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
    echo "Expected staging repository must be owner/name." >&2
    exit 64
  }
  [[ "$EXPECTED_STAGING_RUN_ID" =~ ^[1-9][0-9]*$ && "$EXPECTED_STAGING_RUN_ATTEMPT" =~ ^[1-9][0-9]*$ ]] || {
    echo "Expected staging run ID and attempt must be positive integers." >&2
    exit 64
  }
  [[ "$EXPECTED_STAGING_HEAD_SHA" =~ ^[0-9a-f]{40,64}$ && "$EXPECTED_STAGING_WORKFLOW_SHA" =~ ^[0-9a-f]{40,64}$ ]] || {
    echo "Expected staging head and workflow SHAs must be full lowercase Git object IDs." >&2
    exit 64
  }
  [[ -n "$EXPECTED_STAGING_WORKFLOW_REF" && "$EXPECTED_STAGING_WORKFLOW_REF" != *$'\n'* && "$EXPECTED_STAGING_WORKFLOW_REF" != *$'\r'* ]] || {
    echo "Expected staging workflow ref must be a non-empty single line." >&2
    exit 64
  }
else
  if [[ -n "$BINDING_MANIFEST" || -n "$EXPECTED_SOURCE_COMMIT" || -n "$EXPECTED_STAGING_REPOSITORY" ||
        -n "$EXPECTED_STAGING_RUN_ID" || -n "$EXPECTED_STAGING_RUN_ATTEMPT" ||
        -n "$EXPECTED_STAGING_HEAD_SHA" || -n "$EXPECTED_STAGING_WORKFLOW_REF" ||
        -n "$EXPECTED_STAGING_WORKFLOW_SHA" ]]; then
    echo "Observe mode must not accept binding or staging provenance evidence; use gate mode for bound evidence." >&2
    exit 64
  fi
  cat >&2 <<EOF
NON-GATE OBSERVATION: validating only the release state currently visible on GitHub.
This mode does not bind the release body or asset IDs to the workflow upload and cannot satisfy a publication gate.
EOF
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required. Install and authenticate gh, then rerun this check." >&2
  exit 127
fi

gh_retry() {
  local attempt=1
  local max_attempts=3
  local status=0
  local retry_output

  retry_output="$(mktemp "${TMP_DIR}/gh-retry.XXXXXX")"

  while true; do
    if gh "$@" > "$retry_output"; then
      command cat "$retry_output"
      rm -f "$retry_output"
      return 0
    else
      status=$?
    fi

    if [[ "$attempt" -ge "$max_attempts" ]]; then
      command cat "$retry_output" >&2
      rm -f "$retry_output"
      return "$status"
    fi

    echo "gh $* failed (attempt ${attempt}/${max_attempts}); retrying..." >&2
    attempt=$((attempt + 1))
    : > "$retry_output"
    sleep 2
  done
}

EXPECTED_PRERELEASE="false"
if [[ "$TAG" == *-* ]]; then
  EXPECTED_PRERELEASE="true"
fi
EXPECTED_DMG="Chronicle-${TAG}.dmg"
EXPECTED_CHECKSUM="${EXPECTED_DMG}.sha256"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

RELEASE_JSON="${TMP_DIR}/releases.json"
EXACT_RELEASE_JSON=""
REMOTE_SOURCE_COMMIT="<not-checked>"
echo "Checking GitHub release: ${REPO} ${TAG} (${EXPECTED_STATE}, ${VERIFICATION_MODE})"
gh_retry api \
  --paginate \
  --slurp \
  "repos/${REPO}/releases?per_page=100" \
  > "$RELEASE_JSON"

if [[ "$VERIFICATION_MODE" == "gate" ]]; then
  REMOTE_SOURCE_COMMIT="$(gh_retry api "repos/${REPO}/commits/${TAG}" --jq '.sha')"
  if [[ "$REMOTE_SOURCE_COMMIT" != "$EXPECTED_SOURCE_COMMIT" ]]; then
    echo "Remote tag ${TAG} resolves to ${REMOTE_SOURCE_COMMIT:-<missing>}, expected bound source ${EXPECTED_SOURCE_COMMIT}." >&2
    exit 1
  fi
fi

if [[ -n "$EXPECTED_RELEASE_ID" ]]; then
  EXACT_RELEASE_JSON="${TMP_DIR}/release-${EXPECTED_RELEASE_ID}.json"
  echo "Binding validation to GitHub release ID: ${EXPECTED_RELEASE_ID}"
  gh_retry api \
    "repos/${REPO}/releases/${EXPECTED_RELEASE_ID}" \
    > "$EXACT_RELEASE_JSON"
fi

echo "Validating release state, channel, and exact asset set..."
RELEASE_INFO="$(
  ruby -rjson -e '
    pages = JSON.parse(File.read(ARGV.fetch(0)))
    tag = ARGV.fetch(1)
    expected_state = ARGV.fetch(2)
    expected_prerelease = ARGV.fetch(3) == "true"
    expected_dmg = ARGV.fetch(4)
    expected_checksum = ARGV.fetch(5)
    expected_release_id = ARGV.fetch(6)
    exact_release_path = ARGV.fetch(7)

    releases = pages.flatten
    matches = releases.select { |release| release["tag_name"] == tag }
    abort("Expected exactly one release record for #{tag}, found #{matches.length}") unless matches.length == 1
    data = matches.fetch(0)

    unless expected_release_id.empty?
      release_id = Integer(expected_release_id, 10)
      abort("Tag #{tag} now resolves to release ID #{data["id"].inspect}, expected #{release_id}") unless data["id"] == release_id
      exact_data = JSON.parse(File.read(exact_release_path))
      abort("Exact release endpoint returned ID #{exact_data["id"].inspect}, expected #{release_id}") unless exact_data["id"] == release_id
      abort("Exact release ID #{release_id} now has tag #{exact_data["tag_name"].inspect}, expected #{tag}") unless exact_data["tag_name"] == tag
      data = exact_data
    end

    abort("Release tag mismatch: requested #{tag}, got #{data["tag_name"].inspect}") unless data["tag_name"] == tag
    abort("Release name must exactly match #{tag}") unless data["name"] == tag

    expected_draft = expected_state == "draft"
    abort("Release draft state mismatch: expected #{expected_draft}, got #{data["draft"].inspect}") unless data["draft"] == expected_draft
    abort("Release prerelease channel mismatch: expected #{expected_prerelease}, got #{data["prerelease"].inspect}") unless data["prerelease"] == expected_prerelease

    published_at = data["published_at"].to_s.strip
    if expected_draft
      abort("Draft release unexpectedly has publishedAt=#{published_at}") unless published_at.empty?
    else
      abort("Published release is missing publishedAt") if published_at.empty?
    end

    assets = data.fetch("assets", [])
    actual_names = assets.map { |asset| asset.fetch("name", "") }
    expected_names = [expected_dmg, expected_checksum]
    unless actual_names.sort == expected_names.sort && actual_names.uniq.length == actual_names.length
      abort("Release assets must be exactly #{expected_names.inspect}; got #{actual_names.inspect}")
    end

    assets.each do |asset|
      name = asset.fetch("name", "")
      size = asset.fetch("size", 0)
      state = asset.fetch("state", "")
      abort("Asset #{name} has invalid size: #{size.inspect}") unless size.is_a?(Integer) && size.positive?
      abort("Asset #{name} is not uploaded: #{state.inspect}") unless state == "uploaded"
    end

    dmg = assets.find { |asset| asset["name"] == expected_dmg }
    checksum = assets.find { |asset| asset["name"] == expected_checksum }
    digest = dmg.fetch("digest", "").sub(/\Asha256:/, "").downcase
    checksum_digest = checksum.fetch("digest", "").sub(/\Asha256:/, "").downcase
    abort("DMG asset is missing a valid sha256 digest") unless digest.match?(/\A[0-9a-f]{64}\z/)
    abort("Checksum asset is missing a valid sha256 digest") unless checksum_digest.match?(/\A[0-9a-f]{64}\z/)

    puts data.fetch("html_url")
    puts dmg.fetch("name")
    puts dmg.fetch("size")
    puts digest
    puts checksum.fetch("name")
    puts checksum.fetch("size")
    puts checksum_digest
    puts checksum.fetch("id")
    puts data.fetch("id")
  ' "$RELEASE_JSON" "$TAG" "$EXPECTED_STATE" "$EXPECTED_PRERELEASE" "$EXPECTED_DMG" "$EXPECTED_CHECKSUM" "$EXPECTED_RELEASE_ID" "$EXACT_RELEASE_JSON"
)"

if [[ -n "$BINDING_MANIFEST" ]]; then
  ruby "$SCRIPT_DIR/support/release_binding_manifest.rb" verify \
    "$BINDING_MANIFEST" \
    "$EXACT_RELEASE_JSON" \
    "$TAG" \
    "$EXPECTED_RELEASE_ID" \
    "$EXPECTED_SOURCE_COMMIT" \
    "$EXPECTED_DMG" \
    "$EXPECTED_CHECKSUM" \
    "$EXPECTED_STAGING_REPOSITORY" \
    "$EXPECTED_STAGING_RUN_ID" \
    "$EXPECTED_STAGING_RUN_ATTEMPT" \
    "$EXPECTED_STAGING_HEAD_SHA" \
    "$EXPECTED_STAGING_WORKFLOW_REF" \
    "$EXPECTED_STAGING_WORKFLOW_SHA"
fi

RELEASE_URL="$(printf '%s\n' "$RELEASE_INFO" | sed -n '1p')"
DMG_NAME="$(printf '%s\n' "$RELEASE_INFO" | sed -n '2p')"
DMG_SIZE="$(printf '%s\n' "$RELEASE_INFO" | sed -n '3p')"
ASSET_DIGEST="$(printf '%s\n' "$RELEASE_INFO" | sed -n '4p')"
CHECKSUM_NAME="$(printf '%s\n' "$RELEASE_INFO" | sed -n '5p')"
CHECKSUM_SIZE="$(printf '%s\n' "$RELEASE_INFO" | sed -n '6p')"
CHECKSUM_ASSET_DIGEST="$(printf '%s\n' "$RELEASE_INFO" | sed -n '7p')"
CHECKSUM_ASSET_ID="$(printf '%s\n' "$RELEASE_INFO" | sed -n '8p')"
ACTUAL_RELEASE_ID="$(printf '%s\n' "$RELEASE_INFO" | sed -n '9p')"
CHECKSUM_FILE="${TMP_DIR}/${CHECKSUM_NAME}"

if ! [[ "$ACTUAL_RELEASE_ID" =~ ^[1-9][0-9]*$ ]]; then
  echo "Release has an invalid GitHub ID: ${ACTUAL_RELEASE_ID:-<empty>}" >&2
  exit 1
fi

if ! [[ "$CHECKSUM_ASSET_ID" =~ ^[1-9][0-9]*$ ]]; then
  echo "Checksum asset has an invalid GitHub ID: ${CHECKSUM_ASSET_ID:-<empty>}" >&2
  exit 1
fi

echo "Downloading checksum asset: ${CHECKSUM_NAME}"
gh_retry api \
  --header "Accept: application/octet-stream" \
  "repos/${REPO}/releases/assets/${CHECKSUM_ASSET_ID}" \
  > "$CHECKSUM_FILE"

if [[ ! -f "$CHECKSUM_FILE" ]]; then
  echo "Checksum download failed: ${CHECKSUM_NAME}" >&2
  exit 1
fi

CHECKSUM_CONTENT="$(
  ruby -e '
    content = File.binread(ARGV.fetch(0))
    match = content.match(/\A([0-9A-Fa-f]{64})[ \t]+([^\r\n]+)\r?\n?\z/)
    abort("Checksum asset must contain exactly one SHA-256 and filename line") unless match
    puts match[1].downcase
    puts match[2]
  ' "$CHECKSUM_FILE"
)"
PUBLISHED_CHECKSUM="$(printf '%s\n' "$CHECKSUM_CONTENT" | sed -n '1p')"
PUBLISHED_FILE="$(printf '%s\n' "$CHECKSUM_CONTENT" | sed -n '2p')"

if ! [[ "$PUBLISHED_CHECKSUM" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Checksum file does not contain a valid SHA-256 digest: ${CHECKSUM_NAME}" >&2
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

DOWNLOADED_CHECKSUM_DIGEST="$(shasum -a 256 "$CHECKSUM_FILE" | awk '{print tolower($1)}')"
if [[ "$DOWNLOADED_CHECKSUM_DIGEST" != "$CHECKSUM_ASSET_DIGEST" ]]; then
  echo "Downloaded checksum asset digest does not match GitHub metadata for ${CHECKSUM_NAME}" >&2
  echo "GitHub asset digest: ${CHECKSUM_ASSET_DIGEST}" >&2
  echo "Downloaded digest:   ${DOWNLOADED_CHECKSUM_DIGEST}" >&2
  exit 1
fi

LATEST_TAG="<not-checked>"
if [[ "$EXPECTED_STATE" == "published" && "$EXPECTED_LATEST" == "latest" ]]; then
  LATEST_TAG="$(gh_retry api "repos/${REPO}/releases/latest" --jq '.tag_name')"
  if [[ "$EXPECTED_PRERELEASE" == "true" ]]; then
    echo "A prerelease cannot satisfy the latest-stable expectation: ${TAG}" >&2
    exit 1
  fi
  if [[ "$LATEST_TAG" != "$TAG" ]]; then
    echo "Stable release ${TAG} must be latest, but GitHub reports ${LATEST_TAG:-<empty>}." >&2
    exit 1
  fi
fi

if [[ "$VERIFICATION_MODE" == "gate" ]]; then
  echo "GATE release asset verification passed."
  echo "Gate-qualified: yes"
else
  echo "NON-GATE release observation completed."
  echo "Gate-qualified: no"
fi
echo "Verification mode: ${VERIFICATION_MODE}"
echo "Repo: ${REPO}"
echo "Tag: ${TAG}"
echo "Release ID: ${ACTUAL_RELEASE_ID}"
echo "Source commit: ${REMOTE_SOURCE_COMMIT}"
echo "State: ${EXPECTED_STATE}"
echo "Prerelease: ${EXPECTED_PRERELEASE}"
echo "Latest stable tag: ${LATEST_TAG}"
echo "URL: ${RELEASE_URL}"
echo "DMG: ${DMG_NAME}"
echo "Size bytes: ${DMG_SIZE}"
echo "SHA-256: ${ASSET_DIGEST}"
echo "Checksum asset: ${CHECKSUM_NAME}"
echo "Checksum size bytes: ${CHECKSUM_SIZE}"
echo "Checksum SHA-256: ${CHECKSUM_ASSET_DIGEST}"
