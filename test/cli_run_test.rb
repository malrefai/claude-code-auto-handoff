# frozen_string_literal: true

require_relative 'test_helper'

# Exercises the real executable in a subprocess with a stub `claude` on PATH.
class CLIRunTest < Minitest::Test
  include HandoffTest::Sandbox

  def limits_path_for(dir = project) = store_for(dir).limits_path

  # Plants the sample the way the statusline sidecar would during the session.
  def stub_env(json, dir: project, exit_code: 0)
    {
      'CLAUDE_STUB_SAMPLE_PATH' => limits_path_for(dir),
      'CLAUDE_STUB_SAMPLE_JSON' => json,
      'CLAUDE_STUB_EXIT' => exit_code.to_s
    }
  end

  def future(seconds = 7200) = Time.now.to_i + seconds

  def pending = store_for.read_pending

  def cancel!
    run_cli('cancel')
  end

  # -- scheduling decisions -------------------------------------------------

  def test_schedules_when_a_window_is_exhausted
    run_cli('run', '--handoff-yes', env: stub_env(sample_json(five_hour: [100.0, future])))

    refute_nil pending, 'expected a scheduled resume'
    assert_equal 'detached', pending['backend']
    assert_in_delta future + 60, pending['fire_at'], 5
    cancel!
  end

  def test_does_not_schedule_below_the_threshold
    run_cli('run', '--handoff-yes', env: stub_env(sample_json(five_hour: [42.0, future])))

    assert_nil pending
  end

  def test_does_not_schedule_on_a_stale_sample
    json = sample_json(five_hour: [100.0, future], recorded_at: Time.now.to_i - 99_999)
    run_cli('run', '--handoff-yes', env: stub_env(json))

    assert_nil pending
  end

  def test_does_not_schedule_when_the_window_already_reset
    run_cli('run', '--handoff-yes', env: stub_env(sample_json(five_hour: [100.0, Time.now.to_i - 60])))

    assert_nil pending
  end

  def test_does_not_schedule_without_any_sample
    run_cli('run', '--handoff-yes')

    assert_nil pending
  end

  def test_schedules_against_the_weekly_window_when_that_is_the_blocking_one
    weekly_reset = future(400_000)
    json = sample_json(five_hour: [12.0, future(60)], seven_day: [100.0, weekly_reset])
    run_cli('run', '--handoff-yes', env: stub_env(json))

    refute_nil pending
    assert_in_delta weekly_reset + 60, pending['fire_at'], 5
    cancel!
  end

  def test_schedules_against_the_later_reset_when_both_are_exhausted
    later = future(90_000)
    json = sample_json(five_hour: [100.0, future(100)], seven_day: [100.0, later])
    run_cli('run', '--handoff-yes', env: stub_env(json))

    assert_in_delta later + 60, pending['fire_at'], 5
    cancel!
  end

  def test_threshold_is_configurable_from_the_command_line
    run_cli('run', '--handoff-yes', '--handoff-threshold', '40',
            env: stub_env(sample_json(five_hour: [42.0, future])))

    refute_nil pending
    cancel!
  end

  def test_does_not_schedule_twice_for_the_same_project
    env = stub_env(sample_json(five_hour: [100.0, future]))
    run_cli('run', '--handoff-yes', env: env)
    first = pending

    _out, err, _code = run_cli('run', '--handoff-yes', env: env)

    # The second run cancels the pending resume on startup (the user is back at
    # the keyboard), then schedules a fresh one — never two at once.
    assert_includes err, 'cancelling a previously scheduled resume'
    refute_equal first['pid'], pending['pid']
    cancel!
  end

  # -- process behaviour ----------------------------------------------------

  def test_passes_arguments_through_to_claude
    run_cli('run', '--handoff-yes', '--', '--model', 'opus')

    assert_includes stub_argv.last, '--model'
    assert_includes stub_argv.last, 'opus'
  end

  # -- implicit run ---------------------------------------------------------
  # `cld` stands in for `claude`, so anything that is not one of our commands
  # launches Claude Code with those arguments.

  def test_bare_invocation_launches_claude
    run_cli

    assert_equal 1, stub_argv.length
    assert_equal '[]', stub_argv.first
  end

  def test_claude_flags_pass_through_without_a_subcommand
    run_cli('--model', 'opus')

    assert_includes stub_argv.last, '--model'
    assert_includes stub_argv.last, 'opus'
  end

  def test_a_bare_prompt_passes_through
    run_cli('write me a haiku')

    assert_includes stub_argv.last, 'write me a haiku'
  end

  # Our flags must be consumed, never forwarded to Claude Code.
  def test_handoff_flags_are_not_forwarded_to_claude
    run_cli('--handoff-yes', '--model', 'opus')

    refute_includes stub_argv.last, 'handoff-yes'
    assert_includes stub_argv.last, '--model'
  end

  def test_double_dash_forces_a_command_word_through_to_claude
    run_cli('--', 'status')

    assert_includes stub_argv.last, 'status'
  end

  def test_subcommands_are_not_sent_to_claude
    run_cli('status')

    assert_empty stub_argv
  end

  def test_version_and_help_do_not_launch_claude
    out, = run_cli('version')
    assert_equal ClaudeHandoff::VERSION, out.strip

    help, = run_cli('help')
    assert_includes help, 'cld'
    assert_empty stub_argv
  end

  def test_propagates_claude_exit_status
    _out, _err, code = run_cli('run', '--handoff-yes', env: stub_env(sample_json, exit_code: 3))

    assert_equal 3, code
  end

  def test_clears_a_previous_sample_before_launching
    # A sample left behind by an earlier run must not trigger a resume now.
    store_for.ensure_project_dir
    File.write(limits_path_for, sample_json(five_hour: [100.0, future]))

    run_cli('run', '--handoff-yes')

    assert_nil pending
  end

  # -- status and cancel ----------------------------------------------------

  def test_status_reports_windows_and_the_pending_resume
    run_cli('run', '--handoff-yes', env: stub_env(sample_json(five_hour: [100.0, future],
                                                              seven_day: [50.0, future(90_000)])))
    out, = run_cli('status')

    assert_includes out, 'five_hour'
    assert_includes out, 'seven_day'
    assert_includes out, 'exhausted'
    assert_includes out, 'Pending resume: YES'
    cancel!
  end

  def test_status_without_any_state
    out, = run_cli('status')

    assert_includes out, 'no sample recorded'
    assert_includes out, 'Pending resume: none'
  end

  def test_cancel_kills_the_scheduled_job
    run_cli('run', '--handoff-yes', env: stub_env(sample_json(five_hour: [100.0, future])))
    pid = pending['pid']

    out, = run_cli('cancel')

    assert_includes out, 'Cancelled'
    assert_nil pending
    sleep 0.2
    refute process_alive?(pid), 'expected the scheduled process to be gone'
  end

  def test_cancel_without_a_pending_resume
    out, = run_cli('cancel')

    assert_includes out, 'No pending resume'
  end

  # -- end to end -----------------------------------------------------------

  def test_the_scheduled_job_actually_fires_and_resumes
    # Far enough out that the window is still in the future when `run` finishes
    # launching, close enough that the test does not wait long for it to fire.
    json = sample_json(five_hour: [100.0, Time.now.to_i + 4])
    run_cli('run', '--handoff-yes', env: stub_env(json).merge('CLAUDE_HANDOFF_SKEW_SECONDS' => '0'))

    refute_nil pending, 'expected a scheduled resume'
    File.write(stub_log, '') # ignore the launch invocation

    fired = eventually?(15) { stub_argv.any? { |line| line.include?('--permission-mode') } }
    assert fired, "scheduled job never invoked claude (log: #{stub_argv.inspect})"

    invocation = stub_argv.find { |line| line.include?('--permission-mode') }
    assert_includes invocation, 'auto'
    assert_nil pending, 'the job should clear its pending record when it finishes'
  end

  def test_the_scheduled_job_survives_the_parent_exiting
    json = sample_json(five_hour: [100.0, Time.now.to_i + 30])
    run_cli('run', '--handoff-yes', env: stub_env(json).merge('CLAUDE_HANDOFF_SKEW_SECONDS' => '0'))

    pid = pending['pid']
    # run_cli has already returned, so the launching process is gone.
    assert process_alive?(pid), 'scheduled job died with its parent'
    cancel!
  end

  # -- awkward paths --------------------------------------------------------

  def test_handles_a_project_path_with_spaces_and_a_quote
    weird = File.join(sandbox, "a project's dir")
    FileUtils.mkdir_p(weird)

    run_cli('run', '--handoff-yes',
            env: stub_env(sample_json(five_hour: [100.0, future], project_dir: weird), dir: weird),
            chdir: weird)

    weird_pending = store_for(weird).read_pending
    refute_nil weird_pending, 'expected a scheduled resume for the awkward path'
    assert_equal weird, weird_pending['project_dir']

    run_cli('cancel', chdir: weird)
  end

  private

  def process_alive?(pid)
    return false if pid.nil?

    Process.kill(0, pid.to_i)
    true
  rescue StandardError
    false
  end

  def eventually?(seconds)
    deadline = Time.now + seconds
    while Time.now < deadline
      return true if yield

      sleep 0.25
    end
    false
  end
end
