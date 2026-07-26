#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "time"
require_relative "release_candidate_manifest"

SHA256_PATTERN = /\A[0-9a-f]{64}\z/
OID_PATTERN = /\A[0-9a-f]{40,64}\z/
REPOSITORY_PATTERN = /\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\z/
PREVIOUS_TAG = "v1.0.5"
MAX_CLOCK_SKEW_SECONDS = 300
MAX_ATTESTATION_LIFETIME_SECONDS = 24 * 60 * 60
REQUIRED_CHECKS = %w[
  upgrade relaunch preferences bookmark export rollback permission uninstall
].freeze

def fail_attestation(message)
  warn "clean-account release attestation: #{message}"
  exit 1
end

def safe_file(path, label, exact_size: nil)
  stat = File.lstat(path)
  valid_size = exact_size ? stat.size == exact_size : stat.size.positive?
  unless stat.file? && !stat.symlink? && valid_size
    size_requirement = exact_size ? "exactly #{exact_size} bytes" : "non-empty"
    fail_attestation("#{label} must be a #{size_requirement}, non-symlink regular file: #{path}")
  end
  path
rescue SystemCallError => error
  fail_attestation("#{label} is unavailable: #{path} (#{error.class})")
end

def json_object_with_bytes(path, label)
  bytes = File.binread(safe_file(path, label))
  value = JSON.parse(bytes)
  fail_attestation("#{label} must contain one JSON object") unless value.is_a?(Hash)
  [value, bytes]
rescue JSON::ParserError => error
  fail_attestation("#{label} is invalid JSON: #{error.message}")
end

def json_object(path, label)
  json_object_with_bytes(path, label).first
end

def object(value, label)
  fail_attestation("#{label} must be an object") unless value.is_a?(Hash)
  value
end

def exact_keys(value, keys, label)
  actual = value.keys.sort
  expected = keys.sort
  return if actual == expected

  fail_attestation("#{label} keys must be exactly #{expected.inspect}; got #{actual.inspect}")
end

def string(value, label)
  unless value.is_a?(String) && !value.strip.empty? && !value.match?(/[\r\n]/)
    fail_attestation("#{label} must be a non-empty single-line string")
  end
  value
end

def positive_integer(value, label)
  fail_attestation("#{label} must be a positive JSON integer") unless value.is_a?(Integer) && value.positive?
  value
end

def argument_positive_integer(value, label)
  integer = Integer(value, 10)
  fail_attestation("#{label} must be a positive integer") unless integer.positive?
  integer
rescue ArgumentError, TypeError
  fail_attestation("#{label} must be a positive integer")
end

def sha256(value, label)
  fail_attestation("#{label} must be a lowercase SHA-256") unless value.is_a?(String) && value.match?(SHA256_PATTERN)
  value
end

def oid(value, label)
  fail_attestation("#{label} must be a full lowercase Git object ID") unless value.is_a?(String) && value.match?(OID_PATTERN)
  value
end

def remote_digest(asset, label)
  digest = asset.fetch("digest", "").to_s.sub(/\Asha256:/i, "").downcase
  sha256(digest, "#{label} digest")
end

def one_asset(release, name, label)
  assets = release["assets"]
  fail_attestation("#{label} assets must be an array") unless assets.is_a?(Array) && assets.all? { |asset| asset.is_a?(Hash) }
  matches = assets.select { |asset| asset["name"] == name }
  fail_attestation("#{label} must contain exactly one #{name} asset") unless matches.length == 1
  matches.fetch(0)
end

def validate_attested_file(attested, expected, label, include_id: false)
  attested = object(attested, label)
  keys = include_id ? %w[id name sha256 size] : %w[name sha256 size]
  exact_keys(attested, keys, label)
  if include_id
    expected_id = positive_integer(expected.fetch("id"), "#{label} expected ID")
    actual_id = positive_integer(attested["id"], "#{label} ID")
    fail_attestation("#{label} ID mismatch") unless actual_id == expected_id
  end
  expected_name = string(expected.fetch("name"), "#{label} expected name")
  expected_size = positive_integer(expected.fetch("size"), "#{label} expected size")
  expected_sha256 = sha256(expected.fetch("sha256"), "#{label} expected SHA-256")
  fail_attestation("#{label} name mismatch") unless string(attested["name"], "#{label} name") == expected_name
  fail_attestation("#{label} size mismatch") unless positive_integer(attested["size"], "#{label} size") == expected_size
  fail_attestation("#{label} SHA-256 mismatch") unless sha256(attested["sha256"], "#{label} SHA-256") == expected_sha256
end

def parse_time(value, label)
  Time.iso8601(string(value, label)).utc
rescue ArgumentError
  fail_attestation("#{label} is not ISO-8601")
end

def canonical_json_value(value)
  case value
  when Hash
    value.keys.sort.to_h { |key| [key, canonical_json_value(value.fetch(key))] }
  when Array
    value.map { |item| canonical_json_value(item) }
  else
    value
  end
end

def verify_ed25519_signature(payload_path, payload_bytes, signature_path, public_key_path)
  safe_file(signature_path, "detached Ed25519 signature", exact_size: 64)
  safe_file(public_key_path, "reviewed clean-account Ed25519 public key")
  openssl = ENV.fetch("OPENSSL_BIN", "openssl")

  key_output, key_error, key_status = Open3.capture3(
    openssl, "pkey", "-pubin", "-in", public_key_path, "-text", "-noout"
  )
  unless key_status.success? && key_output.match?(/ED25519/i)
    fail_attestation("reviewed public key is not a valid Ed25519 public key: #{key_error.strip}")
  end

  _output, error, status = Open3.capture3(
    openssl, "pkeyutl", "-verify", "-pubin", "-inkey", public_key_path,
    "-rawin", "-in", payload_path, "-sigfile", signature_path
  )
  fail_attestation("detached Ed25519 signature verification failed: #{error.strip}") unless status.success?
  fail_attestation("signed payload unexpectedly changed during verification") unless File.binread(payload_path) == payload_bytes
end

begin
unless ARGV.length == 19
  warn "Usage: #{$PROGRAM_NAME} <payload.json> <signature.bin> <public-key.pem> <candidate-manifest.json> <candidate-dir> <previous-release.json> <previous.dmg> <candidate-tag> <candidate-source-commit> <repository> <nonce> <artifact-name> <artifact-id> <artifact-archive-sha256> <run-id> <run-attempt> <head-sha> <workflow-ref> <workflow-sha>"
  exit 64
end

payload_path, signature_path, public_key_path, candidate_manifest_path, candidate_dir,
  previous_path, previous_dmg_path, expected_tag, expected_source_commit, expected_repository,
  expected_nonce, expected_artifact_name, expected_artifact_id_value,
  expected_artifact_archive_sha256, expected_run_id_value, expected_run_attempt_value,
  expected_head_sha, expected_workflow_ref, expected_workflow_sha = ARGV

expected_tag = string(expected_tag, "candidate tag")
expected_source_commit = oid(expected_source_commit, "candidate source commit")
expected_repository = string(expected_repository, "repository")
fail_attestation("repository must be owner/name") unless expected_repository.match?(REPOSITORY_PATTERN)
expected_nonce = string(expected_nonce, "attestation nonce")
expected_artifact_id = argument_positive_integer(expected_artifact_id_value, "candidate Actions artifact ID")
expected_artifact_archive_sha256 = sha256(expected_artifact_archive_sha256, "candidate Actions artifact archive SHA-256")
expected_run_id = argument_positive_integer(expected_run_id_value, "staging run ID")
expected_run_attempt = argument_positive_integer(expected_run_attempt_value, "staging run attempt")
expected_head_sha = oid(expected_head_sha, "staging head SHA")
expected_workflow_ref = string(expected_workflow_ref, "staging workflow ref")
expected_workflow_sha = oid(expected_workflow_sha, "staging workflow SHA")

manifest_absolute = File.expand_path(candidate_manifest_path)
candidate_dir_absolute = File.expand_path(candidate_dir)
unless File.dirname(manifest_absolute) == candidate_dir_absolute && File.basename(manifest_absolute) == ChronicleReleaseCandidateManifest::MANIFEST_BASENAME
  fail_attestation("candidate manifest must be the exact manifest basename inside the candidate directory")
end

provenance = ChronicleReleaseCandidateManifest.expected_provenance(
  repository_value: expected_repository,
  run_id: expected_run_id,
  run_attempt: expected_run_attempt,
  head_sha: expected_head_sha,
  workflow_ref: expected_workflow_ref,
  workflow_sha: expected_workflow_sha
)
candidate = ChronicleReleaseCandidateManifest.verify!(
  manifest_path: candidate_manifest_path,
  payload_dir: candidate_dir,
  artifact_name_value: expected_artifact_name,
  tag: expected_tag,
  source_commit: expected_source_commit,
  provenance: provenance
)
candidate_metadata = candidate.fetch("metadata")
candidate_dmg_name = candidate_metadata.fetch("dmg_name")
candidate_dmg = candidate.fetch("files").fetch(candidate_dmg_name)
candidate_expected_file = {
  "name" => candidate_dmg_name,
  "size" => candidate_dmg.fetch("size"),
  "sha256" => candidate_dmg.fetch("sha256")
}
candidate_manifest_sha256 = candidate.fetch("manifest_sha256")
derived_nonce = "chronicle:#{expected_repository}:#{expected_run_id}:#{expected_run_attempt}:#{expected_artifact_id}:#{expected_artifact_name}:#{candidate_manifest_sha256}"
unless expected_nonce == derived_nonce
  fail_attestation("expected nonce does not match the exact candidate artifact identity")
end

previous_release = json_object(previous_path, "previous release response")
previous_release_id = positive_integer(previous_release["id"], "previous release ID")
fail_attestation("previous release tag must be #{PREVIOUS_TAG}") unless previous_release["tag_name"] == PREVIOUS_TAG
fail_attestation("previous release must be published") unless previous_release["draft"] == false
fail_attestation("previous release is missing published_at") if previous_release["published_at"].to_s.strip.empty?
previous_dmg_name = "Chronicle-#{PREVIOUS_TAG}.dmg"
previous_remote_dmg = one_asset(previous_release, previous_dmg_name, "previous release")
previous_asset_id = positive_integer(previous_remote_dmg["id"], "previous DMG asset ID")
previous_asset_size = positive_integer(previous_remote_dmg["size"], "previous DMG asset size")
fail_attestation("previous DMG asset is incomplete") unless previous_remote_dmg["state"] == "uploaded"
safe_file(previous_dmg_path, "downloaded previous DMG")
fail_attestation("downloaded previous DMG size mismatch") unless File.size(previous_dmg_path) == previous_asset_size
previous_dmg_sha256 = Digest::SHA256.file(previous_dmg_path).hexdigest
remote_previous_digest = previous_remote_dmg.fetch("digest", "").to_s
unless remote_previous_digest.empty?
  fail_attestation("downloaded previous DMG digest mismatch") unless remote_digest(previous_remote_dmg, "previous DMG") == previous_dmg_sha256
end
previous_expected_file = {
  "id" => previous_asset_id,
  "name" => previous_dmg_name,
  "size" => previous_asset_size,
  "sha256" => previous_dmg_sha256
}

attestation, payload_bytes = json_object_with_bytes(payload_path, "clean-account signed payload")
canonical_bytes = JSON.generate(canonical_json_value(attestation)) << "\n"
fail_attestation("signed payload is not canonical compact JSON with one trailing LF") unless payload_bytes == canonical_bytes
verify_ed25519_signature(payload_path, payload_bytes, signature_path, public_key_path)

exact_keys(attestation, %w[attestation_type candidate checks environment expires_at issued_at nonce pass previous_release repository schema_version status], "clean-account signed payload")
fail_attestation("unsupported attestation schema") unless attestation["schema_version"] == 3
fail_attestation("unexpected attestation_type") unless attestation["attestation_type"] == "chronicle_clean_account_release_gate"
fail_attestation("attestation status is not passed") unless attestation["status"] == "passed"
fail_attestation("attestation pass flag is not true") unless attestation["pass"] == true
fail_attestation("attestation repository mismatch") unless attestation["repository"] == expected_repository
fail_attestation("attestation nonce mismatch") unless attestation["nonce"] == expected_nonce

issued_at = parse_time(attestation["issued_at"], "issued_at")
expires_at = parse_time(attestation["expires_at"], "expires_at")
now = Time.now.utc
fail_attestation("issued_at is too far in the future") if issued_at > now + MAX_CLOCK_SKEW_SECONDS
fail_attestation("attestation has expired") unless expires_at > now
fail_attestation("expires_at must be later than issued_at") unless expires_at > issued_at
if expires_at - issued_at > MAX_ATTESTATION_LIFETIME_SECONDS
  fail_attestation("attestation lifetime exceeds #{MAX_ATTESTATION_LIFETIME_SECONDS} seconds")
end

environment = object(attestation["environment"], "environment")
exact_keys(environment, %w[clean_macos_account macos_version tester], "environment")
fail_attestation("clean_macos_account must be true") unless environment["clean_macos_account"] == true
string(environment["macos_version"], "environment macos_version")
string(environment["tester"], "environment tester")

attested_previous = object(attestation["previous_release"], "attested previous_release")
exact_keys(attested_previous, %w[dmg release_id tag], "attested previous_release")
fail_attestation("attested previous tag mismatch") unless attested_previous["tag"] == PREVIOUS_TAG
unless positive_integer(attested_previous["release_id"], "attested previous release ID") == previous_release_id
  fail_attestation("attested previous release ID mismatch")
end
validate_attested_file(attested_previous["dmg"], previous_expected_file, "attested previous DMG", include_id: true)

attested_candidate = object(attestation["candidate"], "attested candidate")
exact_keys(attested_candidate, %w[actions_artifact dmg signed_and_notarized source_commit tag], "attested candidate")
fail_attestation("attested candidate tag mismatch") unless attested_candidate["tag"] == expected_tag
unless oid(attested_candidate["source_commit"], "attested candidate source commit") == expected_source_commit
  fail_attestation("attested candidate source commit mismatch")
end
fail_attestation("candidate must be attested signed and notarized") unless attested_candidate["signed_and_notarized"] == true
validate_attested_file(attested_candidate["dmg"], candidate_expected_file, "attested candidate DMG")

attested_artifact = object(attested_candidate["actions_artifact"], "attested candidate Actions artifact")
exact_keys(attested_artifact, %w[archive_sha256 id manifest_sha256 name run_attempt run_id], "attested candidate Actions artifact")
unless string(attested_artifact["name"], "attested candidate Actions artifact name") == expected_artifact_name
  fail_attestation("attested candidate Actions artifact name mismatch")
end
unless positive_integer(attested_artifact["id"], "attested candidate Actions artifact ID") == expected_artifact_id
  fail_attestation("attested candidate Actions artifact ID mismatch")
end
unless sha256(attested_artifact["archive_sha256"], "attested candidate Actions artifact archive SHA-256") == expected_artifact_archive_sha256
  fail_attestation("attested candidate Actions artifact archive SHA-256 mismatch")
end
unless positive_integer(attested_artifact["run_id"], "attested candidate Actions artifact run ID") == expected_run_id
  fail_attestation("attested candidate Actions artifact run ID mismatch")
end
unless positive_integer(attested_artifact["run_attempt"], "attested candidate Actions artifact run attempt") == expected_run_attempt
  fail_attestation("attested candidate Actions artifact run attempt mismatch")
end
unless sha256(attested_artifact["manifest_sha256"], "attested candidate manifest SHA-256") == candidate_manifest_sha256
  fail_attestation("attested candidate manifest SHA-256 mismatch")
end

checks = object(attestation["checks"], "checks")
exact_keys(checks, REQUIRED_CHECKS, "checks")
REQUIRED_CHECKS.each do |check|
  fail_attestation("required clean-account check did not pass: #{check}") unless checks[check] == true
end

puts "ok: detached Ed25519 clean-account candidate attestation verified"
puts "ok: repository #{expected_repository}; nonce #{expected_nonce}; valid until #{expires_at.iso8601}"
puts "ok: previous #{PREVIOUS_TAG} release #{previous_release_id} DMG asset #{previous_asset_id} sha256 #{previous_dmg_sha256}"
puts "ok: candidate #{expected_tag} source #{expected_source_commit} artifact #{expected_artifact_name} ID #{expected_artifact_id} archive #{expected_artifact_archive_sha256} manifest #{candidate_manifest_sha256}"
puts "ok: candidate DMG #{candidate_dmg_name} size #{candidate_expected_file.fetch('size')} sha256 #{candidate_expected_file.fetch('sha256')}"
puts "ok: #{REQUIRED_CHECKS.length} required clean-account checks passed"
rescue ChronicleReleaseCandidateManifest::Error => error
  fail_attestation(error.message)
end
