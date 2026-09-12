# frozen_string_literal: true

require_relative 'test_helper'

class TranscriptTest < Minitest::Test
  include HandoffTest::Sandbox

  def turns_for(records)
    ClaudeHandoff::Transcript.new(write_transcript(records)).turns
  end

  def test_reads_user_and_assistant_text
    turns = turns_for([user_record('do the thing'), assistant_record('doing it')])

    assert_equal %w[user assistant], turns.map(&:role)
    assert_equal ['do the thing', 'doing it'], turns.map(&:text)
  end

  def test_excludes_sidechains
    turns = turns_for([user_record('main'), assistant_record('SUBAGENT', sidechain: true)])

    assert_equal ['main'], turns.map(&:text)
  end

  def test_excludes_tool_blocks_keeping_only_text
    turns = turns_for([assistant_record('visible prose', tool: true)])

    assert_equal ['visible prose'], turns.map(&:text)
    refute_includes turns.first.text, 'tool_use'
  end

  def test_skips_non_conversation_records
    turns = turns_for([
                        { 'type' => 'file-history-snapshot', 'snapshot' => {} },
                        { 'type' => 'mode', 'mode' => 'normal' },
                        user_record('only me')
                      ])

    assert_equal ['only me'], turns.map(&:text)
  end

  def test_skips_records_with_empty_text
    turns = turns_for([user_record(''), assistant_record('   '), user_record('real')])

    assert_equal ['real'], turns.map(&:text)
  end

  def test_tolerates_malformed_lines
    path = File.join(sandbox, 'broken.jsonl')
    File.write(path, "#{JSON.generate(user_record('good'))}\nnot json at all\n\n")

    assert_equal ['good'], ClaudeHandoff::Transcript.new(path).turns.map(&:text)
  end

  def test_missing_file_yields_no_turns
    assert_empty ClaudeHandoff::Transcript.new('/nonexistent/x.jsonl').turns
    assert_empty ClaudeHandoff::Transcript.new(nil).turns
  end
end

class HandoffBuilderTest < Minitest::Test
  include HandoffTest::Sandbox

  def build(records, word_budget: 4000)
    transcript = ClaudeHandoff::Transcript.new(write_transcript(records))
    ClaudeHandoff::HandoffBuilder.new(
      transcript: transcript, project_dir: project, word_budget: word_budget
    ).build
  end

  def test_returns_nil_for_an_empty_conversation
    assert_nil build([])
  end

  def test_includes_the_project_path_and_header
    text = build([user_record('goal'), assistant_record('ok')])

    assert_includes text, '# Session handoff'
    assert_includes text, project
  end

  def test_always_keeps_the_first_user_message
    records = [user_record('THE ORIGINAL GOAL')]
    60.times { |i| records << assistant_record("filler #{i} " * 50) }

    text = build(records, word_budget: 200)

    assert_includes text, 'THE ORIGINAL GOAL'
    assert_includes text, '## The original request'
  end

  def test_keeps_the_most_recent_exchange
    records = [user_record('start')]
    30.times { |i| records << assistant_record("middle #{i}") }
    records << assistant_record('THE VERY LAST THING')

    text = build(records, word_budget: 100)

    assert_includes text, 'THE VERY LAST THING'
  end

  def test_condenses_and_counts_what_it_drops
    records = [user_record('start')]
    80.times { |i| records << assistant_record("turn #{i} " * 30) }

    text = build(records, word_budget: 150)

    assert_match(/\d+ earlier turns? omitted/, text)
  end

  def test_respects_the_word_budget_approximately
    records = [user_record('start')]
    100.times { |i| records << assistant_record(('word ' * 100) + i.to_s) }

    text = build(records, word_budget: 500)
    # Budget governs conversation content; the header and section titles are
    # fixed overhead on top of it.
    assert_operator text.split(/\s+/).length, :<, 1200
  end

  def test_excludes_sidechains_and_tool_noise
    text = build([
                   user_record('goal'),
                   assistant_record('SIDECHAIN TEXT', sidechain: true),
                   assistant_record('real answer', tool: true)
                 ])

    refute_includes text, 'SIDECHAIN TEXT'
    refute_includes text, 'tool_use'
    assert_includes text, 'real answer'
  end

  def test_contains_no_ansi_escapes
    text = build([user_record('goal'), assistant_record('done')])

    refute_includes text, "\e["
  end

  def test_reports_a_clean_working_tree
    system('git', 'init', '-q', project, out: File::NULL, err: File::NULL)
    text = build([user_record('goal')])

    assert_includes text, 'working tree was clean'
  end

  def test_reports_uncommitted_changes
    system('git', 'init', '-q', project, out: File::NULL, err: File::NULL)
    File.write(File.join(project, 'dirty.txt'), 'x')
    text = build([user_record('goal')])

    assert_includes text, 'Uncommitted changes'
    assert_includes text, 'dirty.txt'
  end

  def test_write_to_creates_the_file_and_returns_its_path
    transcript = ClaudeHandoff::Transcript.new(write_transcript([user_record('goal')]))
    target = File.join(state_root, 'projects', 'x', 'handoff.md')

    path = ClaudeHandoff::HandoffBuilder.new(
      transcript: transcript, project_dir: project, word_budget: 100
    ).write_to(target)

    assert_equal target, path
    assert_includes File.read(target), 'goal'
  end

  def test_write_to_returns_nil_when_there_is_nothing_to_write
    transcript = ClaudeHandoff::Transcript.new('/nonexistent')
    target = File.join(state_root, 'handoff.md')

    result = ClaudeHandoff::HandoffBuilder.new(
      transcript: transcript, project_dir: project
    ).write_to(target)

    assert_nil result
    refute_path_exists target
  end
end
