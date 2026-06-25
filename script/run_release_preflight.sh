#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

section() {
  printf '\n==> %s\n' "$1"
}

section "Shell script syntax"
while IFS= read -r script_path; do
  bash -n "$script_path"
  echo "ok: $script_path"
done < <(find script scripts -type f -name '*.sh' | sort)

section "GitHub workflow YAML"
ruby <<'RUBY'
require "yaml"

Dir[".github/workflows/*.{yml,yaml}"].sort.each do |path|
  YAML.load_file(path)
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

Dir["Chronicle.xcodeproj/xcshareddata/xcschemes/*.xcscheme"].sort.each do |path|
  REXML::Document.new(File.read(path))
  puts "ok: #{path}"
end
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

section "Release note freshness"
ruby <<'RUBY'
release_note = "docs/releases/v0.1.0-rc2.md"
base_tag = "v0.1.0-rc1"

unless File.exist?(release_note)
  puts "ok: #{release_note} is not present"
  exit
end

unless system("git", "rev-parse", "--verify", "#{base_tag}^{commit}", out: File::NULL, err: File::NULL)
  abort "Cannot verify release note freshness because #{base_tag} does not exist."
end

text = File.read(release_note)
match = text.match(/Local development has moved\s+(\d+)\s+commits past `#{Regexp.escape(base_tag)}`/)
abort "#{release_note} must include the current commit distance from #{base_tag}." unless match

documented_count = match[1].to_i
actual_count = `git rev-list #{base_tag}..HEAD --count`.to_i
lag = actual_count - documented_count

if documented_count > actual_count
  abort "#{release_note} documents #{documented_count} commits past #{base_tag}, but the current branch has #{actual_count}."
end

if lag > 1
  abort "#{release_note} is stale: it documents #{documented_count} commits past #{base_tag}, current branch has #{actual_count}."
end

puts "ok: #{release_note} commit distance is current"
RUBY

section "Whitespace"
git diff --check

echo
echo "Release preflight checks passed."
