# frozen_string_literal: true

require_relative 'test_helper'

class StatuslineTest < Minitest::Test
  include HandoffTest::Sandbox

  def payload(rate_limits: :default, project_dir: nil)
    body = {
      'session_id' => 'sess-42',
      'transcript_path' => '/tmp/t.jsonl',
      'cwd' => project_dir || project,
      'workspace' => { 'project_dir' => project_dir || project }
    }
    unless rate_limits == :omit
      body['rate_limits'] = rate_limits == :default ? default_limits : rate_limits
    end
    JSON.generate(body)
  end

  def default_limits
    {
      'five_hour' => { 'used_percentage' => 100.0, 'resets_at' => 1_800_000_000 },
      'seven_day' => { 'used_percentage' => 42.5, 'resets_at' => 1_800_500_000 }
    }
  end

  def statusline(out: StringIO.new)
    ClaudeHandoff::Statusline.new(state_root: state_root, out: out)
  end

  def test_records_both_windows
    statusline.run(payload)

    sample = ClaudeHandoff::RateLimitSample.from_h(store_for.read_limits)
    refute_nil sample, 'expected a recorded sample'

    assert_equal 100.0, sample.window('five_hour').used_percentage
    assert_equal 1_800_000_000, sample.window('five_hour').resets_at
    assert_equal 42.5, sample.window('seven_day').used_percentage
    assert_equal 1_800_500_000, sample.window('seven_day').resets_at
  end

  def test_records_session_and_transcript_identity
    statusline.run(payload)
    sample = ClaudeHandoff::RateLimitSample.from_h(store_for.read_limits)

    assert_equal 'sess-42', sample.session_id
    assert_equal '/tmp/t.jsonl', sample.transcript_path
  end

  def test_records_a_single_window_when_only_one_is_present
    limits = { 'seven_day' => { 'used_percentage' => 88.0, 'resets_at' => 1_800_600_000 } }
    statusline.run(payload(rate_limits: limits))

    sample = ClaudeHandoff::RateLimitSample.from_h(store_for.read_limits)

    assert_equal 1, sample.windows.length
    assert_nil sample.window('five_hour')
    assert_equal 88.0, sample.window('seven_day').used_percentage
  end

  # API-key auth has no subscription windows at all.
  def test_absent_rate_limits_records_nothing
    statusline.run(payload(rate_limits: :omit))

    refute_path_exists store_for.limits_path
  end

  def test_malformed_input_does_not_raise_or_record
    statusline.run('this is not json')

    refute_path_exists store_for.limits_path
  end

  def test_chains_to_an_existing_statusline_via_state_file
    FileUtils.mkdir_p(state_root)
    File.write(File.join(state_root, 'inner-statusline'), 'printf INNER-OK')

    out = StringIO.new
    statusline(out: out).run(payload)

    assert_equal 'INNER-OK', out.string
  end

  def test_chained_command_receives_the_same_payload_on_stdin
    FileUtils.mkdir_p(state_root)
    File.write(File.join(state_root, 'inner-statusline'), 'cat')

    out = StringIO.new
    body = payload
    statusline(out: out).run(body)

    assert_equal body, out.string
  end

  def test_chaining_still_happens_when_the_payload_is_malformed
    FileUtils.mkdir_p(state_root)
    File.write(File.join(state_root, 'inner-statusline'), 'printf STILL-HERE')

    out = StringIO.new
    statusline(out: out).run('garbage')

    assert_equal 'STILL-HERE', out.string
  end

  def test_no_chain_configured_produces_no_output
    out = StringIO.new
    statusline(out: out).run(payload)

    assert_empty out.string
  end
end
