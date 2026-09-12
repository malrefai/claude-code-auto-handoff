# frozen_string_literal: true

module ClaudeHandoff
  # Builds and runs the command that continues the interrupted work.
  class Resume
    PROMPT = <<~TEXT.strip
      The usage limit that interrupted the previous session in this project has reset.
      Re-read the workspace to confirm the current state (git status, git diff, and the
      files most recently touched), then continue the task that was in progress. If the
      task was already finished, say so and stop without making changes.
    TEXT

    def initialize(config:, store:, sample: nil)
      @config = config
      @store = store
      @sample = sample
    end

    # The argv for the resumed session. Array form throughout — no path is ever
    # interpolated into a shell string.
    def command(claude_bin: 'claude')
      argv = [claude_bin, '--permission-mode', @config.permission_mode]

      if session_strategy?
        argv += ['--resume', @sample.session_id]
        argv += ['-p', PROMPT]
      else
        argv += ['-p', handoff_prompt]
      end
      argv
    end

    # Falls back to resuming the session when the strategy is "handoff" but no
    # handoff file could be produced — better to spend the tokens than to start
    # a session with no idea what it is meant to do.
    def session_strategy?
      return true if @config.resume_strategy == 'session' && session_id?
      return true if @config.resume_strategy == 'handoff' && !handoff_available? && session_id?

      false
    end

    def handoff_available? = File.file?(@store.handoff_path)

    def session_id? = !@sample.nil? && !@sample.session_id.nil? && !@sample.session_id.empty?

    def describe
      if session_strategy?
        "resume session #{@sample.session_id}"
      elsif handoff_available?
        "fresh session seeded with #{@store.handoff_path}"
      else
        'fresh session (no handoff available)'
      end
    end

    private

    def handoff_prompt
      if handoff_available?
        <<~TEXT.strip
          Read the session handoff file at #{@store.handoff_path} — it is a condensed
          record of an earlier session in this project that a usage limit interrupted.

          #{PROMPT}
        TEXT
      else
        PROMPT
      end
    end
  end
end
