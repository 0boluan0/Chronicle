#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "open3"
require "pathname"

RELEASE_INPUT_ROOTS = %w[
  .github
  Chronicle.xcodeproj
  Chronicle
  ChronicleTests
  ChronicleUITests
  docs
  script
  scripts
].freeze

TOP_LEVEL_RELEASE_INPUT_PREFIXES = %w[
  README
  SECURITY
  CONTRIBUTING
  CODE_OF_CONDUCT
  CONTEXT
  CLAUDE
  UI-design
  LICENSE
  COPYING
].freeze

def fail_fingerprint(message)
  warn "release source fingerprint: #{message}"
  exit 1
end

def release_untracked_input?(relative)
  return true if RELEASE_INPUT_ROOTS.any? { |root| relative == root || relative.start_with?("#{root}/") }
  return false if relative.include?("/")
  return true if relative == ".gitignore"

  TOP_LEVEL_RELEASE_INPUT_PREFIXES.any? do |prefix|
    relative == prefix || relative.match?(/\A#{Regexp.escape(prefix)}[._-]/)
  end
end

def safe_ignored_synchronized_output?(relative)
  # Chronicle is an Xcode filesystem-synchronized source root, so ignored files
  # under it are inputs unless they are known Finder metadata. Top-level build/
  # and dist/ outputs are outside this query and remain safely excluded.
  relative == "Chronicle/.DS_Store" || relative.end_with?("/.DS_Store")
end

def git_capture(root, *arguments)
  output, error, status = Open3.capture3("git", "-C", root.to_s, *arguments)
  fail_fingerprint("git #{arguments.join(' ')} failed: #{error.strip}") unless status.success?
  output
end

def git_diff_dirty?(root, *arguments)
  _output, error, status = Open3.capture3("git", "-C", root.to_s, "diff", "--quiet", *arguments)
  return false if status.exitstatus == 0
  return true if status.exitstatus == 1

  fail_fingerprint("git diff --quiet #{arguments.join(' ')} failed: #{error.strip}")
end

root = Pathname(ARGV.fetch(0, File.expand_path("../..", __dir__))).expand_path
fail_fingerprint("source root is not a directory: #{root}") unless root.directory?

head = git_capture(root, "rev-parse", "HEAD").strip
fail_fingerprint("HEAD is not a full commit object ID") unless head.match?(/\A[0-9a-f]{40,64}\z/)

tracked = git_capture(root, "ls-files", "-z", "--cached").split("\0", -1).reject(&:empty?)
untracked = git_capture(root, "ls-files", "-z", "--others", "--exclude-standard")
  .split("\0", -1)
  .reject(&:empty?)
  .select { |relative| release_untracked_input?(relative) }
ignored_synchronized = git_capture(
  root, "ls-files", "-z", "--others", "--ignored", "--exclude-standard", "--", "Chronicle"
).split("\0", -1)
  .reject(&:empty?)
  .reject { |relative| safe_ignored_synchronized_output?(relative) }

if ARGV[1] == "--dirty"
  dirty = git_diff_dirty?(root) || git_diff_dirty?(root, "--cached") ||
    !untracked.empty? || !ignored_synchronized.empty?
  puts dirty
  exit 0
elsif ARGV.length > 1
  fail_fingerprint("usage: release_source_fingerprint.rb [source-root] [--dirty]")
end

paths = tracked + untracked + ignored_synchronized
fail_fingerprint("git returned duplicate release input paths") unless paths.uniq.length == paths.length

digest = Digest::SHA256.new
digest << "chronicle-release-source-fingerprint-v1\0"
digest << "head\0#{head}\0"

paths.sort.each do |relative|
  fail_fingerprint("git returned an absolute release input: #{relative}") if Pathname(relative).absolute?

  path = root.join(relative)
  digest << "path\0#{relative.b}\0"
  begin
    stat = path.lstat
  rescue Errno::ENOENT
    digest << "missing\0"
    next
  end

  if stat.symlink?
    digest << "symlink\0"
    digest << path.readlink.to_s.b
    digest << "\0"
  elsif stat.file?
    executable = (stat.mode & 0o111).zero? ? "-" : "x"
    digest << "file\0#{executable}\0#{stat.size}\0"
    File.open(path, "rb") do |file|
      buffer = String.new(capacity: 1024 * 1024, encoding: Encoding::BINARY)
      digest << buffer while file.read(1024 * 1024, buffer)
    end
    digest << "\0"
  else
    fail_fingerprint("release input is not a regular file or symlink: #{relative}")
  end
end

puts digest.hexdigest
