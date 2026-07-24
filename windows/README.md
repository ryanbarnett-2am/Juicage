# Tally for Windows

Electron port of the Tally macOS menu bar app — a usage meter for
[Claude.ai](https://claude.ai) that lives in the Windows system tray.

Same architecture as the Mac app: a hidden browser window stays parked on
claude.ai with your logged-in cookies, and every 3 minutes the app calls the
site's own usage API (`/api/organizations` + `/api/organizations/{id}/usage`).
No HTML scraping, no browser automation.

## Run from source

Requires Node.js (LTS).

```bash
cd windows
npm install
npm start
```

On first run, click the tray ring → **Sign in to Claude…** and log into
claude.ai once. Numbers appear within a few seconds and the login is remembered
(cookies persist in the app's own profile under `%APPDATA%/tally`).

## Files

| File | Purpose |
|------|---------|
| `main.js` | Main process: tray icon + tooltip, hidden fetch window, login window, popover management, 3-min poll loop, usage JSON parsing (Raven-based team/personal detection — do not switch to plan-tier capabilities). |
| `icon.html` | Off-screen canvas that renders the tray progress ring (gray = no data, orange ≥60%, red ≥80%) and returns it as a PNG data URL. |
| `popover.html` | The click popover: per-workspace session/weekly/per-model bars, reset countdowns, extra-usage credits, error display. |
| `preload.js` | IPC bridge for the popover (sign in / refresh / open site / quit). |

## Notes

- The Windows tray cannot show text next to the icon (unlike the macOS menu
  bar), so the compact `P12% 4h37m` readout from the Mac app lives in the
  tray tooltip and the popover instead.
- The user agent is scrubbed of the `Electron/x.y` token so claude.ai and
  Cloudflare treat the hidden window as a normal Chrome browser.
- If usage stops loading, check the API endpoints/JSON shape first (see
  `PROJECT_SUMMARY.md` in the Mac repo) — don't scrape the DOM.
