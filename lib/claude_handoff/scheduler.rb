# frozen_string_literal: true

require 'rbconfig'
require 'fileutils'
require 'time'

module ClaudeHandoff
  # Schedules the resume for the moment the blocking window clears.
  #
  # Deliberately not cron: `MIN HOUR * * *` is a daily recurring schedule, not a
  # one-shot, and a self-removal step chained with `&&` leaves the job firing
  # every day forever whenever the command exits non-zero.
  class Scheduler
    class << self
      # A detached process is enough for a 5-hour wait. A weekly window can be
      # days out, and a sleeping process does not survive a reboot, so long
      # waits go to launchd where the OS owns the schedule.
      def for(config:, store:, fire_at:, claude_bin:, now: Time.now.to_i)
        backend = config.scheduler
        backend = pick_backend(config, fire_at - now) if backend == 'auto'

        args = { config: config, store: store, fire_at: fire_at, claude_bin: claude_bin }
        backend == 'launchd' ? Launchd.new(**args) : Detached.new(**args)
      end

      def pick_backend(config, delay)
        return 'detached' unless launchd_available?

        delay > config.launchd_threshold_seconds ? 'launchd' : 'detached'
      end

      def launchd_available?
        RbConfig::CONFIG['host_os'].include?('darwin') && !ENV['CLAUDE_HANDOFF_DISABLE_LAUNCHD']
      end

      # Cancels whatever is recorded as pending, whichever backend placed it.
      def cancel(store)
        pending = store.read_pending
        return false if pending.nil?

        cancelled =
          case pending['backend']
          when 'launchd' then Launchd.cancel(store, pending)
          else Detached.cancel(store, pending)
          end

        store.clear_pending
        cancelled
      end

      def pending_live?(store)
        pending = store.read_pending
        return false if pending.nil?

        case pending['backend']
        when 'launchd' then Launchd.live?(pending)
        else Detached.live?(pending)
        end
      end
    end

    def initialize(config:, store:, fire_at:, claude_bin:)
      @config = config
      @store = store
      @fire_at = fire_at
      @claude_bin = claude_bin
    end

    attr_reader :config, :store, :fire_at, :claude_bin

    # Parenthesised on purpose: Ruby 3.0 cannot parse a bare command call as an
    # endless method body, and the Homebrew formula declares a 3.0 floor.
    def backend = raise(NotImplementedError)

    protected

    # The scheduled job re-invokes this same program, through the same Ruby, so
    # it does not depend on PATH or a shebang being resolvable later. The Claude
    # Code binary is resolved now, in the user's shell, for the same reason —
    # launchd gives the job a minimal PATH.
    def child_argv
      [
        RbConfig.ruby,
        ClaudeHandoff.program_path,
        '__run-scheduled',
        '--project', store.project_dir,
        '--fire-at', fire_at.to_s,
        '--claude-bin', claude_bin
      ]
    end

    def record_pending(extra)
      store.write_pending({
        'backend' => backend,
        'fire_at' => fire_at,
        'project_dir' => store.project_dir,
        'scheduled_at' => Time.now.to_i
      }.merge(extra))
    end

    # A detached child process that sleeps until the reset. Survives the parent
    # terminal closing; does not survive a reboot.
    class Detached < Scheduler
      def backend = 'detached'

      def schedule
        store.ensure_project_dir

        # Block form so the descriptor is closed even if spawn raises. The child
        # keeps its own copy, so closing here does not affect it.
        pid = File.open(store.resume_log, 'a') do |log|
          log.sync = true
          Process.spawn(
            *child_argv,
            out: log, err: log, in: File::NULL,
            pgroup: true # leave the terminal's process group so SIGHUP does not kill it
          )
        end
        Process.detach(pid)

        record_pending('pid' => pid)
        pid
      end

      def self.live?(pending)
        pid = pending['pid']
        return false if pid.nil?

        Process.kill(0, pid.to_i)
        true
      rescue StandardError
        # Errno::ESRCH (gone) and Errno::EPERM (alive, not ours) are both
        # StandardError, so listing them alongside it only shadowed them.
        false
      end

      def self.cancel(_store, pending)
        pid = pending['pid']
        return false if pid.nil?

        Process.kill('TERM', pid.to_i)
        true
      rescue StandardError
        false
      end
    end

    # A launchd agent. The OS holds the schedule, so it survives logout and
    # reboot. The job removes itself once it has run.
    class Launchd < Scheduler
      def backend = 'launchd'

      def label = "com.claude-handoff.#{store.project_key}"

      def schedule
        store.ensure_project_dir
        self.class.bootout(label)
        File.write(store.plist_path, plist)

        ok = system('launchctl', 'bootstrap', domain, store.plist_path,
                    out: File::NULL, err: File::NULL)
        # Fall back rather than silently scheduling nothing.
        unless ok
          return Detached.new(config: config, store: store, fire_at: fire_at,
                              claude_bin: claude_bin).schedule
        end

        record_pending('label' => label, 'plist' => store.plist_path)
        label
      end

      def self.domain = "gui/#{Process.uid}"

      def self.bootout(label)
        system('launchctl', 'bootout', "#{domain}/#{label}", out: File::NULL, err: File::NULL)
      rescue StandardError
        false
      end

      def self.live?(pending)
        label = pending['label']
        return false if label.nil?

        system('launchctl', 'print', "#{domain}/#{label}", out: File::NULL, err: File::NULL)
      rescue StandardError
        false
      end

      def self.cancel(store, pending)
        label = pending['label']
        return false if label.nil?

        result = bootout(label)
        FileUtils.rm_f(store.plist_path)
        result
      end

      private

      def domain = self.class.domain

      def plist
        t = Time.at(fire_at).localtime
        args = child_argv + ['--launchd-label', label]

        <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
            <key>Label</key>
            <string>#{escape(label)}</string>
            <key>ProgramArguments</key>
            <array>
          #{args.map { |a| "      <string>#{escape(a)}</string>" }.join("\n")}
            </array>
            <key>StartCalendarInterval</key>
            <dict>
              <key>Month</key><integer>#{t.month}</integer>
              <key>Day</key><integer>#{t.day}</integer>
              <key>Hour</key><integer>#{t.hour}</integer>
              <key>Minute</key><integer>#{t.min}</integer>
            </dict>
            <key>StandardOutPath</key>
            <string>#{escape(store.resume_log)}</string>
            <key>StandardErrorPath</key>
            <string>#{escape(store.resume_log)}</string>
            <key>RunAtLoad</key>
            <false/>
          </dict>
          </plist>
        XML
      end

      def escape(text)
        text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
      end
    end
  end
end
