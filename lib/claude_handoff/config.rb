# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module ClaudeHandoff
  # Resolved settings, in precedence order: command-line flags, then environment
  # variables, then ~/.claude/auto-handoff/config.yml, then the defaults below.
  class Config
    DEFAULTS = {
      'permission_mode' => 'auto',
      'threshold' => 99.0,
      'stale_seconds' => 900,
      'skew_seconds' => 60,
      'handoff_word_budget' => 4000,
      'resume_strategy' => 'handoff', # "handoff" | "session"
      'scheduler' => 'auto',          # "auto" | "detached" | "launchd"
      'launchd_threshold_seconds' => 6 * 3600,
      'assume_yes' => false
    }.freeze

    # Environment variable name => [config key, coercion]
    ENV_KEYS = {
      'CLAUDE_HANDOFF_PERMISSION_MODE' => ['permission_mode', :string],
      'CLAUDE_HANDOFF_THRESHOLD' => ['threshold', :float],
      'CLAUDE_HANDOFF_STALE_SECONDS' => ['stale_seconds', :int],
      'CLAUDE_HANDOFF_SKEW_SECONDS' => ['skew_seconds', :int],
      'CLAUDE_HANDOFF_WORD_BUDGET' => ['handoff_word_budget', :int],
      'CLAUDE_HANDOFF_RESUME_STRATEGY' => ['resume_strategy', :string],
      'CLAUDE_HANDOFF_SCHEDULER' => ['scheduler', :string],
      'CLAUDE_HANDOFF_LAUNCHD_THRESHOLD_SECONDS' => ['launchd_threshold_seconds', :int],
      'CLAUDE_HANDOFF_ASSUME_YES' => ['assume_yes', :bool]
    }.freeze

    VALID_PERMISSION_MODES = %w[acceptEdits auto bypassPermissions manual dontAsk plan].freeze
    VALID_STRATEGIES = %w[handoff session].freeze
    VALID_SCHEDULERS = %w[auto detached launchd].freeze

    attr_reader :state_dir

    def self.state_dir_from_env
      dir = ENV.fetch('CLAUDE_HANDOFF_HOME', nil)
      return File.expand_path(dir) if dir && !dir.empty?

      File.expand_path('~/.claude/auto-handoff')
    end

    def initialize(overrides = {}, state_dir: nil)
      @state_dir = state_dir || self.class.state_dir_from_env
      @values = DEFAULTS.merge(from_file).merge(from_env).merge(stringify(overrides))
      validate!
    end

    def [](key)
      @values[key.to_s]
    end

    def permission_mode = @values['permission_mode']
    def threshold = @values['threshold'].to_f
    def stale_seconds = @values['stale_seconds'].to_i
    def skew_seconds = @values['skew_seconds'].to_i
    def handoff_word_budget = @values['handoff_word_budget'].to_i
    def resume_strategy = @values['resume_strategy']
    def scheduler = @values['scheduler']
    def launchd_threshold_seconds = @values['launchd_threshold_seconds'].to_i
    def assume_yes? = !!@values['assume_yes']

    def config_file = File.join(@state_dir, 'config.yml')

    def to_h = @values.dup

    private

    def from_file
      return {} unless File.file?(config_file)

      # safe_load: this file is user-editable, but it must never be able to
      # instantiate arbitrary objects.
      loaded = YAML.safe_load_file(config_file, permitted_classes: [], aliases: false)
      loaded.is_a?(Hash) ? loaded.transform_keys(&:to_s) : {}
    rescue StandardError
      # A malformed config must not stop the tool from running.
      {}
    end

    def from_env
      ENV_KEYS.each_with_object({}) do |(env_name, (key, type)), acc|
        raw = ENV.fetch(env_name, nil)
        next if raw.nil? || raw.empty?

        acc[key] = coerce(raw, type)
      end
    end

    def coerce(raw, type)
      case type
      when :int then Integer(raw, exception: false) || DEFAULTS[type.to_s]
      when :float then Float(raw, exception: false)
      when :bool then %w[1 true yes on].include?(raw.downcase)
      else raw
      end
    end

    def stringify(hash)
      hash.each_with_object({}) { |(k, v), acc| acc[k.to_s] = v unless v.nil? }
    end

    def validate!
      unless VALID_PERMISSION_MODES.include?(@values['permission_mode'])
        raise Error, "invalid permission_mode #{@values['permission_mode'].inspect} " \
                     "(expected one of: #{VALID_PERMISSION_MODES.join(', ')})"
      end
      unless VALID_STRATEGIES.include?(@values['resume_strategy'])
        raise Error, "invalid resume_strategy #{@values['resume_strategy'].inspect} " \
                     "(expected one of: #{VALID_STRATEGIES.join(', ')})"
      end
      return if VALID_SCHEDULERS.include?(@values['scheduler'])

      raise Error, "invalid scheduler #{@values['scheduler'].inspect} " \
                   "(expected one of: #{VALID_SCHEDULERS.join(', ')})"
    end
  end
end
