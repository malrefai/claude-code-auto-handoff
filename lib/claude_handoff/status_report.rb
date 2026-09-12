# frozen_string_literal: true

module ClaudeHandoff
  # Renders `cld status`: the usage windows as last sampled, and whether a
  # resume is currently booked for this project.
  class StatusReport
    include Arguments

    def initialize(config:, store:)
      @config = config
      @store = store
    end

    def lines
      ["Project: #{@store.project_dir}", *window_lines, *pending_lines]
    end

    private

    def window_lines
      sample = RateLimitSample.from_h(@store.read_limits)
      return no_sample_lines if sample.nil?

      age = Time.now.to_i - sample.recorded_at.to_i
      ["Usage windows (sampled #{age}s ago):", *sample.windows.map { |w| window_line(w) }]
    end

    def no_sample_lines
      ['Usage windows: no sample recorded',
       '  (run `cld install`, or this account has no subscription limits)']
    end

    def window_line(window)
      marker = window.used_percentage >= @config.threshold ? ' <- exhausted' : ''
      format('  %-10s %5.1f%% used, resets %s%s',
             window.name, window.used_percentage, fmt_time(window.resets_at), marker)
    end

    def pending_lines
      pending = @store.read_pending
      return ['Pending resume: none'] unless pending && Scheduler.pending_live?(@store)

      ["Pending resume: YES at #{fmt_time(pending['fire_at'])} (backend: #{pending['backend']})",
       "Resume log: #{@store.resume_log}"]
    end
  end
end
