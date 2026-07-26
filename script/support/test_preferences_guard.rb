#!/usr/bin/env ruby
# frozen_string_literal: true

require "English"
require "pathname"
require "securerandom"
require "tmpdir"

UUID_SOURCE_SUFFIX = "\\(UUID().uuidString)"
UUID_FILE_PATTERN = /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/

# These are the complete, reviewed suite prefixes constructed by ChronicleTests. Keeping the
# list explicit is intentional: a newly introduced suite must fail source verification until its
# cleanup scope has been reviewed. Do not replace this with a chronicle-* glob.
TEST_SUITE_PREFIXES = %w[
  chronicle-tests-defaults-newer-
  chronicle-tests-defaults-current-newer-
  chronicle-tests-defaults-retry-
  chronicle-tests-defaults-symlink-retry-
  chronicle-tests-defaults-missing-
  chronicle-tests-v1-0-5-reports-
  chronicle-tests-window-title-
  chronicle-tests-timeline-focus-
  chronicle-tests-telemetry-
  chronicle-tests-review-reminder-
  chronicle-tests-dock-pause-
  chronicle-tests-pause-checkpoint-
  chronicle-tests-dashboard-navigation-
  chronicle-tests-preferences-navigation-
  chronicle-tests-support-health-navigation-
  chronicle-tests-tracking-defaults-
  chronicle-tests-capture-profiles-
  chronicle-tests-template-migration-
  chronicle-tests-report-files-
  chronicle-tests-report-settings-persistence-
  chronicle-tests-report-folder-readiness-
  chronicle-tests-report-export-success-
  chronicle-tests-daily-log-menu-
  chronicle-export-history-
  chronicle-frozen-reviewed-tag-
  chronicle-reviewed-day-projection-
  chronicle-export-best-effort-
  chronicle-export-partial-write-
  chronicle-export-escaped-title-
  chronicle-reviewed-existing-conflict-
  chronicle-report-new-file-conflict-
  chronicle-csv-identical-aba-
  chronicle-csv-new-file-conflict-
  chronicle-tests-wipe-local-state-
  chronicle-tests-wipe-symlink-state-
  chronicle-tests-wipe-parent-symlink-
  chronicle-tests-wipe-path-swap-
  chronicle-tests-wipe-nested-symlink-
].freeze

# Most prefixes have one constructor. The pause-checkpoint restart test intentionally creates
# two independent UserDefaults objects for the same suite, in addition to the store-validation
# fixture, so source verification tracks the reviewed constructor count separately from the
# unique-prefix inventory.
TEST_SUITE_CONSTRUCTOR_COUNT = 40

TEST_PREFERENCE_PATTERNS = TEST_SUITE_PREFIXES.map do |prefix|
  /\A#{Regexp.escape(prefix)}#{UUID_FILE_PATTERN.source}\.plist\z/
end.freeze

UNIT_TEST_HOST_PATTERN = /\Acom\.Chronicle\.Chronicle\.unit-tests\.\d+-#{UUID_FILE_PATTERN.source}\.plist\z/
ALL_TEST_PREFERENCE_PATTERNS = (TEST_PREFERENCE_PATTERNS + [UNIT_TEST_HOST_PATTERN]).freeze

def fail_guard(message)
  warn "test preferences guard: #{message}"
  exit 1
end

def exact_test_preference_name?(name)
  ALL_TEST_PREFERENCE_PATTERNS.any? { |pattern| pattern.match?(name) }
end

def preference_entries(preferences_directory)
  Pathname(preferences_directory).children.each_with_object({}) do |path, entries|
    name = path.basename.to_s
    next unless exact_test_preference_name?(name)

    entries[name] = path
  end
end

def snapshot(preferences_directory)
  preference_entries(preferences_directory).keys.sort
end

def validate_cleanup_entry(preferences_directory, name, path)
  stat = path.lstat
  unless stat.file? && !stat.symlink?
    fail_guard("refusing to remove non-regular entry #{path}")
  end
  unless path.dirname == Pathname(preferences_directory) && exact_test_preference_name?(name)
    fail_guard("refusing cleanup outside the exact test-only allowlist: #{path}")
  end
end

def delete_test_entries_once(preferences_directory, entries, use_defaults:)
  entries.sort.each do |name, path|
    validate_cleanup_entry(preferences_directory, name, path)
    domain = name.delete_suffix(".plist")
    if use_defaults
      system(
        "/usr/bin/defaults",
        "delete",
        domain,
        out: File::NULL,
        err: File::NULL
      )
    end

    # `defaults delete` normally removes the backing file through cfprefsd. A short-lived empty
    # plist may remain, so unlink only after revalidating the exact regular-file target.
    next unless path.exist? || path.symlink?

    validate_cleanup_entry(preferences_directory, name, path)
    path.unlink
  end
end

def cleanup_test_entries_until_stable(
  preferences_directory,
  use_defaults: true,
  attempts: 20,
  stable_passes_required: 6,
  interval_seconds: 0.5
)
  seen_names = {}
  removed_names = {}
  stable_passes = 0

  attempts.times do
    entries = preference_entries(preferences_directory)
    entries.each_key do |name|
      seen_names[name] = true
      removed_names[name] = true
    end
    delete_test_entries_once(preferences_directory, entries, use_defaults: use_defaults) unless entries.empty?

    readable_domains = []
    if use_defaults
      seen_names.each_key do |name|
        domain = name.delete_suffix(".plist")
        next unless system(
          "/usr/bin/defaults",
          "read",
          domain,
          out: File::NULL,
          err: File::NULL
        )

        readable_domains << domain
        system(
          "/usr/bin/defaults",
          "delete",
          domain,
          out: File::NULL,
          err: File::NULL
        )
      end
    end

    remaining = preference_entries(preferences_directory)
    if remaining.empty? && readable_domains.empty?
      stable_passes += 1
      break if stable_passes >= stable_passes_required
    else
      stable_passes = 0
    end
    sleep interval_seconds if interval_seconds.positive?
  end

  remaining = snapshot(preferences_directory)
  fail_guard("test-only preferences remain after cleanup: #{remaining.join(', ')}") unless remaining.empty?
  if stable_passes < stable_passes_required
    fail_guard("test-only preferences did not remain absent for #{stable_passes_required} consecutive checks")
  end

  removed_names.length
end

def assert_zero_test_preference_baseline(preferences_directory)
  baseline = snapshot(preferences_directory)
  return if baseline.empty?

  fail_guard("test-only preferences baseline is not empty: #{baseline.join(', ')}")
end

def source_suite_prefixes(root_directory)
  test_paths = Dir[File.join(root_directory, "ChronicleTests", "*.swift")].sort
  fail_guard("no ChronicleTests Swift sources found under #{root_directory}") if test_paths.empty?

  assignments = test_paths.flat_map do |path|
    File.read(path).scan(/let\s+(?:suiteName|defaultsName|reportDefaultsName)\s*=\s*"([^"]+)"/).flatten
  end
  assignments.map do |value|
    value.delete_suffix(UUID_SOURCE_SUFFIX) if value.end_with?(UUID_SOURCE_SUFFIX)
  end.compact.uniq.sort
end

def verify_source_inventory(root_directory)
  discovered = source_suite_prefixes(root_directory)
  allowlisted = TEST_SUITE_PREFIXES.sort
  missing = discovered - allowlisted
  stale = allowlisted - discovered

  fail_guard("unreviewed UserDefaults suite prefixes: #{missing.join(', ')}") unless missing.empty?
  fail_guard("stale suite prefixes in cleanup allowlist: #{stale.join(', ')}") unless stale.empty?

  constructors = Dir[File.join(root_directory, "ChronicleTests", "*.swift")].sum do |path|
    File.read(path).scan(/UserDefaults\(suiteName:/).length
  end
  unless constructors == TEST_SUITE_CONSTRUCTOR_COUNT
    fail_guard("expected #{TEST_SUITE_CONSTRUCTOR_COUNT} suite constructors, found #{constructors}")
  end

  puts "test preferences guard: verified #{discovered.length} explicit ChronicleTests suite prefixes"
end

def run_guarded(root_directory, command)
  fail_guard("missing command after --") if command.empty?
  verify_source_inventory(root_directory)

  preferences_path = Pathname(File.join(Dir.home, "Library", "Preferences"))
  begin
    preferences_stat = preferences_path.lstat
  rescue SystemCallError => error
    fail_guard("preferences directory is unavailable: #{preferences_path} (#{error.class})")
  end
  unless preferences_stat.directory? && !preferences_stat.symlink?
    fail_guard("preferences directory must be a non-symlink directory: #{preferences_path}")
  end
  preferences_directory = preferences_path.realpath.to_s

  stale_count = cleanup_test_entries_until_stable(preferences_directory)
  assert_zero_test_preference_baseline(preferences_directory)
  puts "test preferences guard: pre-run baseline verified empty; removed #{stale_count} stale test-only domain(s)"

  system(*command)
  command_status = $CHILD_STATUS.exitstatus || 128 + $CHILD_STATUS.termsig

  # XCTest and its test host have exited. Repeated defaults deletion plus a stable-zero window
  # catches late cfprefsd writes instead of silently accepting or preserving them as baseline.
  removed_count = cleanup_test_entries_until_stable(preferences_directory)
  assert_zero_test_preference_baseline(preferences_directory)
  puts "test preferences guard: post-run cleanup verified stable zero; removed #{removed_count} test-only domain(s)"
  exit command_status
end

def self_test
  Dir.mktmpdir("chronicle-test-preferences-guard.") do |directory|
    existing = "chronicle-tests-telemetry-#{SecureRandom.uuid}.plist"
    removable = "chronicle-export-history-#{SecureRandom.uuid}.plist"
    unknown = "chronicle-tests-unreviewed-#{SecureRandom.uuid}.plist"
    product = "com.Chronicle.Chronicle.plist"
    File.binwrite(File.join(directory, existing), "existing")
    File.binwrite(File.join(directory, removable), "new")
    File.binwrite(File.join(directory, unknown), "unknown")
    File.binwrite(File.join(directory, product), "product")

    removed = cleanup_test_entries_until_stable(
      directory,
      use_defaults: false,
      attempts: 2,
      stable_passes_required: 1,
      interval_seconds: 0
    )
    fail_guard("self-test removed #{removed} files instead of exactly two") unless removed == 2
    fail_guard("self-test preserved a stale test preference") if File.exist?(File.join(directory, existing))
    fail_guard("self-test removed an unknown test-like preference") unless File.file?(File.join(directory, unknown))
    fail_guard("self-test touched the production preference domain") unless File.file?(File.join(directory, product))

    late = "chronicle-tests-window-title-#{SecureRandom.uuid}.plist"
    late_path = File.join(directory, late)
    writer = Thread.new do
      sleep 0.06
      File.binwrite(late_path, "late cfprefsd-style rewrite")
    end
    late_removed = cleanup_test_entries_until_stable(
      directory,
      use_defaults: false,
      attempts: 12,
      stable_passes_required: 3,
      interval_seconds: 0.05
    )
    writer.join
    fail_guard("self-test missed a late test preference rewrite") unless late_removed == 1
    fail_guard("self-test left the late test preference behind") if File.exist?(late_path)
  end

  puts "test preferences guard: self-test passed"
end

def main(arguments)
  mode = arguments.shift
  case mode
  when "verify-source"
    root = File.expand_path(arguments.shift || File.join(__dir__, "..", ".."))
    verify_source_inventory(root)
  when "run"
    root = File.expand_path(File.join(__dir__, "..", ".."))
    separator = arguments.index("--")
    fail_guard("usage: #{$PROGRAM_NAME} run -- command [arguments]") unless separator == 0
    arguments.shift
    run_guarded(root, arguments)
  when "self-test"
    self_test
  else
    fail_guard("usage: #{$PROGRAM_NAME} {verify-source [root]|run -- command [arguments]|self-test}")
  end
end

main(ARGV) if $PROGRAM_NAME == __FILE__
