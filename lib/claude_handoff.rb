# frozen_string_literal: true

# cld — a drop-in replacement for the `claude` command that schedules an
# unattended resume when a Claude Code session ends while a usage limit is
# exhausted.
#
# Uses only the Ruby standard library: that keeps the Homebrew formula trivial,
# lets bin/cld run straight from a checkout, and keeps the statusline sidecar
# fast to start.
module ClaudeHandoff
  # Raised for user-facing failures; the CLI prints the message and exits 1.
  class Error < StandardError; end

  # Absolute path to the running executable. The scheduled job re-invokes this
  # same program later, when PATH and the working directory may both differ.
  def self.program_path
    @program_path ||= File.expand_path(ENV['CLAUDE_HANDOFF_PROGRAM'] || $PROGRAM_NAME)
  end

  def self.program_path=(path)
    @program_path = path && File.expand_path(path)
  end
end

require 'English'

require_relative 'claude_handoff/version'
require_relative 'claude_handoff/config'
require_relative 'claude_handoff/help'
require_relative 'claude_handoff/arguments'
require_relative 'claude_handoff/state_store'
require_relative 'claude_handoff/rate_limit_sample'
require_relative 'claude_handoff/statusline'
require_relative 'claude_handoff/transcript'
require_relative 'claude_handoff/handoff_builder'
require_relative 'claude_handoff/resume'
require_relative 'claude_handoff/scheduler'
require_relative 'claude_handoff/installer'
require_relative 'claude_handoff/status_report'
require_relative 'claude_handoff/cli'
