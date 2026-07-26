#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "time"

SHA256_PATTERN = /\A[0-9a-f]{64}\z/
OID_PATTERN = /\A[0-9a-f]{40,64}\z/

def fail_attestation(message)
  warn "upgrade drill attestation: #{message}"
  exit 1
end

def object(value, label)
  fail_attestation("#{label} must be an object") unless value.is_a?(Hash)
  value
end

def string(value, label)
  fail_attestation("#{label} must be a non-empty string") unless value.is_a?(String) && !value.empty?
  value
end

def positive_integer(value, label)
  fail_attestation("#{label} must be a positive integer") unless value.is_a?(Integer) && value.positive?
  value
end

def sha256(value, label)
  fail_attestation("#{label} must be a lowercase SHA-256") unless value.is_a?(String) && value.match?(SHA256_PATTERN)
  value
end

def oid(value, label)
  fail_attestation("#{label} must be a full Git object ID") unless value.is_a?(String) && value.match?(OID_PATTERN)
  value
end

def capture_git(root, *arguments)
  output, error, status = Open3.capture3("git", "-C", root.to_s, *arguments)
  fail_attestation("git #{arguments.join(' ')} failed: #{error.strip}") unless status.success?
  output.strip
end

root = Pathname(ARGV.fetch(0, ".")).expand_path
manifest_path = Pathname(ARGV.fetch(1)).expand_path
fingerprint_tool = root.join("script/support/release_source_fingerprint.rb")

fail_attestation("source root is unavailable: #{root}") unless root.directory?
fail_attestation("source fingerprint tool is unavailable: #{fingerprint_tool}") unless fingerprint_tool.file? && !fingerprint_tool.symlink?
begin
  manifest_stat = manifest_path.lstat
rescue SystemCallError => error
  fail_attestation("manifest is unavailable: #{manifest_path} (#{error.class})")
end
unless manifest_stat.file? && !manifest_stat.symlink? && manifest_stat.size.positive?
  fail_attestation("manifest must be a non-symlink, non-empty regular file: #{manifest_path}")
end
manifest_name = manifest_path.basename.to_s
manifest_name_match = manifest_name.match(
  /\Aprevious-release-upgrade-drill-([0-9]{8}T[0-9]{6}Z)[.]json\z/
)
unless manifest_name_match
  fail_attestation("manifest file name is unsafe: #{manifest_name}")
end
attestation_timestamp = manifest_name_match[1]
begin
  parsed_attestation_time = Time.strptime(attestation_timestamp, "%Y%m%dT%H%M%S%z").utc
rescue ArgumentError
  fail_attestation("manifest file name has an invalid UTC timestamp: #{manifest_name}")
end
unless parsed_attestation_time.strftime("%Y%m%dT%H%M%SZ") == attestation_timestamp
  fail_attestation("manifest file name has an invalid UTC timestamp: #{manifest_name}")
end
expected_created_at = parsed_attestation_time.iso8601

begin
  manifest = JSON.parse(manifest_path.binread)
rescue JSON::ParserError => error
  fail_attestation("manifest is invalid JSON: #{error.message}")
end
manifest = object(manifest, "manifest")
fail_attestation("unsupported schema_version #{manifest['schema_version'].inspect}") unless manifest["schema_version"] == 1
unless manifest["attestation_type"] == "chronicle_previous_release_upgrade_drill"
  fail_attestation("unexpected attestation_type #{manifest['attestation_type'].inspect}")
end
fail_attestation("status is not passed") unless manifest["status"] == "passed"
fail_attestation("pass flag is not true") unless manifest["pass"] == true
created_at = string(manifest["created_at"], "created_at")
begin
  Time.iso8601(created_at)
rescue ArgumentError
  fail_attestation("created_at is not ISO-8601")
end
unless created_at == expected_created_at
  fail_attestation("created_at mismatch: expected #{expected_created_at}, got #{created_at}")
end

source = object(manifest["source"], "source")
unless source["fingerprint_schema"] == "chronicle-release-source-fingerprint-v1"
  fail_attestation("unsupported source fingerprint schema")
end
attested_fingerprint = sha256(source["fingerprint"], "source fingerprint")
attested_commit = oid(source["commit"], "source commit")
attested_branch = string(source["branch"], "source branch")
unless source["dirty"] == true || source["dirty"] == false
  fail_attestation("source dirty must be boolean")
end

fingerprint_output, fingerprint_error, fingerprint_status = Open3.capture3(
  "/usr/bin/ruby", fingerprint_tool.to_s, root.to_s
)
fail_attestation("could not compute current source fingerprint: #{fingerprint_error.strip}") unless fingerprint_status.success?
current_fingerprint = fingerprint_output.strip
fail_attestation("current source fingerprint is invalid") unless current_fingerprint.match?(SHA256_PATTERN)
unless current_fingerprint == attested_fingerprint
  fail_attestation("source fingerprint mismatch: attested #{attested_fingerprint}, current #{current_fingerprint}")
end

current_commit = capture_git(root, "rev-parse", "HEAD")
fail_attestation("source commit mismatch: attested #{attested_commit}, current #{current_commit}") unless current_commit == attested_commit
dirty_output, dirty_error, dirty_status = Open3.capture3(
  "/usr/bin/ruby", fingerprint_tool.to_s, root.to_s, "--dirty"
)
fail_attestation("could not compute current release-input dirty state: #{dirty_error.strip}") unless dirty_status.success?
current_dirty = dirty_output.strip == "true"
unless %w[true false].include?(dirty_output.strip)
  fail_attestation("current release-input dirty state is invalid")
end
branch_output, = Open3.capture3("git", "-C", root.to_s, "symbolic-ref", "--short", "-q", "HEAD")
current_branch = branch_output.strip
current_branch = "DETACHED" if current_branch.empty?

previous = object(manifest["previous_release"], "previous_release")
previous_tag = string(previous["tag"], "previous release tag")
expected_previous_tag = ENV.fetch("UPGRADE_DRILL_PREVIOUS_TAG", "v1.0.5")
unless previous_tag == expected_previous_tag
  fail_attestation("previous tag mismatch: attested #{previous_tag}, expected #{expected_previous_tag}")
end
attested_previous_commit = oid(previous["resolved_commit"], "previous resolved commit")
current_previous_commit = capture_git(root, "rev-parse", "refs/tags/#{expected_previous_tag}^{commit}")
unless current_previous_commit == attested_previous_commit
  fail_attestation("previous commit mismatch: attested #{attested_previous_commit}, resolved #{current_previous_commit}")
end

previous_source = object(previous["source"], "previous release source")
unless previous_source["mode"] == "git_archive_resolved_commit_release_safety_build"
  fail_attestation("unexpected previous source mode")
end
unless oid(previous_source["archive_commit"], "previous archive commit") == attested_previous_commit
  fail_attestation("previous archive was not bound to the resolved commit")
end
attested_previous_tree = oid(previous_source["tree_oid"], "previous source tree")
current_previous_tree = capture_git(root, "rev-parse", "#{attested_previous_commit}^{tree}")
unless attested_previous_tree == current_previous_tree
  fail_attestation("previous source tree mismatch: attested #{attested_previous_tree}, resolved #{current_previous_tree}")
end
sha256(previous_source["executable_sha256"], "previous executable digest")
fail_attestation("previous source configuration must be Release") unless previous_source["configuration"] == "Release"
fail_attestation("previous safety build must report sandbox disabled") unless previous_source["sandbox_enabled"] == false

published_dmg = object(previous["published_dmg"], "previous published_dmg")
unless published_dmg["used"] == true || published_dmg["used"] == false
  fail_attestation("previous published_dmg.used must be boolean")
end
if published_dmg["used"]
  string(published_dmg["path"], "previous published DMG path")
  sha256(published_dmg["sha256"], "previous published DMG digest")
elsif !published_dmg["path"].nil? || !published_dmg["sha256"].nil?
  fail_attestation("unused previous published DMG must have null path and digest")
end

candidate = object(manifest["candidate"], "candidate")
fail_attestation("candidate mode mismatch") unless candidate["mode"] == "debug_ui_test_direct_app_support"
fail_attestation("candidate configuration must be Debug") unless candidate["configuration"] == "Debug"
fail_attestation("candidate signing summary must be unsigned") unless candidate["signing"] == "unsigned"
%w[bundle_id product_name version build].each { |field| string(candidate[field], "candidate #{field}") }
%w[executable_sha256 sqlcipher_framework_sha256 upgraded_database_sha256].each do |field|
  sha256(candidate[field], "candidate #{field}")
end
fail_attestation("candidate must report fixed test key use") unless candidate["uses_fixed_test_key"] == true
fail_attestation("candidate must report app-support override use") unless candidate["uses_app_support_override"] == true

schema = object(manifest["database_schema"], "database_schema")
expected_schema = {
  "previous_migration_count" => 5,
  "candidate_migration_count" => 11,
  "candidate_only_table_count" => 8,
  "preserved_sentinel_domains" => 7
}.freeze
expected_schema.each do |field, expected|
  actual = positive_integer(schema[field], "database_schema.#{field}")
  unless actual == expected
    fail_attestation("database_schema.#{field} mismatch: expected #{expected}, got #{actual}")
  end
end

checks = object(manifest["checks"], "checks")
required_checks = %w[
  previous_schema_created plaintext_to_sqlcipher_upgrade candidate_integrity
  candidate_projection rollback_backup_unchanged previous_source_rollback_read
  generated_preferences_cleaned temporary_data_removed
]
required_checks.each do |field|
  fail_attestation("required check did not pass: #{field}") unless checks[field] == true
end

log = object(manifest["log"], "log")
log_name = string(log["file"], "log file")
log_name_match = log_name.match(
  /\Aprevious-release-upgrade-drill-([0-9]{8}T[0-9]{6}Z)[.]log\z/
)
unless File.basename(log_name) == log_name && log_name_match
  fail_attestation("log file name is unsafe: #{log_name}")
end
unless log_name_match[1] == attestation_timestamp
  fail_attestation(
    "log timestamp mismatch: attestation #{attestation_timestamp}, log #{log_name_match[1]}"
  )
end
log_size = positive_integer(log["size"], "log size")
log_sha256 = sha256(log["sha256"], "log digest")
log_path = manifest_path.dirname.join(log_name)
begin
  log_stat = log_path.lstat
rescue SystemCallError => error
  fail_attestation("attested log is unavailable: #{log_path} (#{error.class})")
end
unless log_stat.file? && !log_stat.symlink? && log_stat.size == log_size
  fail_attestation("attested log type or size mismatch: #{log_path}")
end
actual_log_sha256 = Digest::SHA256.file(log_path).hexdigest
fail_attestation("attested log digest mismatch") unless actual_log_sha256 == log_sha256

limitations = manifest["limitations"]
unless limitations.is_a?(Array) && limitations.length >= 3 && limitations.all? { |item| item.is_a?(String) && !item.empty? }
  fail_attestation("limitations must explicitly describe the bounded drill")
end

puts "ok: passed previous-release upgrade attestation verified"
puts "ok: source #{attested_commit} fingerprint #{attested_fingerprint}"
puts "info: attested branch #{attested_branch}; current branch #{current_branch}"
puts "info: attested release-input dirty=#{source['dirty']}; current release-input dirty=#{current_dirty} (informational)"
puts "ok: previous #{previous_tag} resolved to #{attested_previous_commit}"
puts "ok: log #{log_name} sha256 #{log_sha256}"
puts "notice: this bounded source/Debug drill does not satisfy the external published-binary clean-account gate"
