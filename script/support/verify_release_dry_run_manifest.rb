#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "time"

DIGEST_PATTERN = /\A[0-9a-f]{64}\z/
SAFE_BASENAME = /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/
ANALYZE_COMMAND_PREFIX = "CHRONICLE_RELEASE_ANALYZE_COMMAND "
ANALYZE_SUCCESS_MARKER = "** ANALYZE SUCCEEDED **"
ANALYZE_FAILURE_MARKER = "** ANALYZE FAILED **"

def fail_verification(message)
  warn "dry-run manifest verification: #{message}"
  exit 1
end

def require_hash(value, label)
  fail_verification("#{label} must be an object") unless value.is_a?(Hash)
  value
end

def require_exact_keys(value, expected, label)
  value = require_hash(value, label)
  actual = value.keys.sort
  wanted = expected.sort
  fail_verification("#{label} keys mismatch: expected #{wanted.inspect}, got #{actual.inspect}") unless actual == wanted
  value
end

def require_boolean(value, label)
  fail_verification("#{label} must be true or false") unless value == true || value == false
  value
end

def require_integer(value, label, positive: false)
  fail_verification("#{label} must be an integer") unless value.is_a?(Integer)
  fail_verification("#{label} must be positive") if positive && !value.positive?
  value
end

def require_string(value, label, nonempty: true)
  fail_verification("#{label} must be a string") unless value.is_a?(String)
  fail_verification("#{label} must be non-empty") if nonempty && value.empty?
  value
end

def require_digest(value, label)
  fail_verification("#{label} must be a lowercase SHA-256") unless value.is_a?(String) && value.match?(DIGEST_PATTERN)
  value
end

def require_safe_basename(value, label)
  unless value.is_a?(String) && value.match?(SAFE_BASENAME) && File.basename(value) == value
    fail_verification("#{label} must be a safe basename")
  end
  value
end

def stat_signature(stat)
  [
    stat.dev,
    stat.ino,
    stat.mode,
    stat.nlink,
    stat.size,
    stat.mtime.to_r,
    stat.ctime.to_r
  ]
end

def validate_regular_stat(stat, label)
  unless stat.file? && !stat.symlink? && stat.nlink == 1
    fail_verification("#{label} must be a single-link, non-symlink regular file")
  end
end

def verifier_test_seam(point)
  return unless ENV["DRY_RUN_VERIFIER_TEST_SEAM"] == point

  marker = ENV.fetch("DRY_RUN_VERIFIER_TEST_MARKER")
  release = ENV.fetch("DRY_RUN_VERIFIER_TEST_RELEASE")
  File.open(marker, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(point) }
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
  until File.exist?(release)
    fail_verification("test seam timed out at #{point}") if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    sleep 0.01
  end
end

def snapshot_directory(directory, label)
  entries = {}
  begin
    directory.children.each do |path|
      name = path.basename.to_s
      fail_verification("#{label} contains a duplicate basename: #{name}") if entries.key?(name)
      stat = path.lstat
      validate_regular_stat(stat, "#{label} entry #{name}")
      entries[name] = stat_signature(stat)
    end
  rescue Errno::ENOENT, Errno::ELOOP => error
    fail_verification("#{label} changed during enumeration: #{error.message}")
  end
  entries
end

def read_stable_file(directory, name, label, initial_snapshot: nil)
  path = directory.join(name)
  begin
    path_before = path.lstat
    validate_regular_stat(path_before, label)
    verifier_test_seam("after_lstat:#{label}")
    bytes = nil
    fd_signature = nil
    File.open(path.to_s, File::RDONLY | File::NOFOLLOW) do |file|
      file.binmode
      fd_before = file.stat
      validate_regular_stat(fd_before, label)
      unless stat_signature(path_before) == stat_signature(fd_before)
        fail_verification("#{label} identity changed between lstat and O_NOFOLLOW open")
      end
      bytes = file.read
      fd_after = file.stat
      unless stat_signature(fd_before) == stat_signature(fd_after)
        fail_verification("#{label} changed while its open file descriptor was read")
      end
      fd_signature = stat_signature(fd_after)
    end
    path_after = path.lstat
    unless fd_signature == stat_signature(path_after)
      fail_verification("#{label} path identity changed after its file descriptor was read")
    end
  rescue Errno::ENOENT, Errno::ELOOP => error
    fail_verification("#{label} could not be opened without following links: #{error.message}")
  end

  if initial_snapshot
    initial_signature = initial_snapshot[name]
    fail_verification("#{label} was absent from the initial exact directory snapshot") if initial_signature.nil?
    unless initial_signature == fd_signature
      fail_verification("#{label} changed after the initial exact directory snapshot")
    end
  end

  {
    path: path,
    name: name,
    bytes: bytes,
    size: bytes.bytesize,
    sha256: Digest::SHA256.hexdigest(bytes),
    signature: fd_signature
  }
end

def verify_file_evidence(directory, evidence, label, initial_snapshot: nil)
  evidence = require_exact_keys(evidence, %w[name sha256 size], label)
  name = require_safe_basename(evidence["name"], "#{label}.name")
  expected_size = require_integer(evidence["size"], "#{label}.size", positive: true)
  expected_digest = require_digest(evidence["sha256"], "#{label}.sha256")
  file = read_stable_file(directory, name, label, initial_snapshot: initial_snapshot)
  unless file[:size] == expected_size
    fail_verification("#{label} size mismatch: expected #{expected_size}, got #{file[:size]}")
  end
  unless file[:sha256] == expected_digest
    fail_verification("#{label} SHA-256 mismatch: expected #{expected_digest}, got #{file[:sha256]}")
  end
  file
end

usage = "usage: verify_release_dry_run_manifest.rb <manifest> <artifact-directory> <source-fingerprint> <source-commit> <release-tag> <app-version> <app-build> <source-dirty:true|false> [--exact-files]"
manifest_input = ARGV.fetch(0) { fail_verification(usage) }
directory_input = ARGV.fetch(1) { fail_verification(usage) }
expected_source_fingerprint = ARGV.fetch(2) { fail_verification(usage) }
expected_source_commit = ARGV.fetch(3) { fail_verification(usage) }
expected_release_tag = ARGV.fetch(4) { fail_verification(usage) }
expected_app_version = ARGV.fetch(5) { fail_verification(usage) }
expected_app_build = ARGV.fetch(6) { fail_verification(usage) }
expected_source_dirty_text = ARGV.fetch(7) { fail_verification(usage) }
exact_files = ARGV[8] == "--exact-files"
fail_verification(usage) if ARGV.length > 9 || (ARGV.length == 9 && !exact_files)
require_digest(expected_source_fingerprint, "expected source fingerprint")
unless expected_source_commit.match?(/\A[0-9a-f]{40,64}\z/)
  fail_verification("expected source commit must be a full commit object ID")
end
require_string(expected_release_tag, "expected release tag")
require_string(expected_app_version, "expected app version")
require_string(expected_app_build, "expected app build")
expected_source_dirty = case expected_source_dirty_text
                        when "true" then true
                        when "false" then false
                        else fail_verification("expected source dirty must be true or false")
                        end

directory = Pathname(directory_input).expand_path
begin
  directory_stat_before = directory.lstat
rescue Errno::ENOENT
  fail_verification("artifact directory is missing: #{directory}")
end
unless directory_stat_before.directory? && !directory_stat_before.symlink?
  fail_verification("artifact directory must be a non-symlink directory: #{directory}")
end
directory = directory.realpath
directory_signature_before = stat_signature(directory.lstat)
initial_snapshot = exact_files ? snapshot_directory(directory, "initial exact artifact directory") : nil

manifest_path = Pathname(manifest_input).expand_path
begin
  manifest_parent = manifest_path.dirname.realpath
rescue Errno::ENOENT, Errno::ELOOP => error
  fail_verification("manifest parent is unsafe: #{error.message}")
end
fail_verification("manifest must be an immediate child of the artifact directory") unless manifest_parent == directory
manifest_name = require_safe_basename(manifest_path.basename.to_s, "manifest basename")
manifest_file = read_stable_file(directory, manifest_name, "manifest", initial_snapshot: initial_snapshot)

begin
  manifest = JSON.parse(manifest_file[:bytes])
rescue JSON::ParserError => error
  fail_verification("manifest JSON is invalid: #{error.message}")
end
manifest = require_exact_keys(
  manifest,
  %w[attestation_type authoritative_rehearsal created_at pass publishable release schema_version source status validation artifact],
  "manifest"
)

fail_verification("schema_version must be 3") unless manifest["schema_version"] == 3
unless manifest["attestation_type"] == "chronicle_unsigned_release_dry_run"
  fail_verification("unexpected attestation_type")
end
authoritative = require_boolean(manifest["authoritative_rehearsal"], "authoritative_rehearsal")
expected_status = authoritative ? "passed" : "completed_non_authoritative"
fail_verification("status mismatch") unless manifest["status"] == expected_status
fail_verification("pass mismatch") unless require_boolean(manifest["pass"], "pass") == authoritative
fail_verification("publishable must be false") unless require_boolean(manifest["publishable"], "publishable") == false
begin
  Time.iso8601(require_string(manifest["created_at"], "created_at"))
rescue ArgumentError
  fail_verification("created_at must be an ISO-8601 timestamp")
end

source = require_exact_keys(manifest["source"], %w[branch commit dirty fingerprint fingerprint_schema], "source")
unless source["fingerprint_schema"] == "chronicle-release-source-fingerprint-v1"
  fail_verification("source fingerprint schema mismatch")
end
source_fingerprint = require_digest(source["fingerprint"], "source.fingerprint")
unless source_fingerprint == expected_source_fingerprint
  fail_verification("source fingerprint mismatch: expected #{expected_source_fingerprint}, got #{source_fingerprint}")
end
unless source["commit"].is_a?(String) && source["commit"].match?(/\A[0-9a-f]{40,64}\z/)
  fail_verification("source.commit must be a full commit object ID")
end
# Branch is informational because exact-SHA and pull-request checkouts are detached.
unless source["commit"] == expected_source_commit
  fail_verification("source.commit mismatch: expected #{expected_source_commit}, got #{source['commit']}")
end
require_string(source["branch"], "source.branch")
source_dirty = require_boolean(source["dirty"], "source.dirty")
unless source_dirty == expected_source_dirty
  fail_verification("source.dirty mismatch: expected #{expected_source_dirty}, got #{source_dirty}")
end

release = require_exact_keys(manifest["release"], %w[app_build app_version artifact_version tag], "release")
artifact_version = require_safe_basename(release["artifact_version"], "release.artifact_version")
release_tag = require_string(release["tag"], "release.tag")
app_version = require_string(release["app_version"], "release.app_version")
app_build = require_string(release["app_build"], "release.app_build")
unless release_tag == expected_release_tag
  fail_verification("release.tag mismatch: expected #{expected_release_tag}, got #{release_tag}")
end
unless app_version == expected_app_version
  fail_verification("release.app_version mismatch: expected #{expected_app_version}, got #{app_version}")
end
unless app_build == expected_app_build
  fail_verification("release.app_build mismatch: expected #{expected_app_build}, got #{app_build}")
end
expected_manifest_name = "Chronicle-#{artifact_version}.dry-run-manifest.json"
unless manifest_name == expected_manifest_name
  fail_verification("manifest basename mismatch: expected #{expected_manifest_name}, got #{manifest_name}")
end

validation = require_exact_keys(manifest["validation"], %w[preflight release_analyze unit_tests], "validation")
preflight = require_exact_keys(validation["preflight"], ["status"], "validation.preflight")
fail_verification("preflight status must be passed") unless preflight["status"] == "passed"

expected_files = [manifest_name]
tests = require_hash(validation["unit_tests"], "validation.unit_tests")
tests_executed = require_boolean(tests["executed"], "validation.unit_tests.executed")
fail_verification("authoritative manifest cannot omit unit tests") if authoritative && !tests_executed
if tests_executed
  tests = require_exact_keys(
    tests,
    %w[executed expected_failures failed passed result_bundle_evidence skipped status summary total],
    "validation.unit_tests"
  )
  fail_verification("unit-test status must be passed") unless tests["status"] == "passed"
  fail_verification("unit-test evidence name must be logical") unless tests["result_bundle_evidence"] == "ChronicleTests.xcresult"
  total = require_integer(tests["total"], "validation.unit_tests.total", positive: true)
  passed = require_integer(tests["passed"], "validation.unit_tests.passed", positive: true)
  failed = require_integer(tests["failed"], "validation.unit_tests.failed")
  skipped = require_integer(tests["skipped"], "validation.unit_tests.skipped")
  expected_failures = require_integer(tests["expected_failures"], "validation.unit_tests.expected_failures")
  unless total == passed && failed.zero? && skipped.zero? && expected_failures.zero?
    fail_verification("unit-test counts are not an exact all-pass result")
  end
  summary_file = verify_file_evidence(directory, tests["summary"], "unit summary", initial_snapshot: initial_snapshot)
  expected_summary_name = "Chronicle-#{artifact_version}.unit-test-summary.json"
  unless summary_file[:name] == expected_summary_name
    fail_verification("unit summary basename mismatch: expected #{expected_summary_name}, got #{summary_file[:name]}")
  end
  begin
    summary = JSON.parse(summary_file[:bytes])
  rescue JSON::ParserError => error
    fail_verification("unit summary JSON is invalid: #{error.message}")
  end
  summary = require_hash(summary, "unit summary")
  required_summary_fields = %w[expectedFailures failedTests passedTests result skippedTests totalTestCount]
  missing_summary_fields = required_summary_fields.reject { |field| summary.key?(field) }
  unless missing_summary_fields.empty?
    fail_verification("unit summary is missing #{missing_summary_fields.join(', ')}")
  end
  summary_counts = [
    summary["result"],
    require_integer(summary["totalTestCount"], "unit summary totalTestCount"),
    require_integer(summary["passedTests"], "unit summary passedTests"),
    require_integer(summary["failedTests"], "unit summary failedTests"),
    require_integer(summary["skippedTests"], "unit summary skippedTests"),
    require_integer(summary["expectedFailures"], "unit summary expectedFailures")
  ]
  unless summary_counts == ["Passed", total, passed, failed, skipped, expected_failures]
    fail_verification("unit summary contents do not match manifest counts")
  end
  expected_files << summary_file[:name]
else
  tests = require_exact_keys(tests, %w[executed reason status], "validation.unit_tests")
  unless tests["status"] == "skipped_non_authoritative" && !require_string(tests["reason"], "validation.unit_tests.reason").empty?
    fail_verification("skipped unit tests need an explicit reason")
  end
end

analysis = require_hash(validation["release_analyze"], "validation.release_analyze")
analysis_executed = require_boolean(analysis["executed"], "validation.release_analyze.executed")
fail_verification("authoritative manifest cannot omit Release Analyze") if authoritative && !analysis_executed
if analysis_executed
  analysis = require_exact_keys(analysis, %w[executed log receipt status], "validation.release_analyze")
  fail_verification("Release Analyze status must be passed") unless analysis["status"] == "passed"
  log_file = verify_file_evidence(directory, analysis["log"], "Release Analyze log", initial_snapshot: initial_snapshot)
  receipt_file = verify_file_evidence(directory, analysis["receipt"], "Release Analyze receipt", initial_snapshot: initial_snapshot)
  expected_log_name = "Chronicle-#{artifact_version}.release-analyze.log"
  expected_receipt_name = "Chronicle-#{artifact_version}.release-analyze.receipt.json"
  unless log_file[:name] == expected_log_name
    fail_verification("Release Analyze log basename mismatch: expected #{expected_log_name}, got #{log_file[:name]}")
  end
  unless receipt_file[:name] == expected_receipt_name
    fail_verification("Release Analyze receipt basename mismatch: expected #{expected_receipt_name}, got #{receipt_file[:name]}")
  end

  begin
    receipt = JSON.parse(receipt_file[:bytes])
  rescue JSON::ParserError => error
    fail_verification("Release Analyze receipt JSON is invalid: #{error.message}")
  end
  receipt = require_exact_keys(receipt, %w[command log receipt_type result schema_version source], "Release Analyze receipt")
  fail_verification("Release Analyze receipt schema_version must be 1") unless receipt["schema_version"] == 1
  unless receipt["receipt_type"] == "chronicle_release_analyze_execution"
    fail_verification("unexpected Release Analyze receipt_type")
  end

  command = require_exact_keys(
    receipt["command"],
    %w[action architectures argv cloned_source_packages_path code_signing_allowed configuration derived_data_path destination executable only_active_arch project scheme],
    "Release Analyze receipt.command"
  )
  fixed_command = {
    "executable" => "xcodebuild",
    "project" => "Chronicle.xcodeproj",
    "scheme" => "Chronicle",
    "action" => "analyze",
    "configuration" => "Release",
    "destination" => "generic/platform=macOS",
    "architectures" => %w[arm64 x86_64],
    "only_active_arch" => false,
    "code_signing_allowed" => false
  }
  fixed_command.each do |key, expected|
    fail_verification("Release Analyze receipt.command.#{key} mismatch") unless command[key] == expected
  end
  derived_data_path = require_string(command["derived_data_path"], "Release Analyze receipt.command.derived_data_path")
  unless Pathname(derived_data_path).absolute?
    fail_verification("Release Analyze receipt.command.derived_data_path must be absolute")
  end
  cloned_source_packages_path = command["cloned_source_packages_path"]
  unless cloned_source_packages_path.nil? || (cloned_source_packages_path.is_a?(String) && !cloned_source_packages_path.empty? && Pathname(cloned_source_packages_path).absolute?)
    fail_verification("Release Analyze receipt.command.cloned_source_packages_path must be null or absolute")
  end
  argv = command["argv"]
  unless argv.is_a?(Array) && argv.all? { |argument| argument.is_a?(String) && !argument.empty? }
    fail_verification("Release Analyze receipt.command.argv must be a non-empty string array")
  end
  unless argv.uniq.length == argv.length
    fail_verification("Release Analyze receipt.command.argv must not contain duplicate arguments")
  end
  expected_argv = [
    "-project", "Chronicle.xcodeproj",
    "-scheme", "Chronicle",
    "-configuration", "Release",
    "-destination", "generic/platform=macOS",
    "-derivedDataPath", derived_data_path
  ]
  if cloned_source_packages_path
    expected_argv.concat(["-clonedSourcePackagesDirPath", cloned_source_packages_path, "-disableAutomaticPackageResolution"])
  end
  expected_argv.concat(["ARCHS=arm64 x86_64", "ONLY_ACTIVE_ARCH=NO", "CODE_SIGNING_ALLOWED=NO", "clean", "analyze"])
  unless argv == expected_argv
    fail_verification("Release Analyze receipt.command.argv is not the exact canonical Release Analyze invocation")
  end

  result = require_exact_keys(receipt["result"], %w[exit_code finished_at started_at], "Release Analyze receipt.result")
  fail_verification("Release Analyze receipt exit_code must be 0") unless require_integer(result["exit_code"], "Release Analyze receipt.result.exit_code") == 0
  begin
    started_at = Time.iso8601(require_string(result["started_at"], "Release Analyze receipt.result.started_at"))
    finished_at = Time.iso8601(require_string(result["finished_at"], "Release Analyze receipt.result.finished_at"))
  rescue ArgumentError
    fail_verification("Release Analyze receipt timestamps must be ISO-8601")
  end
  fail_verification("Release Analyze receipt finished_at precedes started_at") if finished_at < started_at

  receipt_source = require_exact_keys(receipt["source"], %w[after before fingerprint_schema], "Release Analyze receipt.source")
  unless receipt_source["fingerprint_schema"] == "chronicle-release-source-fingerprint-v1"
    fail_verification("Release Analyze receipt source fingerprint schema mismatch")
  end
  receipt_before = require_digest(receipt_source["before"], "Release Analyze receipt.source.before")
  receipt_after = require_digest(receipt_source["after"], "Release Analyze receipt.source.after")
  unless receipt_before == expected_source_fingerprint && receipt_after == expected_source_fingerprint
    fail_verification("Release Analyze receipt source fingerprints must both match the expected source")
  end

  receipt_log = require_exact_keys(receipt["log"], %w[name sha256 size], "Release Analyze receipt.log")
  expected_log_evidence = {
    "name" => log_file[:name],
    "size" => log_file[:size],
    "sha256" => log_file[:sha256]
  }
  unless receipt_log == expected_log_evidence
    fail_verification("Release Analyze receipt log evidence does not match the bound log")
  end

  command_lines = log_file[:bytes].lines.select { |line| line.start_with?(ANALYZE_COMMAND_PREFIX) }
  fail_verification("Release Analyze log must contain exactly one structured command record") unless command_lines.length == 1
  begin
    logged_command = JSON.parse(command_lines.fetch(0).delete_prefix(ANALYZE_COMMAND_PREFIX))
  rescue JSON::ParserError => error
    fail_verification("Release Analyze log command record is invalid JSON: #{error.message}")
  end
  fail_verification("Release Analyze log command record does not match the receipt") unless logged_command == command
  success_count = log_file[:bytes].lines.count { |line| line.chomp == ANALYZE_SUCCESS_MARKER }
  fail_verification("Release Analyze log must contain exactly one success marker") unless success_count == 1
  if log_file[:bytes].include?(ANALYZE_FAILURE_MARKER)
    fail_verification("Release Analyze log contains a failure marker")
  end
  expected_files.concat([log_file[:name], receipt_file[:name]])
else
  analysis = require_exact_keys(analysis, %w[executed reason status], "validation.release_analyze")
  unless !authoritative && analysis["status"] == "skipped_non_authoritative" && !require_string(analysis["reason"], "validation.release_analyze.reason").empty?
    fail_verification("skipped Release Analyze needs an explicit non-authoritative reason")
  end
end

artifact = require_exact_keys(manifest["artifact"], %w[checksum dmg inspection_mode notarized signing stapled], "artifact")
fail_verification("artifact inspection mode must be rehearsal") unless artifact["inspection_mode"] == "rehearsal"
fail_verification("artifact signing must be unsigned") unless artifact["signing"] == "unsigned"
fail_verification("artifact notarized must be false") unless require_boolean(artifact["notarized"], "artifact.notarized") == false
fail_verification("artifact stapled must be false") unless require_boolean(artifact["stapled"], "artifact.stapled") == false

dmg_file = verify_file_evidence(directory, artifact["dmg"], "DMG", initial_snapshot: initial_snapshot)
expected_dmg_name = "Chronicle-#{artifact_version}.dmg"
unless dmg_file[:name] == expected_dmg_name
  fail_verification("DMG basename mismatch: expected #{expected_dmg_name}, got #{dmg_file[:name]}")
end
checksum_file = verify_file_evidence(directory, artifact["checksum"], "checksum", initial_snapshot: initial_snapshot)
expected_checksum_name = "#{dmg_file[:name]}.sha256"
unless checksum_file[:name] == expected_checksum_name
  fail_verification("checksum basename mismatch: expected #{expected_checksum_name}, got #{checksum_file[:name]}")
end
expected_checksum_bytes = "#{dmg_file[:sha256]}  #{dmg_file[:name]}\n"
unless checksum_file[:bytes] == expected_checksum_bytes
  fail_verification("checksum contents must be the exact DMG SHA-256 and basename")
end
expected_files.concat([dmg_file[:name], checksum_file[:name]])

if exact_files
  expected_files = expected_files.uniq.sort
  initial_names = initial_snapshot.keys.sort
  unless initial_names == expected_files
    fail_verification("exact artifact file set mismatch: expected #{expected_files.inspect}, got #{initial_names.inspect}")
  end
  final_snapshot = snapshot_directory(directory, "final exact artifact directory")
  unless final_snapshot.keys.sort == expected_files
    fail_verification("exact artifact file set mismatch: expected #{expected_files.inspect}, got #{final_snapshot.keys.sort.inspect}")
  end
  unless final_snapshot == initial_snapshot
    fail_verification("exact artifact directory changed during verification")
  end
  directory_signature_after = stat_signature(directory.lstat)
  unless directory_signature_after == directory_signature_before
    fail_verification("artifact directory identity or metadata changed during verification")
  end
end

puts "Dry-run manifest verified: #{manifest_name}"
puts "Source fingerprint: #{source_fingerprint}"
puts "Unit tests: #{tests_executed ? 'passed' : 'skipped_non_authoritative'}"
puts "Release Analyze: #{analysis_executed ? 'passed' : 'skipped_non_authoritative'}"
puts "DMG: #{dmg_file[:name]} (#{dmg_file[:size]} bytes, #{dmg_file[:sha256]})"
