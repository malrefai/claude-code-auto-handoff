# frozen_string_literal: true

# Homebrew formula for cld.
#
# Publishing a release:
#   1. Bump VERSION in lib/claude_handoff/version.rb and tag it:
#        git tag v0.1.0 && git push origin v0.1.0
#   2. Get the checksum:
#        rake build[0.1.0]     # prints the url and the command below
#        curl -sL <url> | shasum -a 256
#   3. Replace the sha256 placeholder here and commit.
class Cld < Formula
  desc 'Claude Code wrapper that resumes automatically after a usage limit clears'
  homepage 'https://github.com/malrefai/claude-code-auto-handoff'
  url 'https://github.com/malrefai/claude-code-auto-handoff/archive/refs/tags/v0.1.0.tar.gz'
  # PLACEHOLDER — replace with the real checksum before publishing the tag.
  sha256 '0000000000000000000000000000000000000000000000000000000000000000'
  license 'MIT'
  head 'https://github.com/malrefai/claude-code-auto-handoff.git', branch: 'main'

  # macOS still ships Ruby 2.6 at /usr/bin/ruby, which is too old for this code.
  depends_on 'ruby'

  def install
    libexec.install 'bin', 'lib'
    (bin / 'cld').write_env_script libexec / 'bin/cld',
                                   PATH: "#{Formula['ruby'].opt_bin}:$PATH"
  end

  def caveats
    <<~EOS
      Wire up the statusline sidecar — this is how cld learns when your usage
      window resets:

        cld install

      Then use `cld` anywhere you would have run `claude`.
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/cld version")

    # The statusline sidecar must consume a payload on stdin, record it, and
    # exit cleanly — a failure there would break the user's prompt.
    ENV['CLAUDE_HANDOFF_HOME'] = testpath / 'state'
    payload = {
      session_id: 'test-session',
      transcript_path: "#{testpath}/transcript.jsonl",
      cwd: testpath.to_s,
      workspace: { project_dir: testpath.to_s },
      rate_limits: {
        five_hour: { used_percentage: 100.0, resets_at: Time.now.to_i + 3600 },
        seven_day: { used_percentage: 12.5, resets_at: Time.now.to_i + 86_400 }
      }
    }.to_json

    pipe_output("#{bin}/cld statusline", payload, 0)

    recorded = Dir[testpath / 'state/projects/*/limits.json'].first
    assert_predicate Pathname.new(recorded.to_s), :exist?, 'statusline recorded no state'
    assert_match 'five_hour', File.read(recorded)
    assert_match 'seven_day', File.read(recorded)

    # `status` must run without a scheduled resume present.
    assert_match 'Pending resume: none', shell_output("#{bin}/cld status", 0)
  end
end
