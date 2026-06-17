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

section "Whitespace"
git diff --check

echo
echo "Release preflight checks passed."
