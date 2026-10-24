#!/usr/bin/env ruby
# Fail early if the Codemagic Ruby/Psych environment cannot load the YAML
# anchors used by PP-OCRv6 inference.yml. No model download is needed.
require "yaml"
require "tempfile"

fixture = <<~YAML
  base: &paddle_characters
    - 日
    - 本
    - A
  PostProcess:
    character_dict: *paddle_characters
YAML

Tempfile.create(["paddle-alias-smoke", ".yml"]) do |file|
  file.write(fixture)
  file.flush
  parsed = YAML.safe_load_file(file.path, aliases: true)
  actual = parsed.fetch("PostProcess").fetch("character_dict")
  raise "YAML alias resolution mismatch" unless actual == ["日", "本", "A"]
end

begin
  YAML.safe_load("payload: !ruby/object:Object {}\n", aliases: true)
  raise "Unsafe Ruby object tag was accepted"
rescue Psych::DisallowedClass
  # Good: aliases can be resolved without allowing object deserialization.
end
puts "PASS: Paddle YAML aliases work with safe loading and reject Ruby objects"
