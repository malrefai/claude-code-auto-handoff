# frozen_string_literal: true

require 'json'
require 'digest'
require 'fileutils'

module ClaudeHandoff
  # Everything this tool persists lives under the state directory, keyed by a
  # hash of the project path. Nothing is ever written into the user's project.
  class StateStore
    attr_reader :root, :project_dir

    def initialize(project_dir, root: Config.state_dir_from_env)
      @project_dir = File.expand_path(project_dir)
      @root = File.expand_path(root)
    end

    def self.project_key(project_dir)
      Digest::SHA256.hexdigest(File.expand_path(project_dir))[0, 16]
    end

    def project_key = self.class.project_key(@project_dir)

    def project_dir_path = File.join(@root, 'projects', project_key)

    def limits_path   = File.join(project_dir_path, 'limits.json')
    def pending_path  = File.join(project_dir_path, 'pending.json')
    def handoff_path  = File.join(project_dir_path, 'handoff.md')
    def resume_log    = File.join(project_dir_path, 'resume.log')
    def plist_path    = File.join(project_dir_path, 'resume.plist')

    # Global (not per-project)
    def inner_statusline_path = File.join(@root, 'inner-statusline')

    def ensure_project_dir
      FileUtils.mkdir_p(project_dir_path)
      project_dir_path
    end

    def read_limits  = read_json(limits_path)
    def read_pending = read_json(pending_path)

    def write_limits(hash)  = write_json(limits_path, hash)
    def write_pending(hash) = write_json(pending_path, hash)

    def clear_limits  = FileUtils.rm_f(limits_path)
    def clear_pending = FileUtils.rm_f(pending_path)

    def inner_statusline
      return nil unless File.file?(inner_statusline_path)

      value = File.read(inner_statusline_path).strip
      value.empty? ? nil : value
    rescue StandardError
      nil
    end

    private

    def read_json(path)
      return nil unless File.file?(path)

      parsed = JSON.parse(File.read(path))
      parsed.is_a?(Hash) ? parsed : nil
    rescue StandardError
      # A truncated or hand-edited state file must never raise.
      nil
    end

    # Written via a temp file and rename so a reader can never observe a
    # half-written state file.
    def write_json(path, hash)
      FileUtils.mkdir_p(File.dirname(path))
      tmp = "#{path}.#{Process.pid}.tmp"
      File.write(tmp, JSON.pretty_generate(hash))
      File.rename(tmp, path)
      path
    ensure
      FileUtils.rm_f(tmp) if tmp && File.exist?(tmp.to_s)
    end
  end
end
