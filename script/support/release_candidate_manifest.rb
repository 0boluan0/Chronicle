#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"

module ChronicleReleaseCandidateManifest
  SCHEMA_VERSION = 1
  METADATA_SCHEMA_VERSION = 1
  SHA256_PATTERN = /\A[0-9a-f]{64}\z/
  OID_PATTERN = /\A[0-9a-f]{40,64}\z/
  REPOSITORY_PATTERN = /\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\z/
  TAG_PATTERN = /\Av\d+\.\d+\.\d+(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?\z/
  ARTIFACT_PATTERN = /\Achronicle-release-candidate-v[0-9A-Za-z.-]+-[1-9][0-9]*\z/
  MANIFEST_BASENAME = "candidate-manifest.json"
  METADATA_BASENAME = "candidate-metadata.json"
  RELEASE_NOTES_BASENAME = "release-notes.md"

  class Error < StandardError; end

  module_function

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

  def canonical_json_bytes(value)
    JSON.generate(canonical_json_value(value)) << "\n"
  end

  def exact_keys(value, expected, label)
    raise Error, "#{label} must be an object" unless value.is_a?(Hash)
    actual = value.keys.sort
    wanted = expected.sort
    return if actual == wanted

    raise Error, "#{label} keys must be exactly #{wanted.inspect}; got #{actual.inspect}"
  end

  def safe_string(value, label)
    unless value.is_a?(String) && !value.empty? && !value.match?(/[\r\n]/)
      raise Error, "#{label} must be a non-empty single-line string"
    end
    value
  end

  def safe_tag(value)
    value = safe_string(value, "tag")
    raise Error, "tag must be a safe semantic-version tag" unless value.match?(TAG_PATTERN)
    value
  end

  def repository(value)
    value = safe_string(value, "repository")
    raise Error, "repository must be owner/name" unless value.match?(REPOSITORY_PATTERN)
    value
  end

  def oid(value, label)
    unless value.is_a?(String) && value.match?(OID_PATTERN)
      raise Error, "#{label} must be a full lowercase Git object ID"
    end
    value
  end

  def positive_integer(value, label)
    integer = value.is_a?(Integer) ? value : Integer(value, 10)
    raise Error, "#{label} must be a positive integer" unless integer.positive?
    integer
  rescue ArgumentError, TypeError
    raise Error, "#{label} must be a positive integer"
  end

  def positive_json_integer(value, label)
    raise Error, "#{label} must be a positive JSON integer" unless value.is_a?(Integer) && value.positive?
    value
  end

  def sha256(value, label)
    unless value.is_a?(String) && value.match?(SHA256_PATTERN)
      raise Error, "#{label} must be a lowercase SHA-256"
    end
    value
  end

  def artifact_name(value)
    value = safe_string(value, "Actions artifact name")
    unless value.match?(ARTIFACT_PATTERN)
      raise Error, "Actions artifact name is unsafe: #{value.inspect}"
    end
    value
  end

  def safe_regular_file(path, label, allow_empty: false)
    stat = File.lstat(path)
    unless stat.file? && !stat.symlink?
      raise Error, "#{label} must be a non-symlink regular file: #{path}"
    end
    raise Error, "#{label} must not be empty: #{path}" if !allow_empty && stat.size.zero?
    stat
  rescue SystemCallError => error
    raise Error, "#{label} is unavailable: #{path} (#{error.class})"
  end

  def safe_directory(path, label)
    stat = File.lstat(path)
    unless stat.directory? && !stat.symlink?
      raise Error, "#{label} must be a non-symlink directory: #{path}"
    end
    path
  rescue SystemCallError => error
    raise Error, "#{label} is unavailable: #{path} (#{error.class})"
  end

  def json_object_with_bytes(path, label)
    bytes = File.binread(path) if safe_regular_file(path, label)
    value = JSON.parse(bytes)
    raise Error, "#{label} must contain one JSON object" unless value.is_a?(Hash)
    [value, bytes]
  rescue JSON::ParserError => error
    raise Error, "#{label} is invalid JSON: #{error.message}"
  end

  def write_exclusive_canonical(path, value, label)
    raise Error, "refusing to replace existing #{label}: #{path}" if File.exist?(path) || File.symlink?(path)
    parent = File.dirname(File.expand_path(path))
    safe_directory(parent, "#{label} parent")
    File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.write(canonical_json_bytes(value))
      file.flush
      file.fsync
    end
  rescue SystemCallError => error
    raise Error, "could not write #{label}: #{path} (#{error.class})"
  end

  def expected_names(tag)
    dmg_name = "Chronicle-#{tag}.dmg"
    [dmg_name, "#{dmg_name}.sha256", METADATA_BASENAME, RELEASE_NOTES_BASENAME]
  end

  def expected_provenance(repository_value:, run_id:, run_attempt:, head_sha:, workflow_ref:, workflow_sha:)
    {
      "repository" => repository(repository_value),
      "run_id" => positive_integer(run_id, "staging run ID"),
      "run_attempt" => positive_integer(run_attempt, "staging run attempt"),
      "head_sha" => oid(head_sha, "staging head SHA"),
      "workflow_ref" => safe_string(workflow_ref, "staging workflow ref"),
      "workflow_sha" => oid(workflow_sha, "staging workflow SHA")
    }
  end

  def create_metadata!(path:, tag:, source_commit:, repository_value:)
    tag = safe_tag(tag)
    source_commit = oid(source_commit, "source commit")
    repository_value = repository(repository_value)
    prerelease = tag.include?("-")
    dmg_name, checksum_name, = expected_names(tag)
    metadata = {
      "schema_version" => METADATA_SCHEMA_VERSION,
      "metadata_type" => "chronicle_release_candidate",
      "repository" => repository_value,
      "tag_name" => tag,
      "source_commit" => source_commit,
      "release_name" => tag,
      "prerelease" => prerelease,
      "make_latest" => !prerelease,
      "dmg_name" => dmg_name,
      "checksum_name" => checksum_name,
      "release_notes_name" => RELEASE_NOTES_BASENAME
    }
    write_exclusive_canonical(path, metadata, "candidate metadata")
    metadata
  end

  def validate_metadata!(path:, tag:, source_commit:, repository_value:)
    metadata, bytes = json_object_with_bytes(path, "candidate metadata")
    exact_keys(
      metadata,
      %w[checksum_name dmg_name make_latest metadata_type prerelease release_name release_notes_name repository schema_version source_commit tag_name],
      "candidate metadata"
    )
    unless bytes == canonical_json_bytes(metadata)
      raise Error, "candidate metadata must be canonical compact JSON with one trailing LF"
    end

    tag = safe_tag(tag)
    source_commit = oid(source_commit, "expected source commit")
    repository_value = repository(repository_value)
    prerelease = tag.include?("-")
    dmg_name, checksum_name, = expected_names(tag)
    expected = {
      "schema_version" => METADATA_SCHEMA_VERSION,
      "metadata_type" => "chronicle_release_candidate",
      "repository" => repository_value,
      "tag_name" => tag,
      "source_commit" => source_commit,
      "release_name" => tag,
      "prerelease" => prerelease,
      "make_latest" => !prerelease,
      "dmg_name" => dmg_name,
      "checksum_name" => checksum_name,
      "release_notes_name" => RELEASE_NOTES_BASENAME
    }
    raise Error, "candidate metadata does not match expected release identity" unless metadata == expected
    metadata
  end

  def file_record(path)
    stat = safe_regular_file(path, "candidate payload file")
    {
      "name" => File.basename(path),
      "size" => stat.size,
      "sha256" => Digest::SHA256.file(path).hexdigest
    }
  end

  def create!(manifest_path:, payload_dir:, artifact_name_value:, tag:, source_commit:, provenance:)
    safe_directory(payload_dir, "candidate payload directory")
    tag = safe_tag(tag)
    source_commit = oid(source_commit, "source commit")
    artifact_name_value = artifact_name(artifact_name_value)
    repository_value = provenance.fetch("repository")
    validate_metadata!(
      path: File.join(payload_dir, METADATA_BASENAME),
      tag: tag,
      source_commit: source_commit,
      repository_value: repository_value
    )

    expected = expected_names(tag)
    actual = Dir.children(payload_dir).sort
    unless actual == expected.sort
      raise Error, "candidate payload must contain exactly #{expected.sort.inspect}; got #{actual.inspect}"
    end
    files = expected.map { |name| file_record(File.join(payload_dir, name)) }.sort_by { |record| record.fetch("name") }
    manifest = {
      "schema_version" => SCHEMA_VERSION,
      "manifest_type" => "chronicle_release_candidate_manifest",
      "actions_artifact" => { "name" => artifact_name_value },
      "repository" => repository_value,
      "tag_name" => tag,
      "source_commit" => source_commit,
      "staging_provenance" => provenance,
      "files" => files
    }
    write_exclusive_canonical(manifest_path, manifest, "candidate manifest")
    manifest
  end

  def verify!(manifest_path:, payload_dir:, artifact_name_value:, tag:, source_commit:, provenance:)
    safe_directory(payload_dir, "candidate artifact directory")
    tag = safe_tag(tag)
    source_commit = oid(source_commit, "expected source commit")
    artifact_name_value = artifact_name(artifact_name_value)
    manifest, manifest_bytes = json_object_with_bytes(manifest_path, "candidate manifest")
    exact_keys(
      manifest,
      %w[actions_artifact files manifest_type repository schema_version source_commit staging_provenance tag_name],
      "candidate manifest"
    )
    unless manifest_bytes == canonical_json_bytes(manifest)
      raise Error, "candidate manifest must be canonical compact JSON with one trailing LF"
    end
    raise Error, "candidate manifest schema mismatch" unless manifest["schema_version"] == SCHEMA_VERSION
    unless manifest["manifest_type"] == "chronicle_release_candidate_manifest"
      raise Error, "candidate manifest type mismatch"
    end

    artifact = manifest["actions_artifact"]
    exact_keys(artifact, %w[name], "candidate manifest actions_artifact")
    raise Error, "candidate Actions artifact name mismatch" unless artifact_name(artifact["name"]) == artifact_name_value
    repository_value = repository(provenance.fetch("repository"))
    raise Error, "candidate manifest repository mismatch" unless manifest["repository"] == repository_value
    raise Error, "candidate manifest tag mismatch" unless manifest["tag_name"] == tag
    raise Error, "candidate manifest source commit mismatch" unless manifest["source_commit"] == source_commit

    manifest_provenance = manifest["staging_provenance"]
    exact_keys(manifest_provenance, %w[head_sha repository run_attempt run_id workflow_ref workflow_sha], "candidate manifest staging_provenance")
    manifest_provenance.fetch("repository") { raise Error, "candidate manifest staging repository is missing" }
    repository(manifest_provenance["repository"])
    positive_json_integer(manifest_provenance["run_id"], "candidate manifest staging run ID")
    positive_json_integer(manifest_provenance["run_attempt"], "candidate manifest staging run attempt")
    oid(manifest_provenance["head_sha"], "candidate manifest staging head SHA")
    safe_string(manifest_provenance["workflow_ref"], "candidate manifest staging workflow ref")
    oid(manifest_provenance["workflow_sha"], "candidate manifest staging workflow SHA")
    raise Error, "candidate manifest staging provenance mismatch" unless manifest_provenance == provenance

    expected = expected_names(tag)
    allowed = (expected + [MANIFEST_BASENAME]).sort
    actual = Dir.children(payload_dir).sort
    unless actual == allowed
      raise Error, "candidate artifact must contain exactly #{allowed.inspect}; got #{actual.inspect}"
    end

    files = manifest["files"]
    unless files.is_a?(Array) && files.all? { |file| file.is_a?(Hash) }
      raise Error, "candidate manifest files must be an array of objects"
    end
    parsed = files.map do |file|
      exact_keys(file, %w[name sha256 size], "candidate manifest file")
      name = safe_string(file["name"], "candidate manifest filename")
      raise Error, "candidate manifest filename must be an exact basename" unless File.basename(name) == name
      {
        "name" => name,
        "size" => positive_json_integer(file["size"], "candidate manifest file size for #{name}"),
        "sha256" => sha256(file["sha256"], "candidate manifest file SHA-256 for #{name}")
      }
    end
    names = parsed.map { |file| file.fetch("name") }
    unless names.sort == expected.sort && names.uniq.length == names.length
      raise Error, "candidate manifest files must be exactly #{expected.sort.inspect}; got #{names.inspect}"
    end

    parsed.each do |expected_file|
      path = File.join(payload_dir, expected_file.fetch("name"))
      actual_record = file_record(path)
      raise Error, "candidate file size mismatch: #{expected_file.fetch('name')}" unless actual_record["size"] == expected_file["size"]
      raise Error, "candidate file SHA-256 mismatch: #{expected_file.fetch('name')}" unless actual_record["sha256"] == expected_file["sha256"]
    end

    metadata = validate_metadata!(
      path: File.join(payload_dir, METADATA_BASENAME),
      tag: tag,
      source_commit: source_commit,
      repository_value: repository_value
    )
    dmg_name = metadata.fetch("dmg_name")
    checksum_name = metadata.fetch("checksum_name")
    dmg_digest = Digest::SHA256.file(File.join(payload_dir, dmg_name)).hexdigest
    checksum_bytes = File.binread(File.join(payload_dir, checksum_name))
    expected_checksum = "#{dmg_digest}  #{dmg_name}\n"
    raise Error, "candidate checksum file does not exactly bind the DMG" unless checksum_bytes == expected_checksum

    {
      "manifest" => manifest,
      "manifest_sha256" => Digest::SHA256.hexdigest(manifest_bytes),
      "metadata" => metadata,
      "files" => parsed.to_h { |file| [file.fetch("name"), file] }
    }
  end
end

def candidate_manifest_usage
  warn <<~USAGE
    Usage:
      #{$PROGRAM_NAME} metadata <metadata-path> <tag> <source-commit> <repository>
      #{$PROGRAM_NAME} create <manifest-path> <payload-dir> <artifact-name> <tag> <source-commit> <repository> <run-id> <run-attempt> <head-sha> <workflow-ref> <workflow-sha>
      #{$PROGRAM_NAME} verify <manifest-path> <payload-dir> <artifact-name> <tag> <source-commit> <repository> <run-id> <run-attempt> <head-sha> <workflow-ref> <workflow-sha>
  USAGE
  exit 64
end

if $PROGRAM_NAME == __FILE__
  begin
    mode = ARGV.shift
    case mode
    when "metadata"
      candidate_manifest_usage unless ARGV.length == 4
      path, tag, source_commit, repository = ARGV
      ChronicleReleaseCandidateManifest.create_metadata!(
        path: path,
        tag: tag,
        source_commit: source_commit,
        repository_value: repository
      )
      puts "Candidate metadata created: #{path}"
    when "create", "verify"
      candidate_manifest_usage unless ARGV.length == 11
      manifest_path, payload_dir, artifact_name, tag, source_commit, repository,
        run_id, run_attempt, head_sha, workflow_ref, workflow_sha = ARGV
      provenance = ChronicleReleaseCandidateManifest.expected_provenance(
        repository_value: repository,
        run_id: run_id,
        run_attempt: run_attempt,
        head_sha: head_sha,
        workflow_ref: workflow_ref,
        workflow_sha: workflow_sha
      )
      if mode == "create"
        ChronicleReleaseCandidateManifest.create!(
          manifest_path: manifest_path,
          payload_dir: payload_dir,
          artifact_name_value: artifact_name,
          tag: tag,
          source_commit: source_commit,
          provenance: provenance
        )
        puts "Candidate manifest created: #{manifest_path}"
      else
        result = ChronicleReleaseCandidateManifest.verify!(
          manifest_path: manifest_path,
          payload_dir: payload_dir,
          artifact_name_value: artifact_name,
          tag: tag,
          source_commit: source_commit,
          provenance: provenance
        )
        puts "Candidate manifest verified: #{artifact_name} #{result.fetch('manifest_sha256')}"
      end
    else
      candidate_manifest_usage
    end
  rescue ChronicleReleaseCandidateManifest::Error => error
    warn "release candidate manifest: #{error.message}"
    exit 1
  end
end
