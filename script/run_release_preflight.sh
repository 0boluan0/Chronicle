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
