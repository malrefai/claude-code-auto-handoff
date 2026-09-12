# frozen_string_literal: true

require 'json'

module ClaudeHandoff
  # Reads a Claude Code session transcript. The file is newline-delimited JSON,
  # which means the conversation can be recovered as structured text — no ANSI
  # escapes, no re-rendered TUI frames, no tool-call noise.
  class Transcript
    Turn = Struct.new(:role, :text, keyword_init: true) do
      def word_count = text.split(/\s+/).length
    end

    attr_reader :path

    def initialize(path)
      @path = path
    end

    def exist? = !@path.nil? && !@path.empty? && File.file?(@path)

    # Conversation turns in order. Sidechain records (subagent conversations)
    # are excluded: they are not the main thread of work.
    def turns
      return [] unless exist?

      File.foreach(@path).filter_map do |line|
        record = parse_line(line)
        next unless record

        turn_from(record)
      end
    rescue StandardError
      []
    end

    private

    def parse_line(line)
      line = line.strip
      return nil if line.empty?

      JSON.parse(line)
    rescue JSON::ParserError
      nil
    end

    def turn_from(record)
      return nil unless record.is_a?(Hash)
      return nil unless %w[user assistant].include?(record['type'])
      return nil if record['isSidechain']

      message = record['message']
      return nil unless message.is_a?(Hash)

      text = extract_text(message['content'])
      return nil if text.nil? || text.strip.empty?

      Turn.new(role: message['role'] || record['type'], text: text.strip)
    end

    # Content is either a plain string or an array of typed blocks. Only text
    # blocks carry conversation; tool_use and tool_result are noise for a
    # handoff.
    def extract_text(content)
      case content
      when String then content
      when Array
        content
          .select { |block| block.is_a?(Hash) && block['type'] == 'text' }
          .map { |block| block['text'] }
          .compact
          .join("\n")
      end
    end
  end
end
