#!/usr/bin/env ruby

require "json"

path = ARGV.fetch(0)
content = File.read(path)
data = begin
  JSON.parse(content)
rescue JSON::ParserError
  _, report = content.split("\n", 2)
  JSON.parse(report || content)
end
images = Array(data["usedImages"])

image_name = lambda do |index|
  image = images[index.to_i] || {}
  image["name"] || File.basename(image["path"].to_s)
end

puts "process: #{data["procName"] || data["processName"]}"
puts "exception: #{data["exception"].inspect}"
puts "termination: #{data["termination"].inspect}"

threads = Array(data["threads"])
faulting = data["faultingThread"] || data["crashedThread"] || data["triggeredThread"]
faulting ||= threads.index { |thread| thread["triggered"] || thread["crashed"] } || 0
puts "faultingThread: #{faulting}"

thread = threads[faulting.to_i] || {}
puts "threadName: #{thread["name"]}" if thread["name"]
Array(thread["frames"]).first(60).each_with_index do |frame, index|
  symbol = frame["symbol"] || frame["symbolication"] || "<unknown>"
  location = frame["symbolLocation"] || frame["imageOffset"]
  puts "%02d %-36s %s + %s" % [index, image_name.call(frame["imageIndex"]), symbol, location]
end

puts "threadSummary:"
threads.each_with_index do |item, index|
  frame = Array(item["frames"]).first || {}
  symbol = frame["symbol"] || "<no frames>"
  puts "%02d %-24s %s" % [index, item["name"].to_s, symbol]
end
