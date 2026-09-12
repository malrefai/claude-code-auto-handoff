# frozen_string_literal: true

require_relative 'test_helper'

class RateLimitSampleTest < Minitest::Test
  NOW = 1_800_000_000

  def build(windows, recorded_at: NOW)
    ClaudeHandoff::RateLimitSample.from_h(
      'windows' => windows,
      'session_id' => 's',
      'recorded_at' => recorded_at
    )
  end

  def win(name, used, resets_at)
    { 'name' => name, 'used_percentage' => used, 'resets_at' => resets_at }
  end

  def test_no_window_is_blocking_when_all_are_below_threshold
    sample = build([win('five_hour', 50, NOW + 100), win('seven_day', 80, NOW + 200)])

    assert_nil sample.blocking_window(99, NOW)
  end

  def test_identifies_the_exhausted_window
    sample = build([win('five_hour', 33, NOW + 100), win('seven_day', 100, NOW + 5000)])
    window = sample.blocking_window(99, NOW)

    assert_equal 'seven_day', window.name
  end

  # The weekly window is the one many users actually run out of, while the
  # five-hour window sits nearly empty.
  def test_picks_weekly_over_an_idle_five_hour_window
    sample = build([win('five_hour', 12, NOW + 60), win('seven_day', 99.6, NOW + 400_000)])

    assert_equal 'seven_day', sample.blocking_window(99, NOW).name
  end

  # Work cannot continue until every exhausted window has cleared, so the later
  # reset governs.
  def test_both_exhausted_picks_the_later_reset
    sample = build([win('five_hour', 100, NOW + 100), win('seven_day', 100, NOW + 90_000)])

    assert_equal 'seven_day', sample.blocking_window(99, NOW).name
  end

  def test_both_exhausted_picks_five_hour_when_it_resets_later
    sample = build([win('five_hour', 100, NOW + 90_000), win('seven_day', 100, NOW + 100)])

    assert_equal 'five_hour', sample.blocking_window(99, NOW).name
  end

  def test_a_window_that_has_already_reset_is_not_blocking
    sample = build([win('five_hour', 100, NOW - 10)])

    assert_nil sample.blocking_window(99, NOW)
  end

  def test_threshold_is_inclusive
    sample = build([win('five_hour', 99.0, NOW + 100)])

    assert_equal 'five_hour', sample.blocking_window(99, NOW).name
  end

  def test_threshold_is_configurable
    sample = build([win('five_hour', 90, NOW + 100)])

    assert_nil sample.blocking_window(99, NOW)
    assert_equal 'five_hour', sample.blocking_window(85, NOW).name
  end

  def test_staleness
    sample = build([win('five_hour', 100, NOW + 100)], recorded_at: NOW - 1000)

    assert sample.stale?(900, NOW)
    refute sample.stale?(2000, NOW)
  end

  def test_round_trips_through_a_hash
    original = build([win('five_hour', 100, NOW + 5)])
    restored = ClaudeHandoff::RateLimitSample.from_h(original.to_h)

    assert_equal original.windows.map(&:to_a), restored.windows.map(&:to_a)
    assert_equal original.session_id, restored.session_id
  end

  def test_from_h_rejects_junk
    assert_nil ClaudeHandoff::RateLimitSample.from_h(nil)
    assert_nil ClaudeHandoff::RateLimitSample.from_h({})
    assert_nil ClaudeHandoff::RateLimitSample.from_h('windows' => [])
    assert_nil ClaudeHandoff::RateLimitSample.from_h('windows' => [{ 'name' => 'x' }])
  end

  def test_from_statusline_ignores_a_payload_without_rate_limits
    assert_nil ClaudeHandoff::RateLimitSample.from_statusline('session_id' => 's')
  end
end
