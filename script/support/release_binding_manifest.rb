#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"

SCHEMA_VERSION = 3
SHA256_PATTERN = /\A[0-9a-f]{64}\z/
OID_PATTERN = /\A[0-9a-f]{40,64}\z/

def fail_manifest(message)
  warn "release binding manifest: #{message}"
  exit 1
end

def usage
  warn <<~USAGE
    Usage:
      #{$PROGRAM_NAME} create <manifest> <release-id> <tag> <source-commit> <release-notes> <repository> <run-id> <run-attempt> <head-sha> <workflow-ref> <workflow-sha> <asset> <upload-response> <asset> <upload-response>
      #{$PROGRAM_NAME} verify <manifest> <exact-release-json> <tag> <release-id> <source-commit> <dmg-name> <checksum-name> <repository> <run-id> <run-attempt> <head-sha> <workflow-ref> <workflow-sha>
  USAGE
  exit 64
end

def positive_integer(value, label)
  integer = value.is_a?(Integer) ? value : Integer(value, 10)
  fail_manifest("#{label} must be a positive integer") unless integer.positive?
  integer
rescue ArgumentError, TypeError
  fail_manifest("#{label} must be a positive integer")
end

def positive_json_integer(value, label)
  unless value.is_a?(Integer) && value.positive?
    fail_manifest("#{label} must be a positive JSON integer")
  end
  value
end

def safe_regular_file(path, label, allow_empty: false)
  stat = File.lstat(path)
  unless stat.file? && !stat.symlink?
    fail_manifest("#{label} must be a non-symlink regular file: #{path}")
  end
  if !allow_empty && stat.size.zero?
    fail_manifest("#{label} must not be empty: #{path}")
  end
  path
rescue SystemCallError => error
  fail_manifest("#{label} is unavailable: #{path} (#{error.class})")
end

def json_object(path, label)
  data = JSON.parse(File.binread(safe_regular_file(path, label)))
  fail_manifest("#{label} must contain one JSON object") unless data.is_a?(Hash)
  data
rescue JSON::ParserError => error
  fail_manifest("#{label} is invalid JSON: #{error.message}")
end

def exact_keys(object, expected, label)
  actual = object.keys.sort
  wanted = expected.sort
  return if actual == wanted

  fail_manifest("#{label} keys must be exactly #{wanted.inspect}; got #{actual.inspect}")
end

def manifest_sha256(value, label)
  unless value.is_a?(String) && value.match?(SHA256_PATTERN)
    fail_manifest("#{label} must be a lowercase SHA-256 digest")
  end
  value
end

def source_commit(value, label)
  unless value.is_a?(String) && value.match?(OID_PATTERN)
    fail_manifest("#{label} must be a full lowercase Git object ID")
  end
  value
end

def remote_sha256(value, label)
  digest = value.to_s.sub(/\Asha256:/i, "").downcase
  unless digest.match?(SHA256_PATTERN)
    fail_manifest("#{label} is missing a valid SHA-256 digest")
  end
  digest
end

def safe_tag(value)
  unless value.is_a?(String) && !value.empty? && !value.match?(/[\r\n]/)
    fail_manifest("tag must be a non-empty single-line string")
  end
  value
end

def single_line(value, label)
  unless value.is_a?(String) && !value.empty? && !value.match?(/[\r\n]/)
    fail_manifest("#{label} must be a non-empty single-line string")
  end
  value
end

def create_manifest(arguments)
  usage unless arguments.length == 15

  manifest_path, release_id_value, tag_value, source_commit_value, notes_path,
    repository_value, run_id_value, run_attempt_value, head_sha_value,
    workflow_ref_value, workflow_sha_value, *asset_arguments = arguments
  release_id = positive_integer(release_id_value, "release ID")
  tag = safe_tag(tag_value)
  release_source_commit = source_commit(source_commit_value, "source commit")
  repository = single_line(repository_value, "repository")
  fail_manifest("repository must be owner/name") unless repository.match?(/\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\z/)
  run_id = positive_integer(run_id_value, "staging run ID")
  run_attempt = positive_integer(run_attempt_value, "staging run attempt")
  head_sha = source_commit(head_sha_value, "staging run head SHA")
  workflow_ref = single_line(workflow_ref_value, "staging workflow ref")
  workflow_sha = source_commit(workflow_sha_value, "staging workflow SHA")
  safe_regular_file(notes_path, "release notes")

  if File.exist?(manifest_path) || File.symlink?(manifest_path)
    fail_manifest("refusing to replace an existing manifest: #{manifest_path}")
  end
  manifest_parent = File.dirname(File.expand_path(manifest_path))
  unless File.directory?(manifest_parent) && !File.symlink?(manifest_parent)
    fail_manifest("manifest parent must be a non-symlink directory: #{manifest_parent}")
  end

  assets = asset_arguments.each_slice(2).map do |asset_path, response_path|
    safe_regular_file(asset_path, "release asset")
    response = json_object(response_path, "upload response")

    name = File.basename(asset_path)
    size = File.size(asset_path)
    sha256 = Digest::SHA256.file(asset_path).hexdigest
    id = positive_json_integer(response["id"], "uploaded asset ID for #{name}")
    actual_digest = remote_sha256(response["digest"], "uploaded asset #{name}")

    fail_manifest("uploaded asset name mismatch for #{name}") unless response["name"] == name
    fail_manifest("uploaded asset size mismatch for #{name}") unless response["size"] == size
    fail_manifest("uploaded asset state mismatch for #{name}") unless response["state"] == "uploaded"
    fail_manifest("uploaded asset digest mismatch for #{name}") unless actual_digest == sha256

    {
      "id" => id,
      "name" => name,
      "size" => size,
      "sha256" => sha256
    }
  end.sort_by { |asset| asset.fetch("name") }

  names = assets.map { |asset| asset.fetch("name") }
  ids = assets.map { |asset| asset.fetch("id") }
  fail_manifest("asset names must be unique") unless names.uniq.length == names.length
  fail_manifest("asset IDs must be unique") unless ids.uniq.length == ids.length

  manifest = {
    "schema_version" => SCHEMA_VERSION,
    "release_id" => release_id,
    "tag_name" => tag,
    "source_commit" => release_source_commit,
    "staging_provenance" => {
      "repository" => repository,
      "run_id" => run_id,
      "run_attempt" => run_attempt,
      "head_sha" => head_sha,
      "workflow_ref" => workflow_ref,
      "workflow_sha" => workflow_sha
    },
    "release_notes" => {
      "size" => File.size(notes_path),
      "sha256" => Digest::SHA256.file(notes_path).hexdigest
    },
    "assets" => assets
  }

  serialized = JSON.pretty_generate(manifest) << "\n"
  File.open(manifest_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
    file.write(serialized)
    file.flush
    file.fsync
  end
  puts "Release binding manifest created: #{manifest_path}"
end

def verified_manifest(path, expected_tag, expected_release_id, expected_source_commit, expected_names, expected_provenance)
  manifest = json_object(path, "binding manifest")
  exact_keys(manifest, %w[assets release_id release_notes schema_version source_commit staging_provenance tag_name], "binding manifest")
  fail_manifest("unsupported schema version: #{manifest["schema_version"].inspect}") unless manifest["schema_version"] == SCHEMA_VERSION
  manifest_release_id = positive_json_integer(manifest["release_id"], "manifest release ID")
  fail_manifest("manifest release ID mismatch") unless manifest_release_id == expected_release_id
  fail_manifest("manifest tag mismatch") unless manifest["tag_name"] == expected_tag
  manifest_source_commit = source_commit(manifest["source_commit"], "manifest source commit")
  fail_manifest("manifest source commit mismatch") unless manifest_source_commit == expected_source_commit

  provenance = manifest["staging_provenance"]
  fail_manifest("manifest staging_provenance must be an object") unless provenance.is_a?(Hash)
  exact_keys(provenance, %w[head_sha repository run_attempt run_id workflow_ref workflow_sha], "manifest staging_provenance")
  repository = single_line(provenance["repository"], "manifest staging repository")
  fail_manifest("manifest staging repository must be owner/name") unless repository.match?(/\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\z/)
  positive_json_integer(provenance["run_id"], "manifest staging run ID")
  positive_json_integer(provenance["run_attempt"], "manifest staging run attempt")
  source_commit(provenance["head_sha"], "manifest staging head SHA")
  single_line(provenance["workflow_ref"], "manifest staging workflow ref")
  source_commit(provenance["workflow_sha"], "manifest staging workflow SHA")

  fail_manifest("manifest staging provenance mismatch") unless provenance == expected_provenance

  notes = manifest["release_notes"]
  fail_manifest("manifest release_notes must be an object") unless notes.is_a?(Hash)
  exact_keys(notes, %w[sha256 size], "manifest release_notes")
  positive_json_integer(notes["size"], "manifest release notes size")
  manifest_sha256(notes["sha256"], "manifest release notes sha256")

  assets = manifest["assets"]
  fail_manifest("manifest assets must be an array") unless assets.is_a?(Array)
  parsed_assets = assets.map do |asset|
    fail_manifest("each manifest asset must be an object") unless asset.is_a?(Hash)
    exact_keys(asset, %w[id name sha256 size], "manifest asset")
    name = asset["name"]
    fail_manifest("manifest asset name must be a non-empty string") unless name.is_a?(String) && !name.empty?
    {
      "id" => positive_json_integer(asset["id"], "manifest asset ID for #{name}"),
      "name" => name,
      "size" => positive_json_integer(asset["size"], "manifest asset size for #{name}"),
      "sha256" => manifest_sha256(asset["sha256"], "manifest asset sha256 for #{name}")
    }
  end

  names = parsed_assets.map { |asset| asset.fetch("name") }
  ids = parsed_assets.map { |asset| asset.fetch("id") }
  unless names.sort == expected_names.sort && names.uniq.length == names.length
    fail_manifest("manifest assets must be exactly #{expected_names.inspect}; got #{names.inspect}")
  end
  fail_manifest("manifest asset IDs must be unique") unless ids.uniq.length == ids.length

  [manifest, parsed_assets]
end

def verify_manifest(arguments)
  usage unless arguments.length == 13

  manifest_path, release_path, tag_value, release_id_value, source_commit_value, dmg_name, checksum_name,
    repository_value, run_id_value, run_attempt_value, head_sha_value,
    workflow_ref_value, workflow_sha_value = arguments
  tag = safe_tag(tag_value)
  release_id = positive_integer(release_id_value, "release ID")
  expected_source_commit = source_commit(source_commit_value, "expected source commit")
  expected_names = [dmg_name, checksum_name]
  expected_repository = single_line(repository_value, "expected staging repository")
  fail_manifest("expected staging repository must be owner/name") unless expected_repository.match?(/\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\z/)
  expected_provenance = {
    "repository" => expected_repository,
    "run_id" => positive_integer(run_id_value, "expected staging run ID"),
    "run_attempt" => positive_integer(run_attempt_value, "expected staging run attempt"),
    "head_sha" => source_commit(head_sha_value, "expected staging head SHA"),
    "workflow_ref" => single_line(workflow_ref_value, "expected staging workflow ref"),
    "workflow_sha" => source_commit(workflow_sha_value, "expected staging workflow SHA")
  }
  manifest, manifest_assets = verified_manifest(
    manifest_path, tag, release_id, expected_source_commit, expected_names, expected_provenance
  )
  release = json_object(release_path, "exact release response")

  fail_manifest("exact release ID does not match binding manifest") unless release["id"] == release_id
  fail_manifest("exact release tag does not match binding manifest") unless release["tag_name"] == tag
  fail_manifest("exact release name does not match binding manifest") unless release["name"] == tag

  body = release["body"]
  fail_manifest("exact release body must be a string") unless body.is_a?(String)
  expected_notes = manifest.fetch("release_notes")
  body_matches = body.bytesize == expected_notes.fetch("size") &&
    Digest::SHA256.hexdigest(body.b) == expected_notes.fetch("sha256")
  fail_manifest("release body does not match binding manifest") unless body_matches

  remote_assets = release["assets"]
  fail_manifest("exact release assets must be an array") unless remote_assets.is_a?(Array)
  unless remote_assets.all? { |asset| asset.is_a?(Hash) }
    fail_manifest("each exact release asset must be an object")
  end
  remote_names = remote_assets.map { |asset| asset["name"] }
  unless remote_names.sort == expected_names.sort && remote_names.uniq.length == remote_names.length
    fail_manifest("exact release assets must be exactly #{expected_names.inspect}; got #{remote_names.inspect}")
  end

  manifest_assets.each do |expected_asset|
    name = expected_asset.fetch("name")
    actual = remote_assets.find { |asset| asset["name"] == name }
    actual_id = actual["id"]
    unless actual_id == expected_asset.fetch("id")
      fail_manifest("asset #{name} ID does not match binding manifest: got #{actual_id.inspect}, expected #{expected_asset.fetch("id")}")
    end
    unless actual["size"] == expected_asset.fetch("size")
      fail_manifest("asset #{name} size does not match binding manifest")
    end
    fail_manifest("asset #{name} is not uploaded") unless actual["state"] == "uploaded"
    actual_digest = remote_sha256(actual["digest"], "asset #{name}")
    unless actual_digest == expected_asset.fetch("sha256")
      fail_manifest("asset #{name} SHA-256 does not match binding manifest")
    end
  end

  puts "Release binding manifest verified: release #{release_id}, #{manifest_assets.length} assets"
end

mode = ARGV.shift
case mode
when "create"
  create_manifest(ARGV)
when "verify"
  verify_manifest(ARGV)
else
  usage
end
