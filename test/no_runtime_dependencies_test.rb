# frozen_string_literal: true

require_relative 'test_helper'

# cld must run on the Ruby standard library alone. That keeps the Homebrew
# formula trivial, lets bin/cld run straight from a checkout, and keeps the
# statusline sidecar — which runs on every render of the user's prompt — fast
# to start.
#
# The Gemfile exists for development tooling only. These tests fail the moment
# something in lib/ or bin/ starts depending on a gem.
class NoRuntimeDependenciesTest < Minitest::Test
  REPO_ROOT = HandoffTest::REPO_ROOT

  # Running under `bundle exec` exports RUBYOPT=-rbundler/setup, which every
  # child process inherits. That re-enables gem loading and would defeat
  # --disable-gems entirely, turning these tests into silent false passes — so
  # the bundler environment has to be scrubbed from the child.
  CLEAN_ENV = {
    'RUBYOPT' => nil, 'RUBYLIB' => nil,
    'BUNDLE_GEMFILE' => nil, 'BUNDLE_PATH' => nil, 'BUNDLE_BIN_PATH' => nil,
    'GEM_HOME' => nil, 'GEM_PATH' => nil
  }.freeze

  def capture_without_gems(*args)
    Open3.capture2e(CLEAN_ENV, RbConfig.ruby, '--disable-gems', *args, unsetenv_others: false)
  end

  # Proves the harness works: with RubyGems genuinely disabled, requiring a gem
  # must fail. If this ever passes, the two tests below mean nothing.
  def test_disabling_rubygems_really_does_block_gem_loading
    _out, status = capture_without_gems('-e', 'require "minitest"')

    refute status.success?,
           '--disable-gems did not block a gem require; the guard below is not testing anything'
  end

  # RubyGems is what makes a `require` of a gem resolve. With it switched off,
  # anything outside the standard library fails to load.
  def test_the_library_loads_with_rubygems_disabled
    out, status = capture_without_gems(
      "-I#{File.join(REPO_ROOT, 'lib')}", '-e', 'require "claude_handoff"; print "ok"'
    )

    assert status.success?, "loading failed without RubyGems:\n#{out}"
    assert_equal 'ok', out
  end

  def test_the_executable_runs_with_rubygems_disabled
    out, status = capture_without_gems(HandoffTest::EXE, 'version')

    assert status.success?, "bin/cld failed without RubyGems:\n#{out}"
    assert_equal ClaudeHandoff::VERSION, out.strip
  end

  def test_no_bundler_or_gem_requires_in_shipped_code
    offenders = shipped_files.select do |file|
      File.read(file).match?(/^\s*require\s+["'](bundler|rubygems)/)
    end

    assert_empty offenders, 'shipped code must not require bundler or rubygems'
  end

  # Guards the Gemfile itself: every gem must sit in a development group, so a
  # runtime dependency cannot be added without this failing.
  def test_gemfile_declares_no_runtime_gems
    gemfile = File.join(REPO_ROOT, 'Gemfile')
    skip 'no Gemfile in this checkout' unless File.file?(gemfile)

    outside_group = false
    depth = 0

    File.readlines(gemfile).each do |line|
      stripped = line.strip
      next if stripped.empty? || stripped.start_with?('#')

      depth += 1 if stripped.start_with?('group ')
      depth -= 1 if stripped == 'end' && depth.positive?
      outside_group = true if stripped.start_with?('gem ') && depth.zero?
    end

    refute outside_group,
           'every gem in the Gemfile must be inside a development/test group — ' \
           'cld has no runtime dependencies'
  end

  private

  def shipped_files
    Dir[File.join(REPO_ROOT, 'lib', '**', '*.rb')] + [HandoffTest::EXE]
  end
end
