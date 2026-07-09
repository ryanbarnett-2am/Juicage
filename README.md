# ClaudeUsage

A lightweight macOS **menu bar app** that shows your live [claude.ai](https://claude.ai)
usage at a glance — session, weekly, and per-model limits — with a colored ring
that fills as you go and a forecast of whether you're on pace to hit a limit.
No dock icon; it runs quietly in the background and refreshes on its own.

> **Unofficial.** This project is not affiliated with, endorsed by, or supported
> by Anthropic. It reads usage data from claude.ai's own web session using an
> **undocumented internal API**, which can change or stop working at any time.
> Use at your own discretion and in line with Anthropic's Terms of Service.

## Features

- **Menu bar ring** — a progress ring that fills with your current-session
  usage and turns orange at 60%, red at 80%.
- **Detail popover** — click the ring for per-workspace bars: current session,
  weekly (all models), and a bar for each per-model cap (e.g. Fable) that your
  account has. Shows all workspaces your login belongs to.
- **Pace forecast** — projects your recent burn rate forward and tells you, in
  time, whether you're **ahead** ("~3h 40m to spare") or **behind** ("on pace to
  hit limit ~2h 15m early"). A ⚠ and red ring appear when you're on track to
  hit a limit before it resets.
- **Service status** — if claude.ai is having an outage, the ring is replaced by
  a red/orange dot and a banner names the issue.
- **Runs quietly** — refreshes every ~3 minutes, survives macOS App Nap, and can
  launch at login (right-click the ring → *Launch at Login*).

## How it works

The app keeps a hidden `WKWebView` parked on `claude.ai` and, every few minutes,
calls the site's own usage API with your logged-in cookies:

- `GET /api/organizations` → your workspaces
- `GET /api/organizations/{id}/usage` → usage JSON per workspace

There's **no HTML scraping and no browser automation** — it just reads the same
structured data the settings page uses.

## Build & run

Requires **Xcode** (macOS 13 Ventura or later).

1. Open `ClaudeUsage.xcodeproj` in Xcode.
2. Press **⌘R** to build and run.
3. The first launch shows a sign-in window — log into claude.ai once. Your login
   is remembered after that.

The app is signed to run locally (ad-hoc), so if you move a built copy to
another Mac you may need to right-click → **Open** the first time to get past
Gatekeeper.

## Privacy

ClaudeUsage talks only to `claude.ai` and `status.claude.com`. Your login lives
in the app's own web-view cookie store on your Mac — **no API keys or credentials
are stored in the code**, and nothing is sent to any third party.

## A note on reliability

Because it depends on an undocumented API, the numbers can stop loading if
claude.ai changes how that data is shaped (it has happened before). When that
occurs the popover shows a "Couldn't load usage" state so you know it's broken
rather than silently wrong. Fixes usually mean updating the small bit of parsing
in `UsageFetcher.swift`.

## License

[MIT](LICENSE) © 2026 Ryan Barnett
