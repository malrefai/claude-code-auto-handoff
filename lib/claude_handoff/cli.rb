# frozen_string_literal: true

require 'optparse'
require 'time'

module ClaudeHandoff
  # Works out which command the user meant and runs it.
  #
  # `cld` stands in for `claude`, so the dispatch rule is: a recognised
  # subcommand runs here, and everything else launches Claude Code with the
  # arguments untouched.
  class CLI
    include Arguments

    # `cld` stands in for `claude`, so anything that is not one of these is
    # passed straight through to Claude Code.
    COMMANDS = %w[run status cancel resume-now install uninstall statusline version help].freeze

    # Hidden: what a scheduled job re-invokes.
    SCHEDULED_COMMAND = '__run-scheduled'

    def initialize(out: $stdout, err: $stderr, stdin: $stdin)
      @out = out
      @err = err
      @stdin = stdin
    end

    def run(argv)
      command, rest = dispatch(argv)

      case command
      when 'run' then cmd_run(rest)
      when 'statusline' then cmd_statusline
      when 'status' then cmd_status(rest)
      when 'cancel' then cmd_cancel(rest)
      when 'resume-now' then cmd_resume_now(rest)
      when 'install' then cmd_install(rest)
      when 'uninstall' then cmd_uninstall(rest)
      when '__run-scheduled' then cmd_run_scheduled(rest)
      when 'version' then @out.puts(VERSION)
                          0
      when 'help' then usage
                       0
      end
    rescue Error => e
      @err.puts "cld: #{e.message}"
      1
    end

    private

    # A bare `cld`, or `cld` followed by anything that is not one of our
    # commands, means "launch Claude Code".
    def dispatch(argv)
      first = argv.first

      case first
      when nil then ['run', []]
      when '--version' then ['version', []]
      when '--help', '-h' then ['help', []]
      when *COMMANDS, SCHEDULED_COMMAND then [first, argv[1..]]
      else ['run', argv]
      end
    end

    # -- commands ------------------------------------------------------------

    # Launch Claude Code, then decide whether the session ended in a state that
    # warrants an unattended resume.
    def cmd_run(argv)
      opts, passthrough = extract_flags(argv)
      config = Config.new(opts)
      store = StateStore.new(Dir.pwd, root: config.state_dir)
      claude_bin = which('claude') or raise Error, 'claude not found on PATH'

      store.ensure_project_dir
      # A sample from an earlier run must never trigger a resume for this one.
      store.clear_limits

      if Scheduler.pending_live?(store)
        @err.puts 'cld: cancelling a previously scheduled resume (you are running interactively again)'
        Scheduler.cancel(store)
      end

      system(claude_bin, *passthrough)
      status = $CHILD_STATUS&.exitstatus || 1

      maybe_schedule(config, store, claude_bin)
      status
    end

    def cmd_statusline
      Statusline.new(state_root: Config.state_dir_from_env, out: @out).run(@stdin.read)
      0
    rescue StandardError
      0 # never break the user's statusline
    end

    def cmd_status(argv)
      config = Config.new(extract_flags(argv).first)
      store = StateStore.new(Dir.pwd, root: config.state_dir)

      StatusReport.new(config: config, store: store).lines.each { |line| @out.puts(line) }
      0
    end

    def cmd_cancel(argv)
      config = Config.new(extract_flags(argv).first)
      store = StateStore.new(Dir.pwd, root: config.state_dir)

      if Scheduler.cancel(store)
        @out.puts "Cancelled the pending resume for #{store.project_dir}"
      else
        @out.puts "No pending resume for #{store.project_dir}"
      end
      0
    end

    def cmd_resume_now(argv)
      config = Config.new(extract_flags(argv).first)
      store = StateStore.new(Dir.pwd, root: config.state_dir)
      claude_bin = which('claude') or raise Error, 'claude not found on PATH'

      raise Error, 'no resume has been scheduled for this project' if store.read_pending.nil?

      Scheduler.cancel(store)
      execute_resume(config, store, claude_bin)
    end

    def cmd_install(argv)
      config = Config.new(extract_flags(argv).first)
      Installer.new(state_root: config.state_dir, out: @out).install
      0
    end

    def cmd_uninstall(argv)
      config = Config.new(extract_flags(argv).first)
      Installer.new(state_root: config.state_dir, out: @out).uninstall
      0
    end

    # Hidden: what the scheduled job actually runs.
    def cmd_run_scheduled(argv)
      project = nil
      fire_at = nil
      claude_bin = nil
      label = nil

      OptionParser.new do |o|
        o.on('--project DIR') { |v| project = v }
        o.on('--fire-at N') { |v| fire_at = v.to_i }
        o.on('--claude-bin PATH') { |v| claude_bin = v }
        o.on('--launchd-label L') { |v| label = v }
      end.parse(argv)

      raise Error, '--project is required' if project.nil?

      config = Config.new
      store = StateStore.new(project, root: config.state_dir)

      # launchd fires at the calendar time, so this is usually a no-op; the
      # detached backend does its whole wait here.
      wait_until(fire_at) if fire_at

      @out.puts "\n===== cld resume #{Time.now} ====="
      status = execute_resume(config, store, claude_bin || which('claude') || 'claude')
      @out.puts "===== resume finished (exit #{status}) ====="

      store.clear_pending
      Scheduler::Launchd.bootout(label) if label
      status
    end

    # -- helpers -------------------------------------------------------------

    def execute_resume(config, store, claude_bin)
      sample = RateLimitSample.from_h(store.read_limits)
      resume = Resume.new(config: config, store: store, sample: sample)
      argv = resume.command(claude_bin: claude_bin)

      Dir.chdir(store.project_dir) do
        system(*argv)
      end
      $CHILD_STATUS&.exitstatus || 0
    end

    def maybe_schedule(config, store, claude_bin)
      sample = RateLimitSample.from_h(store.read_limits)
      return if sample.nil?
      return if sample.stale?(config.stale_seconds)

      window = sample.blocking_window(config.threshold)
      return if window.nil?

      if Scheduler.pending_live?(store)
        @err.puts 'cld: a resume is already scheduled for this project'
        return
      end

      fire_at = window.resets_at + config.skew_seconds
      return unless confirm_schedule?(config, window, fire_at)

      build_handoff(config, store, sample) if config.resume_strategy == 'handoff'

      scheduler = Scheduler.for(config: config, store: store, fire_at: fire_at, claude_bin: claude_bin)
      scheduler.schedule

      announce_schedule(config, store, sample, window: window, fire_at: fire_at,
                                               backend: scheduler.backend)
    end

    def announce_schedule(config, store, sample, window:, fire_at:, backend:)
      resume = Resume.new(config: config, store: store, sample: sample)

      @err.puts ''
      @err.puts "The #{window.name.tr('_', '-')} usage window was exhausted when this session ended."
      @err.puts "  Auto-resume scheduled for #{fmt_time(fire_at)} (backend: #{backend})"
      @err.puts "  Strategy: #{resume.describe}"
      @err.puts "  Log:      #{store.resume_log}"
      @err.puts '  Cancel:   cld cancel'
      @err.puts ''
    end

    def build_handoff(config, store, sample)
      transcript = Transcript.new(sample.transcript_path)
      HandoffBuilder.new(
        transcript: transcript,
        project_dir: store.project_dir,
        word_budget: config.handoff_word_budget
      ).write_to(store.handoff_path)
    rescue StandardError => e
      @err.puts "cld: could not build a handoff (#{e.message}); will resume the session instead"
      nil
    end

    def confirm_schedule?(config, window, fire_at)
      return true if config.assume_yes?
      return true unless @stdin.respond_to?(:tty?) && @stdin.tty? && @out.respond_to?(:tty?) && @out.tty?

      @err.print "#{window.name.tr('_', '-')} limit exhausted. " \
                 "Schedule an unattended resume at #{fmt_time(fire_at)}? [Y/n] "
      answer = read_with_timeout(20)
      @err.puts ''
      return true if answer.nil? || answer.strip.empty?

      !answer.strip.downcase.start_with?('n')
    end

    def read_with_timeout(seconds)
      require 'io/wait'
      return @stdin.gets if @stdin.wait_readable(seconds)

      nil
    rescue StandardError
      nil
    end

    def wait_until(fire_at)
      remaining = fire_at - Time.now.to_i
      sleep(remaining) if remaining.positive?
    end

    def usage
      @out.puts(Help.text)
    end
  end
end
