#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

if [[ -n "${RELEASE_TAG:-}" ]]; then
  APP_VERSION="$(awk -F ' = ' '/MARKETING_VERSION = / { gsub(/;/, "", $2); print $2 }' Chronicle.xcodeproj/project.pbxproj | sort -u)"
  if [[ "$RELEASE_TAG" != "v${APP_VERSION}" ]]; then
    echo "release tag ${RELEASE_TAG} does not match app version ${APP_VERSION}" >&2
    exit 1
  fi
fi

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

section "UI smoke surface coverage"
ruby <<'RUBY'
test_path = "ChronicleUITests/ChronicleUITests.swift"
test_source = File.read(test_path)

required_present_identifiers = {
  "popover daily snapshot" => "popover.commandCenter",
  "popover dashboard entry" => "popover.openDashboard",
  "quick marker workspace" => "quickMarker.workspace",
  "dashboard overview summary" => "dashboard.overview.reviewBrief",
  "dashboard timeline navigation" => "dashboard.section.timeline",
  "dashboard reports navigation" => "dashboard.section.reports",
  "reports folder picker" => "reports.closeout.chooseDailyFolder"
}

required_absent_identifiers = {
  "quick marker reuse path" => "quickMarker.recentEmpty.path",
  "quick marker header progress" => "quickMarker.headerProgress",
  "quick marker header status pill" => "quickMarker.headerStatus",
  "quick marker composer mode status" => "quickMarker.composerModeStatus",
  "quick marker outcome strip" => "quickMarker.outcome",
  "quick marker review loop" => "quickMarker.reviewLoop",
  "quick marker next steps heading" => "Next steps",
  "dashboard sidebar flow path" => "dashboard.sidebar.flowPath",
  "app mappings empty path" => "appMappings.emptyPath",
  "dashboard overview activity map empty path" => "dashboard.overview.activityMap.emptyPath",
  "dashboard overview selection empty path" => "dashboard.overview.selection.emptyPath",
  "dashboard overview daily chart empty path" => "overview.dailyChart.emptyPath",
  "dashboard overview weekly chart empty path" => "overview.weeklyChart.emptyPath",
  "dashboard overview suggested next" => "dashboard.overview.suggestedNext",
  "dashboard overview suggested next copy" => "Suggested next",
  "dashboard overview readiness strip" => "dashboard.overview.readiness",
  "dashboard timeline next-action card" => "dashboard.timeline.nextAction",
  "dashboard timeline start-here panel" => "dashboard.timeline.startHere",
  "dashboard timeline empty path" => "dashboard.timeline.emptyPath",
  "dashboard timeline filter guide" => "dashboard.timeline.filterGuide",
  "dashboard timeline batch empty filter step" => "dashboard.timeline.batchEmpty.filter",
  "dashboard timeline batch empty select step" => "dashboard.timeline.batchEmpty.select",
  "dashboard timeline batch empty apply step" => "dashboard.timeline.batchEmpty.apply",
  "standalone timeline next-action card" => "timeline.nextAction",
  "tag picker no-tags path" => "tag.picker.noTags.path",
  "dashboard markers next-action card" => "dashboard.markers.nextAction",
  "markers review path" => "markers.review.path",
  "markers timeline empty prompts" => "markers.timeline.emptyPrompts",
  "reports closeout next-action card" => "reports.closeout.nextAction",
  "reports closeout included cards" => "reports.closeout.include",
  "reports workspace next-action text" => "reports.workspace.nextAction",
  "reports weekly next-action card" => "reports.dashboardWeekly.nextAction",
  "reports readiness next-action card" => "reports.readiness.nextAction",
  "reports csv guidance strip" => "reports.csv.guidance",
  "reports csv guidance next-action card" => "reports.csv.guidance.nextAction",
  "reports preview loading path" => "reports.preview.loadingPath",
  "reports preview empty path" => "reports.preview.emptyPath",
  "onboarding header progress card" => "onboarding.header.progress",
  "onboarding numeric step counter" => "Step 1 of 4",
  "onboarding progress status" => "In progress",
  "onboarding final step status" => "Final step",
  "onboarding rail focus label" => "Setup focus",
  "onboarding finish checklist" => "onboarding.finishChecklist",
  "self check readiness impact" => "selfCheck.readiness.impact",
  "self check next-action card" => "selfCheck.readiness.nextAction",
  "self check readiness path" => "selfCheck.readiness.path",
  "self check action guidance" => "Start with the current state",
  "dashboard stats next-step card" => "dashboard.stats.nextStep",
  "dashboard stats data quality evidence chain" => "dashboard.stats.dataQuality.evidenceChain",
  "dashboard stats app empty path" => "dashboard.stats.appFocus.emptyPath",
  "dashboard stats tag empty path" => "dashboard.stats.tagFocus.emptyPath",
  "standalone stats next-step card" => "stats.review.nextStep",
  "standalone stats app empty path" => "stats.topApps.emptyPath",
  "standalone stats tag empty path" => "stats.topTags.emptyPath",
  "standalone stats markers empty path" => "stats.markers.emptyPath",
  "standalone stats deep work empty path" => "stats.deepWork.emptyPath",
  "popover header progress" => "popover.headerProgress",
  "popover next step heading" => "Next Step",
  "popover command center progress card" => "popover.commandCenter.progress",
  "popover daily snapshot empty path" => "popover.dailySnapshot.emptyPath",
  "popover daily snapshot saved guidance action" => "popover.dailySnapshot.guidance.openFolder",
  "popover daily snapshot ready guidance action" => "popover.dailySnapshot.guidance.exportDaily",
  "popover daily snapshot context guidance action" => "popover.dailySnapshot.guidance.addNote",
  "popover daily snapshot building guidance action" => "popover.dailySnapshot.guidance.reviewTimeline",
  "settings sidebar flow header" => "preferences.sidebar.flowHeader",
  "settings sidebar guide" => "preferences.sidebar.guide.focus",
  "settings readiness start step" => "preferences.readiness.start",
  "settings readiness timeline step" => "preferences.readiness.timeline",
  "settings readiness recall step" => "preferences.readiness.recall",
  "settings window title empty path" => "preferences.windowTitles.blocklistEmptyPath",
  "settings advanced tracking empty path" => "preferences.advancedTracking.allowlistEmptyPath",
  "settings capture profile guidance" => "preferences.captureProfiles.guidance",
  "privacy next-step header" => "privacy.next.header",
  "privacy next-step reason" => "privacy.next.reason",
  "privacy capture outcome strip" => "privacy.capture.outcome",
  "privacy sharing checklist heading" => "Reviewable local files",
  "tags rules outcome strip" => "tagsRules.outcomeStrip",
  "tags setup guide" => "tags.setup.header",
  "tags empty path" => "tags.empty.path",
  "app mappings impact strip" => "appMappings.impactStrip",
  "tag wizard outcome strip" => "wizard.outcomeStrip",
  "tag wizard empty path" => "wizard.emptyPath",
  "tag wizard loading path" => "wizard.loadingPath",
  "reports reminder outcome strip" => "reports.reviewReminder.outcome",
  "reports closeout steps" => "reports.closeout.steps"
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
  abort "Removed guidance surfaces need UI smoke absence checks before release."
end

puts "ok: #{required_present_identifiers.length} key release surfaces are covered by UI smoke assertions"
puts "ok: #{required_absent_identifiers.length} removed guidance surfaces have absence checks"
RUBY

section "Release note freshness"
ruby <<'RUBY'
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

  actual_count = `git rev-list #{base_tag}..HEAD --count`.to_i
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
