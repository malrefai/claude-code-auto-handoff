# frozen_string_literal: true

require_relative 'test_helper'

class ResumeTest < Minitest::Test
  include HandoffTest::Sandbox

  def sample(session_id: 'sess-1')
    ClaudeHandoff::RateLimitSample.from_h(
      'windows' => [{ 'name' => 'five_hour', 'used_percentage' => 100, 'resets_at' => 1 }],
      'session_id' => session_id,
      'recorded_at' => Time.now.to_i
    )
  end

  def resume(strategy:, with_handoff: false, session_id: 'sess-1')
    store = store_for
    store.ensure_project_dir
    File.write(store.handoff_path, '# handoff') if with_handoff

    ClaudeHandoff::Resume.new(
      config: config(resume_strategy: strategy),
      store: store,
      sample: sample(session_id: session_id)
    )
  end

  def test_handoff_strategy_starts_a_fresh_session_pointing_at_the_file
    argv = resume(strategy: 'handoff', with_handoff: true).command(claude_bin: '/bin/claude')

    refute_includes argv, '--resume'
    assert_includes argv, '-p'
    assert_includes argv.last, store_for.handoff_path
  end

  def test_handoff_strategy_sets_the_permission_mode
    argv = resume(strategy: 'handoff', with_handoff: true).command(claude_bin: '/bin/claude')

    assert_equal '/bin/claude', argv.first
    assert_equal 'auto', argv[argv.index('--permission-mode') + 1]
  end

  def test_session_strategy_resumes_the_original_session
    argv = resume(strategy: 'session').command(claude_bin: '/bin/claude')

    assert_includes argv, '--resume'
    assert_equal 'sess-1', argv[argv.index('--resume') + 1]
  end

  # Starting a blank session with no idea what it is for would be worse than
  # spending the tokens to replay the conversation.
  def test_falls_back_to_session_resume_when_no_handoff_could_be_built
    argv = resume(strategy: 'handoff', with_handoff: false).command(claude_bin: '/bin/claude')

    assert_includes argv, '--resume'
  end

  def test_handoff_strategy_without_handoff_or_session_id_still_produces_a_prompt
    r = resume(strategy: 'handoff', with_handoff: false, session_id: '')
    argv = r.command(claude_bin: '/bin/claude')

    refute_includes argv, '--resume'
    assert_includes argv, '-p'
    refute_empty argv.last
  end

  def test_command_is_argv_not_a_shell_string
    argv = resume(strategy: 'handoff', with_handoff: true).command(claude_bin: '/bin/claude')

    assert_kind_of Array, argv
    assert(argv.all?(String))
  end

  def test_describe_explains_the_chosen_strategy
    assert_includes resume(strategy: 'session').describe, 'resume session'
    assert_includes resume(strategy: 'handoff', with_handoff: true).describe, 'fresh session'
  end
end
