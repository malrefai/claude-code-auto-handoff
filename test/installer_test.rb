# frozen_string_literal: true

require_relative 'test_helper'

class InstallerTest < Minitest::Test
  include HandoffTest::Sandbox

  def installer
    ClaudeHandoff::Installer.new(
      state_root: state_root, settings_path: settings_path, out: StringIO.new
    )
  end

  def settings = JSON.parse(File.read(settings_path))

  def write_settings(hash)
    File.write(settings_path, JSON.pretty_generate(hash))
  end

  def test_installs_into_an_empty_settings_file
    write_settings({})
    installer.install

    assert_equal 'command', settings.dig('statusLine', 'type')
    assert_includes settings.dig('statusLine', 'command'), 'cld statusline'
    assert_includes settings.dig('statusLine', 'command'), 'statusline'
  end

  def test_creates_settings_when_the_file_does_not_exist
    installer.install

    assert_path_exists settings_path
    assert_includes settings.dig('statusLine', 'command'), 'cld statusline'
  end

  def test_preserves_unrelated_settings
    write_settings({ 'model' => 'opus', 'theme' => 'dark', 'enabledPlugins' => { 'a' => true } })
    installer.install

    assert_equal 'opus', settings['model']
    assert_equal 'dark', settings['theme']
    assert_equal({ 'a' => true }, settings['enabledPlugins'])
  end

  def test_preserves_and_chains_an_existing_statusline
    write_settings({ 'statusLine' => { 'type' => 'command', 'command' => 'echo MY-PROMPT' } })
    installer.install

    assert_includes settings.dig('statusLine', 'command'), 'cld statusline'
    assert_equal 'echo MY-PROMPT', File.read(File.join(state_root, 'inner-statusline'))
  end

  def test_install_is_idempotent
    write_settings({ 'statusLine' => { 'type' => 'command', 'command' => 'echo MY-PROMPT' } })
    installer.install
    installer.install

    # The second install must not capture our own sidecar as the inner command.
    assert_equal 'echo MY-PROMPT', File.read(File.join(state_root, 'inner-statusline'))
  end

  def test_uninstall_restores_the_previous_statusline
    write_settings({ 'model' => 'opus',
                     'statusLine' => { 'type' => 'command', 'command' => 'echo MY-PROMPT' } })
    installer.install
    installer.uninstall

    assert_equal 'echo MY-PROMPT', settings.dig('statusLine', 'command')
    assert_equal 'opus', settings['model']
    refute_path_exists File.join(state_root, 'inner-statusline')
  end

  def test_uninstall_removes_statusline_entirely_when_there_was_none_before
    write_settings({ 'model' => 'opus' })
    installer.install
    installer.uninstall

    refute settings.key?('statusLine')
    assert_equal 'opus', settings['model']
  end

  def test_full_round_trip_leaves_settings_identical
    original = { 'model' => 'opus', 'theme' => 'dark',
                 'statusLine' => { 'type' => 'command', 'command' => 'echo HI' } }
    write_settings(original)
    installer.install
    installer.uninstall

    assert_equal original, settings
  end

  def test_uninstall_is_a_no_op_when_not_installed
    write_settings({ 'model' => 'opus' })
    out = StringIO.new
    ClaudeHandoff::Installer.new(
      state_root: state_root, settings_path: settings_path, out: out
    ).uninstall

    assert_includes out.string, 'not installed'
    assert_equal({ 'model' => 'opus' }, settings)
  end

  def test_installed_predicate
    write_settings({})
    refute installer.installed?
    installer.install
    assert installer.installed?
  end

  def test_malformed_settings_raises_a_clear_error
    File.write(settings_path, '{ not json')

    error = assert_raises(ClaudeHandoff::Error) { installer.install }
    assert_includes error.message, 'not valid JSON'
  end
end
