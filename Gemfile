# frozen_string_literal: true

source 'https://rubygems.org'

# No `ruby` directive on purpose: it would stamp the exact interpreter version
# into Gemfile.lock and churn the diff every time someone runs bundler on a
# different Ruby. The version is pinned in mise.toml for development, and the
# 3.0+ floor is declared by the Homebrew formula for installs.

# cld itself has NO runtime dependencies. It uses only the Ruby standard
# library, which is what keeps the Homebrew formula to a few lines with no
# bundle step at install time, and lets `bin/cld` run straight from a checkout.
#
# Never add a runtime gem here. Everything below is development tooling only,
# and nothing in lib/ or bin/ may require it.

group :development, :test do
  gem 'minitest', '~> 5.0'                  # test framework
  gem 'rake', '~> 13.0'                     # task runner: rake test / rake lint
  gem 'rubocop', '~> 1.0', require: false   # style checker: rake rubocop
end
