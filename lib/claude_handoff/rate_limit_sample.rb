# frozen_string_literal: true

module ClaudeHandoff
  # A reading of the subscription usage windows, taken from the statusline
  # payload. Claude Code exposes two independent windows and either can be the
  # one actually blocking you — many users are constrained by the weekly limit
  # while the 5-hour window sits nearly empty.
  class RateLimitSample
    WINDOW_NAMES = %w[five_hour seven_day].freeze

    Window = Struct.new(:name, :used_percentage, :resets_at, keyword_init: true) do
      def exhausted?(threshold) = used_percentage >= threshold
      def reset_in_future?(now = Time.now.to_i) = resets_at > now
    end

    attr_reader :windows, :session_id, :transcript_path, :project_dir, :recorded_at

    def initialize(windows:, session_id: nil, transcript_path: nil, project_dir: nil, recorded_at: nil)
      @windows = windows
      @session_id = session_id
      @transcript_path = transcript_path
      @project_dir = project_dir
      @recorded_at = recorded_at
    end

    # Builds from the raw statusline JSON. Returns nil when the payload carries
    # no rate-limit data at all — that is the normal case for API-key auth and
    # before the first API response of a session.
    def self.from_statusline(payload)
      return nil unless payload.is_a?(Hash)

      limits = payload['rate_limits']
      return nil unless limits.is_a?(Hash)

      windows = WINDOW_NAMES.filter_map do |name|
        raw = limits[name]
        next unless raw.is_a?(Hash)

        used = raw['used_percentage']
        resets = raw['resets_at']
        next if used.nil? || resets.nil?

        Window.new(name: name, used_percentage: used.to_f, resets_at: resets.to_i)
      end
      return nil if windows.empty?

      new(
        windows: windows,
        session_id: payload['session_id'],
        transcript_path: payload['transcript_path'],
        project_dir: payload.dig('workspace', 'project_dir') || payload['cwd'],
        recorded_at: Time.now.to_i
      )
    end

    def self.from_h(hash)
      return nil unless hash.is_a?(Hash)

      raw_windows = hash['windows']
      return nil unless raw_windows.is_a?(Array)

      windows = raw_windows.filter_map do |w|
        next unless w.is_a?(Hash) && w['name'] && w['used_percentage'] && w['resets_at']

        Window.new(
          name: w['name'],
          used_percentage: w['used_percentage'].to_f,
          resets_at: w['resets_at'].to_i
        )
      end
      return nil if windows.empty?

      new(
        windows: windows,
        session_id: hash['session_id'],
        transcript_path: hash['transcript_path'],
        project_dir: hash['project_dir'],
        recorded_at: hash['recorded_at']&.to_i
      )
    end

    def to_h
      {
        'windows' => windows.map do |w|
          { 'name' => w.name, 'used_percentage' => w.used_percentage, 'resets_at' => w.resets_at }
        end,
        'session_id' => session_id,
        'transcript_path' => transcript_path,
        'project_dir' => project_dir,
        'recorded_at' => recorded_at
      }
    end

    def window(name) = windows.find { |w| w.name == name }

    def stale?(stale_seconds, now = Time.now.to_i)
      return true if recorded_at.nil?

      (now - recorded_at) > stale_seconds
    end

    # The window that is actually holding the session back: exhausted, and not
    # yet reset. When both are exhausted the later reset governs, because work
    # cannot continue until every exhausted window has cleared.
    def blocking_window(threshold, now = Time.now.to_i)
      windows
        .select { |w| w.exhausted?(threshold) && w.reset_in_future?(now) }
        .max_by(&:resets_at)
    end
  end
end
