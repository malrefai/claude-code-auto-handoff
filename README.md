# cld

**Claude Code that picks up where it left off — even if you've gone to bed.**

`cld` is a drop-in replacement for the `claude` command. You use it exactly the
same way. The difference shows up when you run out of usage: `cld` waits for
your limit to reset and then restarts the work for you, without you being there.

```bash
cld                       # instead of: claude
cld --model opus          # all the usual claude options still work
cld status                # check on cld itself
```

---

## Contents

- [Cheat sheet](#cheat-sheet)
- [Words you'll see](#words-youll-see)
- [The problem, in plain terms](#the-problem-in-plain-terms)
- [What cld does about it](#what-cld-does-about-it)
- [Do you actually need this?](#do-you-actually-need-this)
- [Installing](#installing)
- [Your first run](#your-first-run)
- [A complete example](#a-complete-example)
- [All the commands](#all-the-commands)
- [The handoff file](#the-handoff-file)
- [Options](#options)
- [Settings file](#settings-file)
- [What cld does not do](#what-cld-does-not-do)
- [How it works inside](#how-it-works-inside)
- [Staying safe](#staying-safe)
- [Troubleshooting](#troubleshooting)
- [Questions people ask](#questions-people-ask)
- [Development](#development)

---

## Cheat sheet

| I want to… | Type this |
| --- | --- |
| Start Claude Code | `cld` |
| Start it with options | `cld --model opus` |
| See if a restart is booked | `cld status` |
| Call off a booked restart | `cld cancel` |
| Restart right now, don't wait | `cld resume-now` |
| Set it up (once, after installing) | `cld install` |
| Remove the setup | `cld uninstall` |
| See all commands | `cld help` |

Files live in `~/.claude/auto-handoff/`. Nothing is written into your project.

---

## Words you'll see

Some terms used throughout this page:

**Terminal** — the black window where you type commands. Closing it stops
whatever was running inside.

**Session** — one continuous conversation with Claude Code, from when you start
it to when you quit.

**Usage limit / budget** — how much Claude you're allowed before you must wait.
You have two: a **5-hour** one and a **7-day (weekly)** one.

**Reset** — the moment a budget refills. Always a specific time, like 3:47 PM.

**Transcript** — the file Claude Code writes recording your conversation. `cld`
reads it to build the handoff.

**Handoff file** — a short summary `cld` writes so the restarted session knows
what it was doing, without paying to replay the whole conversation.

**Statusline** — the small info line at the bottom of a Claude Code session.
`cld` hooks into it to read your budget. Explained in
[Installing](#installing).

**Unattended** — running while you're not there to watch or approve anything.

---

## The problem, in plain terms

Your Claude subscription gives you a budget of usage. When you use it all up,
Claude Code stops working until the budget refills. Every limit has an exact
moment when it clears.

There are **two** budgets, and this matters later:

| Budget | Refills after |
| --- | --- |
| **5-hour limit** | a few hours |
| **7-day limit** (weekly) | up to a week |

Now picture this. It's 11 PM, Claude Code is halfway through building something
for you, and your budget runs out. It can't continue until 4 AM.

You go to bed and close your laptop.

**At 4 AM, nothing happens.** Claude Code is a program running in your terminal
window. When you closed it, the program stopped. There's nothing left running to
notice that your budget refilled.

You wake up at 8 AM and find exactly what you left at 11 PM. Five hours of
waiting, and no work got done.

## What cld does about it

`cld` watches for that situation. When Claude Code shuts down while your budget
is empty, `cld` leaves behind a small background timer. That timer isn't Claude
Code — it's a tiny separate program whose only job is to wait.

At 4 AM the timer wakes up and starts Claude Code again to continue your task.

```
11:00 PM   Budget runs out
           You close the terminal and go to bed
           cld quietly sets a timer for 4 AM
 4:00 AM   Timer fires. Claude Code starts up and continues working.
 8:00 AM   You wake up. The work is done.
```

To keep the restarted session cheap, `cld` doesn't replay your entire
conversation. It writes a short summary — a **handoff file** — and gives the new
session that instead.

---

## Do you actually need this?

**Be honest with yourself here, because often the answer is no.**

Claude Code can already do this by itself. When you hit the limit, it usually
shows you this:

```
Usage limit reached · continuing automatically when it resets · esc to cancel
```

That means: *"I'll wait and carry on by myself."* And it does — keeping your
**entire** conversation, which is better than anything `cld` can offer.

But there's a catch: **it only works if you leave the terminal window open.**
Claude Code says so itself when you don't:

> Claude Code exited during the wait, so the task will not resume on its own
> when the usage limit resets.

So ask yourself: **when I run out of budget, do I leave the terminal open, or do
I close it?**

- **I leave it open** → You don't need `cld`. Claude Code has you covered.
- **I close it / my laptop dies / my SSH connection drops** → `cld` is for you.

### When Claude Code *won't* wait by itself

There are also situations where the built-in waiting never kicks in at all. If
you've noticed you always have to restart things manually, one of these is
probably why:

| Situation | What you'd see |
| --- | --- |
| The reset is more than 24 hours away | `Automatic continue stopped · the usage limit now resets more than 24 hours out` |
| The feature was switched off | `Automatic continue was turned off` |
| You pressed Esc or Ctrl+C, or typed a message while it was waiting | the waiting just stops |
| Claude Code updated itself and restarted | the waiting just stops |
| You're on API billing, or using overage credits | it never starts waiting |

**That first row is the big one.** Remember the two budgets? Claude Code only
waits for short resets. If it's your **weekly** budget that ran out, the reset
could be three days away — Claude Code won't sit there for that, so it hands the
decision back to you.

`cld` handles both budgets, which is exactly where it earns its keep.

To check which budget is the problem, type `/usage` inside Claude Code. To see
or change the waiting behaviour, type `/rate-limit-options`.

---

## Installing

### Step 1 — Install the program

```bash
brew tap malrefai/cld https://github.com/malrefai/claude-code-auto-handoff
brew install cld
```

<sub>No release tagged yet? From a local copy of this repo you can run
`brew install --formula ./Formula/cld.rb`, or simply use `bin/cld` directly —
it only needs Ruby 3.0 or newer.</sub>

### Step 2 — Run the setup command

```bash
cld install
```

You'll see:

```
installed the statusline sidecar

Done. Run `cld` instead of `claude`, and check state with `cld status`.
```

**What this step is for.** `cld` needs to know the exact time your budget
refills. That number is only available in one place: the data Claude Code sends
to something called a *statusline command*. `cld install` registers itself there
so it can read it.

It edits one file, `~/.claude/settings.json`, adding this:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/path/to/ruby /path/to/cld statusline"
  }
}
```

Your other settings are left completely alone.

**Already using a statusline?** Claude Code only allows one, so `cld` takes the
slot — but it does not throw yours away. Yours gets saved and run right
afterwards, so **your prompt looks exactly the same as before.** You won't
notice any change.

To undo everything later: `cld uninstall`.

### That's it — no alias needed

`cld` is the command itself. Nothing to add to your `.zshrc`.

---

## Your first run

Go to any project and start Claude Code with `cld` instead of `claude`:

```bash
cd ~/projects/my-app
cld
```

Claude Code opens exactly as it always does. **Use it completely normally.**
`cld` is invisible while you work.

Every `claude` option still works, because anything `cld` doesn't recognise is
passed straight through:

```bash
cld --model opus
cld "write me a function that sorts a list"
cld --resume
```

---

## A complete example

Here is the whole thing, start to finish.

### Monday, 11:00 PM — you're working

```bash
cd ~/projects/my-app
cld
```

You ask Claude Code to add discount codes to your checkout. It's partway through
when your weekly budget runs out.

### 11:05 PM — you decide to go to bed

You press Ctrl+C to quit. `cld` notices what just happened and asks:

```
seven-day limit exhausted. Schedule an unattended resume at 2026-09-15 20:00:59 CEST? [Y/n]
```

You press Enter (or just wait 20 seconds — Enter is the default).

### 11:05 PM — cld tells you what it booked

```
The seven-day usage window was exhausted when this session ended.
  Auto-resume scheduled for 2026-09-15 20:00:59 CEST (backend: launchd)
  Strategy: fresh session seeded with /Users/you/.claude/auto-handoff/projects/a1b2c3d4/handoff.md
  Log:      /Users/you/.claude/auto-handoff/projects/a1b2c3d4/resume.log
  Cancel:   cld cancel
```

Reading that:

- **Auto-resume scheduled for** — when it will run
- **backend: launchd** — macOS is holding the schedule, so it survives a reboot
  ([why](#how-it-waits))
- **Strategy** — a fresh session using the summary
- **Log** — where to read what happened afterwards
- **Cancel** — how to call it off

You close the laptop.

### Tuesday — you check on it

```bash
cd ~/projects/my-app
cld status
```

```
Project: /Users/you/projects/my-app
Usage windows (sampled 41003s ago):
  five_hour   33.0% used, resets 2026-09-13 23:09:59 CEST
  seven_day  100.0% used, resets 2026-09-15 19:59:59 CEST <- exhausted
Pending resume: YES at 2026-09-15 20:00:59 CEST (backend: launchd)
Resume log: /Users/you/.claude/auto-handoff/projects/a1b2c3d4/resume.log
```

Still booked. Nothing to do.

### Monday, 8:00 PM — it runs by itself

Your weekly budget refills. The scheduled job starts Claude Code, which reads
the handoff file and carries on with the discount code work.

### Later — you review what happened

```bash
cd ~/projects/my-app
git diff                                              # what changed in your code
cat ~/.claude/auto-handoff/projects/*/resume.log      # what Claude Code did
cld status                                            # confirms: no longer pending
```

If you don't like the changes, `git checkout .` undoes all of them — which is
why [committing before you leave](#staying-safe) matters.

---

## All the commands

### `cld` — start Claude Code

```bash
cld
cld --model opus
cld "fix the bug in checkout.rb"
```

Anything `cld` doesn't recognise goes straight to Claude Code.

If you ever need to send a word that happens to be one of `cld`'s own commands,
put `--` in front of it:

```bash
cld -- status      # sends the literal word "status" to Claude Code
```

### `cld status` — check what's going on

```bash
cld status
```

```
Project: /Users/you/projects/my-app
Usage windows (sampled 3s ago):
  five_hour   33.0% used, resets 2026-09-13 23:09:59 CEST
  seven_day  100.0% used, resets 2026-09-15 19:59:59 CEST <- exhausted
Pending resume: YES at 2026-09-15 20:00:59 CEST (backend: launchd)
Resume log: /Users/you/.claude/auto-handoff/projects/a1b2c3d4/resume.log
```

Reading that:

- **five_hour 33.0%** — a third of your 5-hour budget used, plenty left
- **seven_day 100.0% ← exhausted** — your weekly budget is gone; *this* is what
  stopped you
- **Pending resume: YES** — a restart is booked

If you've never run `cld` in this folder yet:

```
Usage windows: no sample recorded
  (run `cld install`, or this account has no subscription limits)
Pending resume: none
```

Status is **per project**. Each folder gets its own schedule, so run it in the
folder you care about.

### `cld cancel` — call off a scheduled restart

```bash
cld cancel
```

```
Cancelled the pending resume for /Users/you/projects/my-app
```

You don't need this before starting work again — just running `cld` cancels any
pending restart automatically, since you're obviously back at the keyboard.

### `cld resume-now` — don't wait, do it now

```bash
cld resume-now
```

Runs the scheduled restart immediately. Handy for testing, or when your budget
refilled sooner than expected.

### `cld install` / `cld uninstall` — setup and removal

Covered in [Installing](#installing). `uninstall` puts back any statusline you
had before, or removes the entry entirely if you didn't have one.

### `cld version` / `cld help`

```bash
cld version     # 0.1.0
cld help        # full command list
```

### `cld statusline` — not for you

This is the piece Claude Code calls automatically. You never run it by hand.

---

## The handoff file

This is what makes the restarted session cheap.

When Claude Code restarts, it has no memory of your conversation. Two ways to
deal with that:

1. **Replay everything.** Accurate, but you pay for every word again.
2. **Give it a summary.** Much cheaper. This is what `cld` does by default.

The summary is built from Claude Code's own session records, so it comes out as
clean readable text — no screen junk, no colour codes, no tool-call noise.

Here's a real one:

````markdown
# Session handoff

A previous Claude Code session in this project was interrupted by a usage limit.
This file is a condensed record of that session, not a full transcript.

- Project: `/Users/you/projects/my-app`
- Interrupted: 2026-09-12 20:04:00 CEST
- Branch: `main`

## Uncommitted changes at the time of the interruption

```
 M src/checkout.rb
?? src/discount.rb
```

## The original request

add discount code support to checkout

## Earlier in the session (condensed)

_14 earlier turns omitted._

- **assistant:** I'll start by reading checkout.rb to see how totals are …
- **user:** use percentage discounts, not fixed amounts

## Most recent exchanges

### assistant

I've added the Discount class. Next step is wiring it into the total
calculation in checkout.rb.
````

Notice what's included:

- **Where things stand** — branch and uncommitted files, so the new session
  knows what's half-finished
- **Your original request** — always kept, because it states the actual goal
- **The middle, shortened** — one-line excerpts, with a count of what was cut
- **The recent part in full** — the most useful context

It's written to `~/.claude/auto-handoff/`, **never into your project folder**.

### Want the full conversation instead?

```bash
cld --handoff-strategy session
```

**The honest trade-off:** after a few hours the discount Claude gets for
repeated text has expired, so replaying really does cost full price — the
handoff is genuinely cheaper. But a summarised session has *thrown away* the
details, and may spend tokens working out things it used to know. The handoff is
the default because it's usually the better deal, not because it's free.

If a handoff can't be built for some reason, `cld` replays the conversation
rather than starting a session that has no idea what it's meant to do.

---

## Options

`cld`'s own options all start with `--handoff-`. That's deliberate: it
guarantees they can never be confused with one of Claude Code's options.

| Option | Default | What it does |
| --- | --- | --- |
| `--handoff-yes` | off | Skip the confirmation question |
| `--handoff-threshold PCT` | `99` | How full a budget must be to count as used up |
| `--handoff-strategy S` | `handoff` | `handoff` (summary) or `session` (full replay) |
| `--handoff-permission-mode M` | `auto` | How much the restarted session may do on its own |
| `--handoff-scheduler B` | `auto` | `auto`, `detached`, or `launchd` |
| `--handoff-word-budget N` | `4000` | Maximum size of the handoff file, in words |

Examples:

```bash
cld --handoff-yes                       # never ask, just schedule it
cld --handoff-strategy session          # replay the full conversation
cld --handoff-word-budget 8000          # allow a longer summary
cld --handoff-threshold 95 --model opus # mix cld options with claude options
```

### About `--handoff-permission-mode`

This controls how much the *restarted* session is allowed to do while you're
asleep. The default is `auto`, which checks each action and **refuses when it
isn't sure**. That's the right setting for unattended work.

Avoid `acceptEdits` here. The restarted session runs without a screen, so it
can't ask you permission for anything — meaning anything needing approval just
gets refused.

---

## Settings file

Instead of typing options every time, put them in
`~/.claude/auto-handoff/config.yml`:

```yaml
permission_mode: auto
threshold: 99
stale_seconds: 900
skew_seconds: 60
handoff_word_budget: 4000
resume_strategy: handoff   # or: session
scheduler: auto            # or: detached, launchd
launchd_threshold_seconds: 21600
assume_yes: false
```

Two that need explaining:

- **`stale_seconds`** (default 900 = 15 min) — if `cld`'s information about your
  budget is older than this, it's ignored. Stops it acting on yesterday's
  reading.
- **`skew_seconds`** (default 60) — waits an extra minute past the reset, so the
  budget is definitely available.

Anything you type on the command line beats the settings file. Environment
variables sit in between:

| Setting | Environment variable |
| --- | --- |
| `permission_mode` | `CLAUDE_HANDOFF_PERMISSION_MODE` |
| `threshold` | `CLAUDE_HANDOFF_THRESHOLD` |
| `stale_seconds` | `CLAUDE_HANDOFF_STALE_SECONDS` |
| `skew_seconds` | `CLAUDE_HANDOFF_SKEW_SECONDS` |
| `handoff_word_budget` | `CLAUDE_HANDOFF_WORD_BUDGET` |
| `resume_strategy` | `CLAUDE_HANDOFF_RESUME_STRATEGY` |
| `scheduler` | `CLAUDE_HANDOFF_SCHEDULER` |
| `launchd_threshold_seconds` | `CLAUDE_HANDOFF_LAUNCHD_THRESHOLD_SECONDS` |
| `assume_yes` | `CLAUDE_HANDOFF_ASSUME_YES` |
| where files are kept | `CLAUDE_HANDOFF_HOME` |

---

## What cld does not do

Setting expectations honestly:

- **It doesn't give you more usage.** It only helps you use what you already
  have without sitting and waiting.
- **It doesn't make Claude Code faster or smarter.** It's a wrapper, nothing
  more.
- **It doesn't survive a reboot in every case.** Short waits don't — see
  [How it waits](#how-it-waits).
- **It doesn't watch what the restarted session does.** Read the log and
  `git diff` afterwards.
- **It doesn't work on API-key billing.** Those accounts have no subscription
  budgets for it to read, so it stays inert and behaves like plain `claude`.
- **It doesn't remember your conversation.** The restarted session only knows
  what's in the handoff file.

---

## How it works inside

Skip this section unless you're curious.

### Finding out when your budget refills

This is the tricky part. The reset time isn't printed anywhere you can easily
read. It lives in the data Claude Code sends to a statusline command:

```jsonc
"rate_limits": {
  "five_hour": { "used_percentage": 97.4, "resets_at": 1789412400 },
  "seven_day": { "used_percentage": 76.0, "resets_at": 1789930000 }
}
```

That's why `cld install` exists — registering as your statusline is the only
supported way to see those numbers.

### Picking which budget matters

Both budgets are checked. If both are used up, `cld` waits for **whichever
clears last**, because work can't continue until every blocker is gone.

### How it waits

| Method | Used when | Survives a restart of your Mac? |
| --- | --- | --- |
| `detached` | wait is under 6 hours | **No** |
| `launchd` | wait is over 6 hours (macOS only) | **Yes** |

A short wait just needs a small background process. A weekly reset can be days
away, and a background process won't survive you rebooting — so long waits are
handed to macOS itself, as a scheduled job that deletes itself after running.

After restarting your computer, run `cld status` to see if anything's still
booked.

**Why not `cron`?** Anyone who's used cron will ask. A cron entry like
`MIN HOUR * * *` repeats **every day** — it isn't a one-off. The usual trick for
deleting it afterwards only runs if the command succeeded, so a single failure
leaves a job firing at 4 AM forever. cron on macOS also needs special permissions
and gets a stripped-down environment. Not worth it for a wait under a week.

---

## Staying safe

The restarted session writes to your files while you're not watching. Three
habits make that comfortable:

**1. Commit or stash before you leave.** Then `git diff` in the morning shows
you exactly what changed, and `git checkout .` undoes all of it.

**2. Read the log.** Everything is recorded:

```bash
cat ~/.claude/auto-handoff/projects/*/resume.log
```

**3. Know that your project folder stays clean.** Handoff files, logs, and
settings all live in `~/.claude/auto-handoff/`. Nothing is ever written into
your repository.

---

## Troubleshooting

**`cld status` says "no sample recorded"**

`cld` hasn't seen your budget yet. Either you haven't run `cld install`, or you
haven't started a Claude Code session with `cld` since installing. Run
`cld install`, then use `cld` once.

**Nothing gets scheduled even though I ran out**

Check `cld status`. Common causes:

- No budget is at 99% or above — lower it with `--handoff-threshold 95`
- The reset already passed while you were quitting
- You're on API billing, which has no subscription budgets for `cld` to read

**A restart was scheduled but never ran**

Did you reboot? A short wait (`detached`) doesn't survive that. Run `cld status`
to confirm, then `cld resume-now` if your budget has refilled.

**My statusline disappeared**

It shouldn't — `cld` chains to it. Check that your old command was saved:

```bash
cat ~/.claude/auto-handoff/inner-statusline
```

If something's wrong, `cld uninstall` puts everything back.

**I want to remove cld completely**

```bash
cld uninstall                    # restore your settings
brew uninstall cld               # remove the program
rm -rf ~/.claude/auto-handoff    # remove its files
```

---

## Questions people ask

**Does this cost me extra money?**

No. It uses the budget you already pay for. The handoff file exists specifically
to spend *less* of it than replaying a whole conversation would.

**Will it run without asking me?**

Only if you let it. It asks before booking anything, with a 20-second timeout
that defaults to yes. Use `--handoff-yes` to skip the question, or `n` to
decline.

**Can I use it in more than one project?**

Yes. Each folder keeps its own schedule, so two projects can have restarts
booked at the same time without interfering.

**What if I start working again before the restart fires?**

Just run `cld`. It cancels the pending restart automatically.

**Does it work on Linux?**

The `detached` method does. `launchd` is macOS-only, so long waits fall back to
a background process that won't survive a reboot.

**Is my conversation sent anywhere?**

No. The handoff file is written to your own disk and read by Claude Code on your
own machine. `cld` makes no network requests of its own.

**Why is the command called `cld`?**

It's short, and it's what you type dozens of times a day instead of `claude`.

---

## Development

The Ruby version is pinned in `mise.toml`, and [mise](https://mise.jdx.dev)
picks it up automatically:

```bash
mise install              # get Ruby 4.0.4
mise run check            # lint + test — run this before committing
mise run test
mise run lint             # syntax check with warnings enabled
mise run rubocop          # style check
mise run cld -- status    # run the local build
```

You don't need to install gems first: `test` and `lint` depend on
`bundle:install`, so a fresh clone works straight away. That task puts gems in
`vendor/bundle` rather than system-wide, so this project can never clash with
another one on your machine.

> **Use `mise run`, not bare `bundle exec`.** RuboCop pulls in a gem with a
> native extension, compiled against the pinned Ruby. Running `bundle exec`
> under a different Ruby fails with a `libruby` mismatch. `mise run` always uses
> the right one.

### About dependencies

The `Gemfile` contains **development tooling only** — `rake`, `minitest`, and
`rubocop`.

`cld` itself has **no runtime dependencies**; it uses only the Ruby standard
library. That is deliberate, and worth preserving:

- the Homebrew formula stays a few lines, with no bundle step at install time
- `bin/cld` runs straight from a checkout, with nothing installed first
- the statusline sidecar, which runs on every render of your prompt, starts fast

Nothing in `lib/` or `bin/` may `require` a gem. This is **enforced by tests**,
not just documented — `test/no_runtime_dependencies_test.rb` loads the library
with RubyGems switched off, and fails if any gem in the `Gemfile` sits outside a
development group.

### Style

`mise run rubocop` must be clean. The config in `.rubocop.yml` is deliberately
small, and one setting there is a correctness check rather than a style choice:

```yaml
TargetRubyVersion: 3.0
```

The Homebrew formula declares a Ruby 3.0 floor, so the linter is told to check
against 3.0. This caught a real bug — `def backend = raise NotImplementedError`
parses fine on modern Ruby but **not on 3.0**, where an endless method cannot
take a bare command call as its body. If you raise this version, raise the floor
in `Formula/cld.rb` too.

### Tests

```bash
mise run test     # 89 tests
```

They run against a throwaway folder and a fake `claude`, so they never touch
your real setup and need no network. They cover reading the statusline data and
passing it along to your own, every decision about whether to schedule, picking
the right budget, building handoff files, both restart strategies, argument
dispatch and passthrough, setup and removal leaving `settings.json` untouched,
folder names with spaces and apostrophes, and a full end-to-end test that a
scheduled job really does fire.

### Layout

```
bin/cld                  the command

lib/claude_handoff/
  cli.rb                 works out which command you meant
  arguments.rb           splits your flags from Claude Code's
  help.rb                the `cld help` text
  config.rb              settings: flags > environment > config.yml > defaults
  state_store.rb         per-project files, named by a hash of the project path
  rate_limit_sample.rb   the two budgets; works out which one is blocking
  statusline.rb          reads the data, then runs your statusline
  transcript.rb          reads Claude Code's session records
  handoff_builder.rb     writes the summary
  resume.rb              builds the restart command
  scheduler.rb           the two waiting methods (detached, launchd)
  status_report.rb       renders `cld status`
  installer.rb           edits settings.json

Formula/cld.rb           Homebrew formula
```

Requires Ruby 3.0+ and uses no external libraries at runtime.

## License

MIT — see [LICENSE](LICENSE).
