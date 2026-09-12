# frozen_string_literal: true

module ClaudeHandoff
  # The `cld help` text. Kept apart from the CLI so the dispatcher stays about
  # dispatching, and so wording changes never touch command logic.
  module Help
    module_function

    def text
      <<~TEXT
        cld #{VERSION} — Claude Code, plus an automatic resume when a usage limit clears

        Usage:
          cld [claude args...]      Launch Claude Code. Schedules a resume if the
                                    session ends while a usage window is exhausted.
          cld <command> [options]

        Commands:
          status        Show usage windows and any pending resume
          cancel        Cancel a pending resume for this project
          resume-now    Run the pending resume immediately
          install       Wire the statusline sidecar into ~/.claude/settings.json
          uninstall     Reverse install, restoring any previous statusline
          run           Launch Claude Code (the implicit default)
          statusline    Sidecar; reads the statusline payload on stdin
          version       Print the version
          help          Show this message

        Options (namespaced so they never collide with Claude Code's own flags):
          --handoff-yes                 Do not prompt before scheduling
          --handoff-threshold PCT       Treat a window at/above this as exhausted (default: 99)
          --handoff-strategy S          handoff (default) | session
          --handoff-permission-mode M   Permission mode for the resume (default: auto)
          --handoff-scheduler B         auto | detached | launchd
          --handoff-word-budget N       Handoff size budget in words (default: 4000)

        Everything else is passed straight to Claude Code:
          cld --model opus
          cld -- status            (sends the literal word "status" to Claude Code)

        State lives in #{Config.state_dir_from_env}
      TEXT
    end
  end
end
