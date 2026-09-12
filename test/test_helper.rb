# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'open3'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'claude_handoff'

module HandoffTest
  REPO_ROOT = File.expand_path('..', __dir__)
  EXE = File.join(REPO_ROOT, 'bin', 'cld')

  # Sandboxes every path the tool touches, so a test run can never read or
  # write the developer's real ~/.claude.
  module Sandbox
    attr_reader :sandbox, :state_root, :project, :stub_log, :settings_path

    def setup
      super
      # realpath matters on macOS: $TMPDIR lives under /var, a symlink to
      # /private/var, and the tool keys its state off the resolved path.
      @sandbox = File.realpath(Dir.mktmpdir('claude-handoff-test'))
      @state_root = File.join(@sandbox, 'state')
      @project = File.join(@sandbox, 'project')
      @bin = File.join(@sandbox, 'bin')
      @stub_log = File.join(@sandbox, 'claude-argv.log')
      @settings_path = File.join(@sandbox, 'settings.json')

      FileUtils.mkdir_p([@state_root, @project, @bin])
      write_claude_stub

      # In-process tests would otherwise inherit $PROGRAM_NAME from the test
      # runner, which is rake's loader, not this tool.
      ClaudeHandoff.program_path = EXE
    end

    def teardown
      FileUtils.remove_entry(@sandbox) if @sandbox && File.directory?(@sandbox)
      super
    end

    def store_for(dir = project)
      ClaudeHandoff::StateStore.new(dir, root: state_root)
    end

    def config(overrides = {})
      ClaudeHandoff::Config.new(overrides, state_dir: state_root)
    end

    # A stand-in for the Claude Code binary. Records how it was invoked and,
    # when told to, plants a rate-limit sample exactly as the real statusline
    # sidecar would during a session.
    def write_claude_stub
      path = File.join(@bin, 'claude')
      File.write(path, <<~RUBY)
        #!/usr/bin/env ruby
        require "json"
        require "fileutils"
        File.open(ENV.fetch("CLAUDE_STUB_ARGV_LOG"), "a") { |f| f.puts(ARGV.inspect) }
        if (sample = ENV["CLAUDE_STUB_SAMPLE_PATH"])
          FileUtils.mkdir_p(File.dirname(sample))
          File.write(sample, ENV.fetch("CLAUDE_STUB_SAMPLE_JSON"))
        end
        exit Integer(ENV.fetch("CLAUDE_STUB_EXIT", "0"))
      RUBY
      FileUtils.chmod(0o755, path)
      path
    end

    def stub_argv
      return [] unless File.file?(stub_log)

      File.readlines(stub_log).map(&:strip).reject(&:empty?)
    end

    # Builds the JSON the stub will plant as a recorded sample.
    def sample_json(five_hour: nil, seven_day: nil, recorded_at: Time.now.to_i,
                    session_id: 'sess-1', transcript_path: '/nonexistent',
                    project_dir: nil)
      windows = []
      windows << window('five_hour', *five_hour) if five_hour
      windows << window('seven_day', *seven_day) if seven_day

      JSON.generate({
                      'windows' => windows,
                      'session_id' => session_id,
                      'transcript_path' => transcript_path,
                      'project_dir' => project_dir || project,
                      'recorded_at' => recorded_at
                    })
    end

    def window(name, used, resets_at)
      { 'name' => name, 'used_percentage' => used, 'resets_at' => resets_at }
    end

    # Runs the real executable in a subprocess with a fully sandboxed
    # environment. This is how the integration tests exercise `run`.
    def run_cli(*args, env: {}, chdir: project)
      full_env = {
        'PATH' => "#{@bin}:#{ENV.fetch('PATH', '')}",
        'HOME' => sandbox,
        'CLAUDE_HANDOFF_HOME' => state_root,
        'CLAUDE_HANDOFF_SETTINGS_PATH' => settings_path,
        'CLAUDE_STUB_ARGV_LOG' => stub_log,
        'CLAUDE_HANDOFF_DISABLE_LAUNCHD' => '1'
      }.merge(env)

      stdout, stderr, status = Open3.capture3(full_env, RbConfig.ruby, EXE, *args, chdir: chdir)
      [stdout, stderr, status.exitstatus]
    end

    def write_transcript(records, name: 'transcript.jsonl')
      path = File.join(sandbox, name)
      File.write(path, records.map { |r| JSON.generate(r) }.join("\n"))
      path
    end

    def user_record(text, sidechain: false)
      { 'type' => 'user', 'isSidechain' => sidechain,
        'message' => { 'role' => 'user', 'content' => text } }
    end

    def assistant_record(text, sidechain: false, tool: false)
      content = [{ 'type' => 'text', 'text' => text }]
      content << { 'type' => 'tool_use', 'name' => 'Edit', 'input' => {} } if tool
      { 'type' => 'assistant', 'isSidechain' => sidechain,
        'message' => { 'role' => 'assistant', 'content' => content } }
    end
  end
end
