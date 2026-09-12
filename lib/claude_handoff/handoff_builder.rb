# frozen_string_literal: true

require 'open3'
require 'time'

module ClaudeHandoff
  # Builds the compact briefing that seeds the resumed session.
  #
  # The point of the handoff is to avoid replaying an entire conversation at
  # full input price. So it keeps what a resuming session actually needs: the
  # original goal, the most recent exchanges in full, and the state of the
  # working tree. Everything in between is condensed or dropped.
  class HandoffBuilder
    EXCERPT_WORDS = 40
    FIRST_MESSAGE_MAX_WORDS = 300

    def initialize(transcript:, project_dir:, word_budget: 4000, interrupted_at: Time.now)
      @transcript = transcript
      @project_dir = project_dir
      @word_budget = word_budget
      @interrupted_at = interrupted_at
    end

    def build
      turns = @transcript.turns
      return nil if turns.empty?

      [header, *body(turns)].join("\n")
    end

    # Writes the handoff and returns its path, or nil when there was nothing to
    # write (no transcript, or an empty conversation).
    def write_to(path)
      content = build
      return nil if content.nil?

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
      path
    end

    private

    def header
      lines = [
        '# Session handoff',
        '',
        'A previous Claude Code session in this project was interrupted by a usage limit.',
        'This file is a condensed record of that session, not a full transcript.',
        '',
        "- Project: `#{@project_dir}`",
        "- Interrupted: #{@interrupted_at.strftime('%Y-%m-%d %H:%M:%S %Z')}"
      ]
      branch = git_branch
      lines << "- Branch: `#{branch}`" if branch

      status = git_status
      lines << ''
      if status && !status.empty?
        lines << '## Uncommitted changes at the time of the interruption'
        lines << ''
        lines << '```'
        lines << status
        lines << '```'
      elsif status
        lines << 'The working tree was clean when the session was interrupted.'
      end
      lines << ''
      lines.join("\n")
    end

    def body(turns)
      budget = @word_budget
      first_user = turns.find { |t| t.role == 'user' }

      first_section, budget = render_first_user(first_user, budget)
      recent, remaining_turns, budget = take_recent(turns, first_user, budget)
      condensed = condense(remaining_turns, budget)

      sections = ['## The original request', '', first_section, '']
      sections += ['## Earlier in the session (condensed)', '', *condensed, ''] unless condensed.empty?
      sections += ['## Most recent exchanges', '', *recent.map { |t| render_turn(t) }]
      sections
    end

    def render_first_user(turn, budget)
      return ['_(no user message found in the transcript)_', budget] if turn.nil?

      text = truncate_words(turn.text, FIRST_MESSAGE_MAX_WORDS)
      [text, [budget - word_count(text), 0].max]
    end

    # Walk backwards from the end of the conversation, taking whole turns while
    # the budget allows. Recent context is what a resuming session needs most.
    def take_recent(turns, first_user, budget)
      candidates = turns.reject { |t| t.equal?(first_user) }
      taken = []
      remaining_budget = budget

      candidates.reverse_each do |turn|
        cost = turn.word_count
        break if cost > remaining_budget && !taken.empty?

        taken.unshift(turn)
        remaining_budget -= cost
        break if remaining_budget <= 0
      end

      leftover = candidates[0, candidates.length - taken.length] || []
      [taken, leftover, [remaining_budget, 0].max]
    end

    # Older turns get a one-line excerpt each while budget allows; the rest are
    # replaced by a count so the resumed session knows material was omitted.
    def condense(turns, budget)
      return [] if turns.empty?

      lines = []
      used = 0
      included = 0

      turns.reverse_each do |turn|
        excerpt = truncate_words(turn.text, EXCERPT_WORDS)
        cost = word_count(excerpt)
        break if used + cost > budget

        lines.unshift("- **#{turn.role}:** #{single_line(excerpt)}")
        used += cost
        included += 1
      end

      dropped = turns.length - included
      lines.unshift("_#{dropped} earlier turn#{'s' if dropped != 1} omitted._", '') if dropped.positive?
      lines
    end

    def render_turn(turn)
      "### #{turn.role}\n\n#{turn.text}\n"
    end

    def truncate_words(text, limit)
      words = text.split(/\s+/)
      return text if words.length <= limit

      "#{words[0, limit].join(' ')} …"
    end

    def single_line(text) = text.gsub(/\s+/, ' ').strip

    def word_count(text) = text.split(/\s+/).length

    def git_branch
      out, status = capture_git('rev-parse', '--abbrev-ref', 'HEAD')
      status&.success? ? out.strip : nil
    end

    def git_status
      out, status = capture_git('status', '--short')
      status&.success? ? out.strip : nil
    end

    def capture_git(*args)
      Open3.capture2('git', '-C', @project_dir, *args, err: File::NULL)
    rescue StandardError
      [nil, nil]
    end
  end
end
