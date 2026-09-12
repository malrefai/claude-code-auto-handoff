# frozen_string_literal: true

require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'lib' << 'test'
  t.test_files = FileList['test/**/*_test.rb']
  t.warning = true
  t.verbose = false
end

desc 'Check every Ruby file parses cleanly with warnings enabled'
task :lint do
  files = FileList['bin/cld', 'lib/**/*.rb', 'test/**/*.rb']
  failed = files.reject { |f| system(RbConfig.ruby, '-w', '-c', f, out: File::NULL) }
  abort "syntax errors in: #{failed.join(', ')}" unless failed.empty?
  puts "#{files.length} files OK"
end

desc 'Print the sha256 and url to paste into the Homebrew formula for a tag'
task :build, [:version] do |_t, args|
  version = args[:version] or abort 'usage: rake build[0.1.0]'
  url = "https://github.com/malrefai/claude-code-auto-handoff/archive/refs/tags/v#{version}.tar.gz"
  puts "url    #{url}"
  puts
  puts 'Generate the checksum after pushing the tag:'
  puts "  curl -sL #{url} | shasum -a 256"
end

task default: %i[lint test]
