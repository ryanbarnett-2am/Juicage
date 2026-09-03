# Juicage — what it is

## The job

**Know where you stand with Claude, without going to look.**

You're mid-task and about to start something expensive. Do you have the runway,
or will you get cut off halfway and wait for a reset? Answering that today means
stopping, switching context, and running a command — by which point you've
already made the decision badly.

Juicage answers it from the menu bar, continuously, without being asked.

## Who it's for

Someone who uses Claude heavily enough that limits shape their day: several
hours most days, often more than one account, frequently in Claude Code but not
only there. They notice when they run out. They'd change *when* they work if
they knew what it cost them.

Not for occasional users — they never hit a limit and have nothing to monitor.

## What it does that `/usage` doesn't

Claude Code ships `/usage`, which is richer than Juicage for one machine's
Claude Code activity: real token counts, per-model cost, context diagnostics.
The meter part is commodity now. What remains ours:

- **Ambient.** Always visible. `/usage` requires being in Claude Code and typing
  a command, so you only check when you already suspect a problem — too late.
- **Cross-surface.** `/usage` says "this machine only, excludes claude.ai".
  Juicage reads the account-wide limits, whatever burned them.
- **Memory.** Peaks per window, trends, "maxed 3 of the last 8 weeks". `/usage`
  shows the present. History cannot be backfilled, which makes it defensible.
- **Timing.** When the session window opened, what's left of today, when you'll
  run out at this pace.
- **Local models.** Ollama and LM Studio activity. Nothing else does this.

The meter is the hook. **The memory and the timing are the product.**

## What it deliberately isn't

- **Not a scheduler or an agent.** It reports; it doesn't spend your quota. The
  line between "your window closes in 40 minutes with 70% unused" and firing
  requests to reshape that window is one we hold deliberately.
- **Not a team surveillance tool.** Per-developer productivity metrics are a
  different product with different obligations (#10).
- **Not sold.** The App Store is effectively closed to it, and charging for a
  tool built on an undocumented API changes the calculus considerably.
- **Not a general dashboard.** It fits in a menu bar popover. Anything needing
  a real window earns one on merit (#3), not by accretion.

## Constraints that shape everything

- **The usage API is undocumented.** It can change without notice. When it does,
  the app shows "Couldn't load usage" rather than stale numbers presented as
  live — being visibly broken beats being quietly wrong.
- **Percent is the only honest unit.** claude.ai returns no token counts, and
  the percentage is model-weighted, so it can't be converted to tokens.
- **Unsandboxed by necessity.** Local-model monitoring needs a log file and a
  CLI, both blocked by the App Sandbox. Documented in the README, because a
  menu bar app reading your Claude session should explain itself.
- **The bundle identifier is frozen** at `twoam.Tally`. macOS keys the saved
  sign-in to it; changing it signs everyone out for no visible benefit.

## How we decide

Ship when a change answers a question a user actually asked, in fewer steps than
before. Two views that answer the same question is one too many; a view that
answers a question nobody asked is decoration.

When in doubt, prefer the version that can be wrong out loud.
