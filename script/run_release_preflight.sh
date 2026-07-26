#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

section() {
  printf '\n==> %s\n' "$1"
}

section "Release metadata"
ruby <<'RUBY'
project_path = "Chronicle.xcodeproj/project.pbxproj"
project = File.read(project_path)

versions = project.scan(/MARKETING_VERSION = ([^;]+);/).flatten.map(&:strip).uniq
builds = project.scan(/CURRENT_PROJECT_VERSION = ([^;]+);/).flatten.map(&:strip).uniq
abort "Expected one MARKETING_VERSION, found: #{versions.inspect}" unless versions.length == 1
abort "Expected one CURRENT_PROJECT_VERSION, found: #{builds.inspect}" unless builds.length == 1

version = versions.fetch(0)
build = builds.fetch(0)
release_tag = ENV.fetch("RELEASE_TAG", "").strip
expected_tag = "v#{version}"

unless release_tag.empty?
  valid_tag = /\A#{Regexp.escape(expected_tag)}(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?\z/
  abort "release tag #{release_tag} does not match app version #{version}" unless release_tag.match?(valid_tag)
end

documented_tag = release_tag.empty? ? expected_tag : release_tag
release_note_path = "docs/releases/#{documented_tag}.md"
abort "Missing release notes for #{documented_tag}: #{release_note_path}" unless File.file?(release_note_path)

release_note = File.read(release_note_path)
expected_note_fields = [
  "App version: `#{version}`",
  "Build: `#{build}`",
  "Artifact tag/version: `#{documented_tag}`"
]
missing_note_fields = expected_note_fields.reject { |field| release_note.include?(field) }
unless missing_note_fields.empty?
  abort "#{release_note_path} is inconsistent with the Xcode project: missing #{missing_note_fields.join(", ")}"
end

release_statuses = release_note.scan(/^Status:[ \t]*(.*?)[ \t]*$/).flatten
if ENV["REQUIRE_FINAL_RELEASE_NOTES"] == "1"
  unless release_statuses == ["Final"]
    abort "#{release_note_path} must contain exactly one `Status: Final` line; found #{release_statuses.inspect}"
  end
elsif release_statuses != ["Final"]
  warn "warning: #{release_note_path} is not final; expected exactly one `Status: Final` line, found #{release_statuses.inspect}"
end

readme = File.read("README.md")
source_version_line = "Current source version: `#{version}` (build `#{build}`)."
abort "README.md must contain: #{source_version_line}" unless readme.include?(source_version_line)

major = version.split(".").first
security = File.read("SECURITY.md")
supported_line = "Latest stable `#{major}.x` release"
abort "SECURITY.md must describe the supported #{major}.x release line" unless security.include?(supported_line)

puts "ok: source version #{version} (build #{build})"
puts "ok: release metadata matches #{release_note_path}"
puts "ok: README and SECURITY version statements match the Xcode project"
RUBY

section "Previous-release upgrade attestation"
UPGRADE_ATTESTATION_POINTER="${ROOT_DIR}/build/release-evidence/previous-release-upgrade-drill-latest-passed.path"
UPGRADE_ATTESTATION_PATH="${UPGRADE_DRILL_ATTESTATION_PATH:-}"
UPGRADE_ATTESTATION_ERROR=""
UPGRADE_ATTESTATION_VALID=0
RELEASE_NOTE_IS_FINAL="$({
  /usr/bin/ruby -e '
    project = File.read("Chronicle.xcodeproj/project.pbxproj")
    versions = project.scan(/MARKETING_VERSION = ([^;]+);/).flatten.map(&:strip).uniq
    abort "Expected one MARKETING_VERSION" unless versions.length == 1
    release_tag = ENV.fetch("RELEASE_TAG", "").strip
    documented_tag = release_tag.empty? ? "v#{versions.fetch(0)}" : release_tag
    note = File.read("docs/releases/#{documented_tag}.md")
    statuses = note.scan(/^Status:[ \t]*(.*?)[ \t]*$/).flatten
    puts(statuses == ["Final"] ? "1" : "0")
  '
} 2>/dev/null)"

if [[ -z "$UPGRADE_ATTESTATION_PATH" ]]; then
  if [[ -L "$UPGRADE_ATTESTATION_POINTER" || ( -e "$UPGRADE_ATTESTATION_POINTER" && ! -f "$UPGRADE_ATTESTATION_POINTER" ) ]]; then
    UPGRADE_ATTESTATION_ERROR="latest passed-attestation pointer is unsafe: ${UPGRADE_ATTESTATION_POINTER}"
  elif [[ -f "$UPGRADE_ATTESTATION_POINTER" ]]; then
    if ! UPGRADE_ATTESTATION_PATH="$(/usr/bin/ruby -e '
      require "pathname"
      pointer = Pathname(ARGV.fetch(0)).expand_path
      lines = pointer.readlines(chomp: true)
      abort "pointer must contain exactly one non-empty path" unless lines.length == 1 && !lines.fetch(0).strip.empty?
      value = lines.fetch(0)
      abort "pointer must contain only an attestation basename" unless File.basename(value) == value && !Pathname(value).absolute?
      puts pointer.dirname.join(value).expand_path
    ' "$UPGRADE_ATTESTATION_POINTER" 2>&1)"; then
      UPGRADE_ATTESTATION_ERROR="invalid passed-attestation pointer: ${UPGRADE_ATTESTATION_PATH}"
      UPGRADE_ATTESTATION_PATH=""
    fi
  else
    UPGRADE_ATTESTATION_ERROR="no passed upgrade-drill attestation pointer exists at ${UPGRADE_ATTESTATION_POINTER}"
  fi
fi

if [[ -n "$UPGRADE_ATTESTATION_PATH" ]]; then
  if UPGRADE_ATTESTATION_OUTPUT="$(
    /usr/bin/ruby script/support/verify_upgrade_drill_attestation.rb \
      "$ROOT_DIR" \
      "$UPGRADE_ATTESTATION_PATH" 2>&1
  )"; then
    UPGRADE_ATTESTATION_VALID=1
    printf '%s\n' "$UPGRADE_ATTESTATION_OUTPUT"
  else
    UPGRADE_ATTESTATION_ERROR="$UPGRADE_ATTESTATION_OUTPUT"
  fi
fi

if [[ "$UPGRADE_ATTESTATION_VALID" != "1" ]]; then
  if [[ "$RELEASE_NOTE_IS_FINAL" == "1" ]]; then
    echo "Final release notes require a current, passed previous-release upgrade attestation." >&2
    echo "$UPGRADE_ATTESTATION_ERROR" >&2
    exit 1
  fi
  echo "warning: NON-GATE Draft preflight has no current passed upgrade-drill attestation." >&2
  echo "warning: ${UPGRADE_ATTESTATION_ERROR}" >&2
else
  echo "ok: bounded source/Debug upgrade-drill evidence is bound to the current release inputs"
fi
echo "notice: the published-v1.0.5-DMG to signed-candidate clean-account exercise remains an external release gate"

section "Community and privacy files"
ruby <<'RUBY'
required_files = %w[
  README.md
  SECURITY.md
  CONTRIBUTING.md
  CODE_OF_CONDUCT.md
  docs/privacy-and-permissions.md
  docs/data-safety.md
  docs/migrations-and-upgrades.md
  docs/release-keys/README.md
  docs/stable-release-checklist.md
  docs/update-strategy.md
  Chronicle/Resources/ThirdPartyNotices.md
  Chronicle.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
  script/inspect_release_artifact.sh
  script/run_previous_release_upgrade_drill.sh
  script/run_release_analyze.sh
  script/run_release_dry_run.sh
  script/run_unit_tests.sh
  script/support/release_candidate_manifest.rb
  script/support/release_binding_manifest.rb
  script/support/release_source_fingerprint.rb
  script/support/test_preferences_guard.rb
  script/support/sqlcipher_upgrade_drill_inspector.c
  script/support/verify_clean_account_release_attestation.rb
  script/support/verify_release_dry_run_manifest.rb
  script/support/verify_upgrade_drill_attestation.rb
  script/test_release_guards.sh
]

missing_files = required_files.reject { |path| File.file?(path) }
abort "Missing required community/release files: #{missing_files.join(", ")}" unless missing_files.empty?

license_candidates = %w[LICENSE COPYING]
present_license_paths = license_candidates.select { |path| File.exist?(path) || File.symlink?(path) }
license_files = present_license_paths.select do |path|
  stat = File.lstat(path)
  stat.file? && !stat.symlink? && !File.read(path).strip.empty?
rescue SystemCallError
  false
end
invalid_license_paths = present_license_paths - license_files

unless invalid_license_paths.empty?
  message = "License path must be an exact, non-symlink, non-empty regular file: #{invalid_license_paths.join(", ")}"
  if ENV["REQUIRE_OPEN_SOURCE_LICENSE"] == "1"
    abort message
  end
  warn "warning: #{message}"
end

if license_files.empty?
  if ENV["REQUIRE_OPEN_SOURCE_LICENSE"] == "1"
    abort "A public open-source release requires an exact LICENSE or COPYING path that is a reviewed, non-symlink, non-empty regular file"
  end
  warn "warning: no valid exact LICENSE/COPYING file yet; dry-runs may continue, but public release is blocked"
else
  puts "ok: license file present (#{license_files.join(", ")})"
end

require "json"
notice_path = "Chronicle/Resources/ThirdPartyNotices.md"
notice_stat = File.lstat(notice_path)
unless notice_stat.file? && !notice_stat.symlink? && !File.read(notice_path).strip.empty?
  abort "Third-party notices must be a non-symlink, non-empty regular file: #{notice_path}"
end

resolved_path = "Chronicle.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
resolved = JSON.parse(File.read(resolved_path))
sqlcipher_pins = resolved.fetch("pins", []).select { |pin| pin["identity"] == "sqlcipher.swift" }
abort "Expected exactly one SQLCipher.swift package pin, found #{sqlcipher_pins.length}" unless sqlcipher_pins.length == 1
sqlcipher_version = sqlcipher_pins.fetch(0).dig("state", "version").to_s
abort "SQLCipher.swift package pin must use an exact semantic version" unless sqlcipher_version.match?(/\A\d+\.\d+\.\d+\z/)

notice = File.read(notice_path)
required_notice_patterns = [
  /`SQLCipher\.swift`\s+#{Regexp.escape(sqlcipher_version)}\./,
  /Copyright \(c\) 2025, ZETETIC LLC/,
  /Redistribution and use in source and binary forms/,
  /Redistributions in binary form must reproduce the above copyright notice/,
  /THIS SOFTWARE IS PROVIDED BY ZETETIC LLC "AS IS"/,
  /SQLite is in the public domain/
]
missing_notice_patterns = required_notice_patterns.reject { |pattern| notice.match?(pattern) }
unless missing_notice_patterns.empty?
  abort "#{notice_path} is incomplete for SQLCipher.swift #{sqlcipher_version}: missing #{missing_notice_patterns.map(&:inspect).join(", ")}"
end
puts "ok: reviewed SQLCipher.swift #{sqlcipher_version} third-party notices are present"

privacy_checks = {
  "README.md" => [/does not .*upload/i, /Activity data is stored locally/i],
  "SECURITY.md" => [/local-only privacy boundary/i],
  "docs/privacy-and-permissions.md" => [/does not sync or upload/i, /No remote telemetry/i],
  "docs/data-safety.md" => [/does not sync .* cloud services/i, /ordinary files outside Chronicle/i]
}

privacy_checks.each do |path, patterns|
  text = File.read(path)
  missing = patterns.reject { |pattern| text.match?(pattern) }
  abort "#{path} is missing required privacy declarations: #{missing.map(&:inspect).join(", ")}" unless missing.empty?
end

puts "ok: required community and release documents are present"
puts "ok: local-only, no-upload, telemetry, and export-boundary declarations are present"
RUBY

section "Runtime network surface"
ruby <<'RUBY'
network_api = /\b(URLSession|URLRequest|NWConnection|NWPathMonitor|CFHTTPMessage|SFSafariViewController)\b/
findings = Dir["Chronicle/**/*.swift"].sort.map do |path|
  matches = File.readlines(path).each_with_index.map do |line, index|
    "#{path}:#{index + 1}:#{line.strip}" if line.match?(network_api)
  end.compact
  matches unless matches.empty?
end.compact.flatten

unless findings.empty?
  warn findings.join("\n")
  abort "Runtime networking API found. Review it against Chronicle's activity-data offline boundary."
end

puts "ok: no in-process networking API found in Chronicle Swift sources"
RUBY

section "Shell script syntax"
while IFS= read -r script_path; do
  bash -n "$script_path"
  echo "ok: $script_path"
done < <(find script scripts -type f -name '*.sh' | sort)

section "GitHub workflow YAML"
ruby <<'RUBY'
require "yaml"

commit_pinned_action = /\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.\/-]+@[0-9a-f]{40}\z/
required_node24_actions = {
  "actions/checkout" => "3d3c42e5aac5ba805825da76410c181273ba90b1", # v7.0.1
  "actions/upload-artifact" => "043fb46d1a93c77aae656e7c1c64a875d1fc6a0a", # v7.0.1
  "actions/download-artifact" => "3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c", # v8.0.1
  "maxim-lobanov/setup-xcode" => "ed7a3b1fda3918c0306d1b724322adc0b8cc0a90" # v1.7.0
}

Dir[".github/workflows/*.{yml,yaml}"].sort.each do |path|
  workflow = YAML.load_file(path)
  workflow.fetch("jobs").each_value do |job|
    Array(job["steps"]).each do |step|
      uses = step["uses"]
      next if uses.nil?

      abort "#{path}: external action is not commit-pinned: #{uses}" unless uses.match?(commit_pinned_action)
      action, commit = uses.split("@", 2)
      expected = required_node24_actions[action]
      next if expected.nil?

      abort "#{path}: #{action} must use the reviewed Node 24 commit #{expected}" unless commit == expected
    end
  end
  puts "ok: #{path}"
end
RUBY

section "Localized strings"
plutil -lint Chronicle/en.lproj/Localizable.strings
plutil -lint Chronicle/zh-Hans.lproj/Localizable.strings

ruby <<'RUBY'
def localized_keys(path)
  File.read(path).scan(/^\s*"((?:\\.|[^"])*)"\s*=/).flatten
end

def duplicate_keys(keys)
  counts = Hash.new(0)
  keys.each { |key| counts[key] += 1 }
  counts.select { |_, count| count > 1 }.keys.sort
end

localizations = {
  "en" => "Chronicle/en.lproj/Localizable.strings",
  "zh-Hans" => "Chronicle/zh-Hans.lproj/Localizable.strings"
}

raw_key_sets = localizations.transform_values { |path| localized_keys(path) }
raw_key_sets.each do |locale, keys|
  duplicates = duplicate_keys(keys)
  next if duplicates.empty?

  puts "Duplicate localization keys found for #{locale}:"
  puts "  #{duplicates.join(", ")}"
  abort "Localized string keys must be unique within each supported language."
end
puts "ok: localized string keys are unique"

key_sets = raw_key_sets.transform_values { |keys| keys.uniq.sort }
reference_locale, reference_keys = key_sets.first
failed = false

key_sets.each do |locale, keys|
  missing = reference_keys - keys
  extra = keys - reference_keys
  next if missing.empty? && extra.empty?

  failed = true
  puts "Localization keys differ for #{locale} compared with #{reference_locale}:"
  puts "  missing: #{missing.join(", ")}" unless missing.empty?
  puts "  extra: #{extra.join(", ")}" unless extra.empty?
end

abort "Localized string keys must match across supported languages." if failed
puts "ok: localized string keys match"
RUBY

section "Shared Xcode schemes"
ruby <<'RUBY'
require "rexml/document"
require "rexml/xpath"

Dir["Chronicle.xcodeproj/xcshareddata/xcschemes/*.xcscheme"].sort.each do |path|
  document = REXML::Document.new(File.read(path))
  if File.basename(path) == "Chronicle.xcscheme"
    analyze_actions = REXML::XPath.match(document, "/Scheme/AnalyzeAction")
    unless analyze_actions.length == 1 && analyze_actions.fetch(0).attributes["buildConfiguration"] == "Release"
      abort "#{path} must contain exactly one Release AnalyzeAction"
    end
    chronicle_analyze_entries = REXML::XPath.match(
      document,
      "/Scheme/BuildAction/BuildActionEntries/BuildActionEntry"
    ).select do |entry|
      reference = entry.elements["BuildableReference"]
      reference && reference.attributes["BlueprintName"] == "Chronicle" &&
        reference.attributes["BuildableName"] == "Chronicle.app"
    end
    unless chronicle_analyze_entries.length == 1 &&
           chronicle_analyze_entries.fetch(0).attributes["buildForAnalyzing"] == "YES"
      abort "#{path} must analyze exactly the Chronicle app build entry"
    end
  end
  puts "ok: #{path}"
end
RUBY

section "Release validation wiring"
ruby <<'RUBY'
require "yaml"

analyze_path = "script/run_release_analyze.sh"
dry_run_path = "script/run_release_dry_run.sh"
verifier_path = "script/support/verify_release_dry_run_manifest.rb"
release_workflow_path = ".github/workflows/release.yml"
dry_run_workflow_path = ".github/workflows/release-dry-run.yml"

def unique_step(steps, label, &predicate)
  matches = steps.select(&predicate)
  abort "#{label} must exist exactly once" unless matches.length == 1
  matches.fetch(0)
end

def path_lines(step)
  step.fetch("with").fetch("path").lines.map(&:strip).reject(&:empty?)
end

analyze = File.read(analyze_path)
invocations = analyze.lines.select do |line|
  line.strip == '"$XCODEBUILD_BIN" "${XCODEBUILD_ARGS[@]}"'
end
abort "#{analyze_path} must execute its argv array exactly once" unless invocations.length == 1
unless analyze.scan(/^XCODEBUILD_ARGS=\($/).length == 1 &&
       analyze.scan(/^\s*XCODEBUILD_ARGS\+=\($/).length == 2 &&
       analyze.include?("CHRONICLE_RELEASE_ANALYZE_COMMAND") &&
       analyze.include?("chronicle_release_analyze_execution")
  abort "#{analyze_path} must build one canonical command and emit structured log/receipt evidence"
end

release = YAML.load_file(release_workflow_path)
abort "#{release_workflow_path} must default to contents: read" unless release.fetch("permissions") == { "contents" => "read" }
release_steps = release.fetch("jobs").fetch("build-dmg").fetch("steps")
analyze_step = unique_step(release_steps, "formal Release Analyze step") { |step| step["id"] == "release_analyze" }
expected_analyze_run = "RELEASE_ANALYZE_SOURCE_FINGERPRINT=\"$EXPECTED_SOURCE_FINGERPRINT\" \\\n  bash script/run_release_analyze.sh\n"
abort "formal Release Analyze must call the wrapper with the captured source fingerprint" unless analyze_step["run"] == expected_analyze_run
expected_analyze_env = {
  "RELEASE_ANALYZE_DERIVED_DATA_PATH" => "${{ github.workspace }}/build/release-analyze",
  "RELEASE_ANALYZE_LOG_PATH" => "${{ github.workspace }}/build/release-evidence/release-analyze.log",
  "RELEASE_ANALYZE_RECEIPT_PATH" => "${{ github.workspace }}/build/release-evidence/release-analyze.receipt.json"
}
abort "formal Release Analyze evidence paths changed" unless analyze_step["env"] == expected_analyze_env

expected_formal_evidence = %w[
  build/release-evidence/release-analyze.log
  build/release-evidence/release-analyze.receipt.json
]
passed_analyze = unique_step(release_steps, "passed Analyze artifact step") { |step| step["name"] == "Upload passed Release Analyze evidence" }
failed_analyze = unique_step(release_steps, "failed Analyze artifact step") { |step| step["name"] == "Upload failed Release Analyze diagnostics" }
abort "passed Analyze artifact condition changed" unless passed_analyze["if"] == "${{ !cancelled() && steps.release_analyze.outcome == 'success' }}"
abort "failed Analyze artifact condition changed" unless failed_analyze["if"] == "${{ !cancelled() && steps.release_analyze.outcome == 'failure' }}"
abort "passed Analyze artifact must contain exact log and receipt" unless path_lines(passed_analyze) == expected_formal_evidence
abort "failed Analyze artifact must contain exact log and receipt" unless path_lines(failed_analyze) == expected_formal_evidence

release_names = release_steps.map { |step| step["name"] }
stage_index = release_names.index("Stage exact release payload")
final_source_index = release_names.index("Verify source unchanged after release payload staging")
upload_index = release_names.index("Upload private workflow artifact")
unless stage_index && final_source_index && upload_index && stage_index < final_source_index && final_source_index < upload_index
  abort "formal release must re-check source after staging and before upload"
end

dry_run = File.read(dry_run_path)
unless dry_run.scan(/^\s+bash "\$RELEASE_ANALYZE_SCRIPT"$/).length == 1 &&
       dry_run.scan(/^\s+"schema_version" => 3,$/).length == 1 &&
       dry_run.include?('EVIDENCE_PATHS+=("$ANALYZE_LOG_PATH" "$ANALYZE_RECEIPT_PATH")')
  abort "#{dry_run_path} must invoke Analyze once and bind schema-3 log/receipt evidence"
end
if dry_run.include?("DRY_RUN_UNIT_RESULT_PATH") || dry_run.include?('"result_bundle" =>')
  abort "#{dry_run_path} must not put a runner-absolute XCTest result path in the portable manifest"
end

verifier = File.read(verifier_path)
unless verifier.include?("File::RDONLY | File::NOFOLLOW") &&
       verifier.include?("Release Analyze log command record does not match the receipt") &&
       verifier.include?("exact artifact directory changed during verification") &&
       verifier.include?("source.commit mismatch") &&
       verifier.include?("source.dirty mismatch") &&
       verifier.include?("release.app_version mismatch")
  abort "#{verifier_path} is missing FD identity, receipt, or before/after exact-directory verification"
end

dry_workflow = YAML.load_file(dry_run_workflow_path)
abort "#{dry_run_workflow_path} must default to contents: read" unless dry_workflow.fetch("permissions") == { "contents" => "read" }
dry_jobs = dry_workflow.fetch("jobs")
producer = dry_jobs.fetch("unsigned-release-dry-run")
expected_producer_outputs = {
  "artifact_id" => "${{ steps.upload_candidate.outputs.artifact-id }}"
}
unless producer.fetch("outputs") == expected_producer_outputs
  abort "dry-run producer outputs must expose only the exact uploaded artifact ID"
end
producer_steps = producer.fetch("steps")
dry_step = unique_step(producer_steps, "authoritative dry-run step") { |step| step["id"] == "dry_run" }
unless dry_step["run"] == "bash script/run_release_dry_run.sh" &&
       dry_step.fetch("env").slice("DRY_RUN_MODE", "DRY_RUN_SKIP_TESTS") == {
         "DRY_RUN_MODE" => "authoritative", "DRY_RUN_SKIP_TESTS" => "0"
       }
  abort "dry-run workflow must execute the authoritative driver"
end
upload = unique_step(producer_steps, "candidate dry-run upload") { |step| step["id"] == "upload_candidate" }
expected_upload_paths = %w[
  build/dry-run-upload/*.dmg
  build/dry-run-upload/*.dmg.sha256
  build/dry-run-upload/*.dry-run-manifest.json
  build/dry-run-upload/*.unit-test-summary.json
  build/dry-run-upload/*.release-analyze.log
  build/dry-run-upload/*.release-analyze.receipt.json
]
abort "candidate dry-run upload paths changed" unless path_lines(upload) == expected_upload_paths
abort "candidate dry-run upload must require producer success" unless upload["if"] == "${{ steps.dry_run.outcome == 'success' }}"

immutable = dry_jobs.fetch("verify-immutable-dry-run-artifact")
abort "immutable verification must depend on the producer" unless immutable["needs"] == "unsigned-release-dry-run"
immutable_steps = immutable.fetch("steps")
download = unique_step(immutable_steps, "immutable dry-run download") { |step| step["name"] == "Download immutable dry-run artifact by ID" }
expected_download_inputs = {
  "artifact-ids" => "${{ needs.unsigned-release-dry-run.outputs.artifact_id }}",
  "path" => "build/immutable-dry-run-evidence"
}
unless download.fetch("with") == expected_download_inputs
  abort "immutable dry-run verification must download the exact uploaded artifact ID"
end
remote_verify = unique_step(immutable_steps, "downloaded dry-run verification") { |step| step["name"] == "Re-verify downloaded exact payload" }
remote_run = remote_verify.fetch("run")
unless remote_run.scan("verify_release_dry_run_manifest.rb").length == 1 && remote_run.scan("--exact-files").length == 1
  abort "downloaded immutable dry-run payload must receive one exact manifest verification"
end
expected_remote_invocation = <<~'SHELL'
  ruby script/support/verify_release_dry_run_manifest.rb \
    "${manifests[0]}" \
    build/immutable-dry-run-evidence \
    "$fingerprint" \
    "$GITHUB_SHA" \
    "$expected_tag" \
    "$app_version" \
    "$app_build" \
    false \
    --exact-files
SHELL
unless remote_run.include?(expected_remote_invocation)
  abort "downloaded immutable dry-run verification must bind exact checkout and release metadata"
end

puts "ok: formal release and authoritative dry-run share universal Release Analyze"
puts "ok: dry-run schema-3 payload binds receipt/log evidence and is re-verified after immutable download"
RUBY

section "UI smoke test manifest"
ruby <<'RUBY'
script_path = "script/run_ui_smoke.sh"
test_path = "ChronicleUITests/ChronicleUITests.swift"

script = File.read(script_path)
manifest_tests = script.scan(%r{"ChronicleUITests/ChronicleUITests/(test[A-Za-z0-9_]+)"}).flatten.uniq.sort
abort "No UI smoke tests found in #{script_path}" if manifest_tests.empty?

test_source = File.read(test_path)
defined_tests = test_source.scan(/func\s+(test[A-Za-z0-9_]+)\s*\(/).flatten.uniq.sort
missing = manifest_tests - defined_tests

unless missing.empty?
  puts "UI smoke manifest names tests that are not defined in #{test_path}:"
  puts "  #{missing.join(", ")}"
  abort "UI smoke test manifest must only reference existing tests."
end

puts "ok: #{manifest_tests.length} UI smoke test references are defined"
RUBY

section "UI smoke surface coverage"
ruby <<'RUBY'
test_path = "ChronicleUITests/ChronicleUITests.swift"
test_source = File.read(test_path)
smoke_script = File.read("script/run_ui_smoke.sh")

required_present_identifiers = {
  "pending review navigation" => "dashboard.section.pendingReview",
  "timeline navigation" => "dashboard.section.timeline",
  "notes navigation" => "dashboard.section.notes",
  "insights navigation" => "dashboard.section.insights",
  "integrations navigation" => "dashboard.section.integrations",
  "pending review page" => "pendingReview.page",
  "work-block timeline page" => "timeline.workBlocks.page",
  "notes page" => "notes.page",
  "work-block insights page" => "insights.workBlocks.page",
  "integrations page" => "integrations.page",
  "integrations mode" => "integrations.mode",
  "integrations folder picker" => "integrations.chooseFolder",
  "integrations plaintext confirmation" => "integrations.plaintext.confirm",
  "integrations export-history search" => "integrations.history.search",
  "popover controller" => "popover.controller",
  "popover tracking state" => "popover.tracking",
  "popover current app" => "popover.currentApp",
  "popover pending review" => "popover.pendingReview",
  "popover pending review count" => "popover.pendingReview.count",
  "popover pending review action" => "popover.openPendingReview",
  "popover quick note action" => "popover.quickNote",
  "popover manual work action" => "popover.manualWork",
  "popover tracking action" => "popover.toggleTracking",
  "popover settings action" => "popover.openSettings",
  "dashboard pending review shortcut" => "dashboard.sidebar.pendingReview",
  "dashboard quick actions" => "dashboard.sidebar.quickActions",
  "dashboard quick note shortcut" => "dashboard.sidebar.quickNote",
  "dashboard manual work shortcut" => "dashboard.sidebar.manualWork",
  "onboarding value page" => "onboarding.page.value",
  "onboarding value truth" => "onboarding.value.truth",
  "onboarding value flow" => "onboarding.value.flow",
  "onboarding privacy page" => "onboarding.page.privacy",
  "onboarding app-level privacy" => "onboarding.privacy.appLevel",
  "onboarding allowlist privacy" => "onboarding.privacy.allowlist",
  "onboarding safety privacy" => "onboarding.privacy.safety",
  "onboarding ready page" => "onboarding.page.ready",
  "onboarding menu bar readiness" => "onboarding.ready.menuBar",
  "onboarding pending review readiness" => "onboarding.ready.pendingReview",
  "onboarding capture readiness" => "onboarding.ready.capture",
  "onboarding reminder readiness" => "onboarding.ready.reminders",
  "onboarding deferred exports" => "onboarding.ready.exportsLater",
  "onboarding value step" => "onboarding.step.value",
  "onboarding privacy step" => "onboarding.step.privacy",
  "onboarding ready step" => "onboarding.step.ready",
  "onboarding value next action" => "onboarding.next.value",
  "onboarding privacy next action" => "onboarding.next.privacy",
  "onboarding finish action" => "onboarding.finish"
}

required_absent_identifiers = {
  "retired popover command center" => "popover.commandCenter",
  "retired overview navigation" => "dashboard.section.overview",
  "retired markers navigation" => "dashboard.section.markers",
  "retired stats navigation" => "dashboard.section.stats",
  "retired reports navigation" => "dashboard.section.reports",
  "retired preferences export section" => "preferences.section.export",
  "retired onboarding export step" => "onboarding.step.exports"
}

missing = required_present_identifiers.reject do |_, identifier|
  test_source.include?(%("#{identifier}"))
end

unless missing.empty?
  puts "UI smoke tests must assert the key release surfaces:"
  missing.each do |label, identifier|
    puts "  #{label}: #{identifier}"
  end
  abort "Key release surfaces need UI smoke coverage before release."
end

missing_absence_checks = required_absent_identifiers.reject do |_, identifier|
  test_source.match?(/XCTAssertFalse\([^\n]*"#{Regexp.escape(identifier)}"[^\n]*\.exists/)
end

unless missing_absence_checks.empty?
  puts "UI smoke tests must assert removed toy surfaces stay removed:"
  missing_absence_checks.each do |label, identifier|
    puts "  #{label}: #{identifier}"
  end
  abort "Retired navigation surfaces need UI smoke absence checks before release."
end

required_bilingual_commands = [
  'run_case en full "${PUBLIC_TESTS_EN[@]}" "${SURFACE_TESTS[@]}"',
  'run_case zh-Hans full "${PUBLIC_TESTS_ZH_HANS[@]}" "${SURFACE_TESTS[@]}"',
  'run_case en surface "${SURFACE_TESTS[@]}"',
  'run_case zh-Hans surface "${SURFACE_TESTS[@]}"'
]
missing_bilingual_commands = required_bilingual_commands.reject { |command| smoke_script.include?(command) }
unless missing_bilingual_commands.empty?
  abort "UI smoke must execute the release surfaces in both languages; missing #{missing_bilingual_commands.inspect}"
end
unless smoke_script.include?('env CHRONICLE_UI_SMOKE_LANGUAGE="$language"')
  abort "UI smoke must pass its selected language into the XCTest process."
end
unless smoke_script.include?('-testLanguage "$language"')
  abort "UI smoke must also set XCTest's selected language explicitly."
end

surface_block = smoke_script[/SURFACE_TESTS=\((.*?)\n\)/m, 1].to_s
surface_test_names = surface_block.scan(%r{ChronicleUITests/ChronicleUITests/(test[A-Za-z0-9_]+)}).flatten.uniq
abort "No release surface tests found in SURFACE_TESTS." if surface_test_names.empty?

test_starts = test_source.enum_for(:scan, /^    func (test[A-Za-z0-9_]+)\(\) throws \{/).map do
  match = Regexp.last_match
  [match[1], match.begin(0)]
end
test_bodies = test_starts.each_with_index.to_h do |(name, offset), index|
  next_offset = test_starts[index + 1]&.fetch(1) || test_source.length
  [name, test_source[offset...next_offset]]
end
unparameterized_surfaces = surface_test_names.reject do |name|
  body = test_bodies[name].to_s
  body.include?("makeWorkspace(language: surfaceLanguage)") && body.include?("language: surfaceLanguage")
end
unless unparameterized_surfaces.empty?
  abort "Release surface tests must launch through the bilingual surfaceLanguage path: #{unparameterized_surfaces.join(", ")}"
end
unless test_source.include?('ProcessInfo.processInfo.environment["CHRONICLE_UI_SMOKE_LANGUAGE"]')
  abort "UI surface tests do not consume CHRONICLE_UI_SMOKE_LANGUAGE."
end
unless test_source.include?('Locale.preferredLanguages.first?.hasPrefix("zh-Hans")')
  abort "UI surface tests need an XCTest-language fallback for isolated runners."
end
unless test_source.include?('dashboardApp.textFields["timeline.workBlocks.search"]')
  abort "The bilingual public path must assert the current work-block Timeline surface."
end

puts "ok: #{required_present_identifiers.length} key release surfaces are covered by UI smoke assertions"
puts "ok: #{required_absent_identifiers.length} retired navigation surfaces have absence checks"
puts "ok: #{surface_test_names.length} release surface tests are configured for both English and Simplified Chinese"
RUBY

section "Release note freshness"
ruby <<'RUBY'
require "open3"

draft_notes = Dir["docs/releases/v*-rc*.md"].sort.select do |path|
  File.read(path).match?(/^Status:\s*Draft\b/)
end

if draft_notes.empty?
  puts "ok: no draft RC release notes found"
  exit
end

draft_notes.each do |release_note|
  text = File.read(release_note)
  tag = text[/^Artifact tag\/version:\s*`([^`]+)`/, 1]
  abort "#{release_note} must declare an artifact tag/version." if tag.nil? || tag.empty?

  distance_match = text.match(/Local development has moved\s+(\d+)\s+commits past `([^`]+)`/)
  abort "#{release_note} must include the current commit distance from its previous public tag." unless distance_match

  documented_count = distance_match[1].to_i
  base_tag = distance_match[2]
  unless base_tag.match?(/\Av\d+\.\d+\.\d+(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?\z/)
    abort "#{release_note} previous public tag is not a safe semantic-version tag: #{base_tag.inspect}"
  end

  if system("git", "rev-parse", "--is-shallow-repository", out: File::NULL, err: File::NULL)
    shallow = `git rev-parse --is-shallow-repository`.strip == "true"
    if shallow
      system("git", "fetch", "--force", "--quiet", "--tags", "--unshallow", "origin", out: File::NULL, err: File::NULL)
    end
  end

  unless system("git", "rev-parse", "--verify", "#{base_tag}^{commit}", out: File::NULL, err: File::NULL)
    system("git", "fetch", "--force", "--quiet", "origin", "tag", base_tag, out: File::NULL, err: File::NULL)
  end

  unless system("git", "rev-parse", "--verify", "#{base_tag}^{commit}", out: File::NULL, err: File::NULL)
    abort "Cannot verify #{release_note} freshness because #{base_tag} does not exist."
  end

  count_output, count_error, count_status = Open3.capture3(
    "git", "rev-list", "#{base_tag}..HEAD", "--count"
  )
  unless count_status.success? && count_output.strip.match?(/\A\d+\z/)
    abort "Could not count #{release_note} distance from #{base_tag}: #{count_error.strip}"
  end
  actual_count = Integer(count_output.strip, 10)
  lag = actual_count - documented_count

  if documented_count > actual_count
    abort "#{release_note} documents #{documented_count} commits past #{base_tag}, but the current branch has #{actual_count}."
  end

  if lag > 1
    abort "#{release_note} is stale: it documents #{documented_count} commits past #{base_tag}, current branch has #{actual_count}."
  end

  puts "ok: #{release_note} commit distance is current for #{tag}"
end
RUBY

section "Whitespace"
git diff --check

echo
echo "Release preflight checks passed."
