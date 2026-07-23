# Installing Tally

A menu bar app that shows your live claude.ai usage. **macOS 13 (Ventura) or later.**

> **Unofficial** — not affiliated with or endorsed by Anthropic. It shows *your*
> usage, read through *your* own claude.ai login on your Mac. Nothing is sent
> anywhere else.

## Steps

1. **Download** `Tally.zip` and double-click it to unzip.
2. **Drag `Tally.app` into your Applications folder.**
3. **First launch needs one extra step** (the app isn't from the App Store):
   - **Right-click** the app → **Open** → **Open**.
   - If macOS still blocks it, open **System Settings → Privacy & Security**,
     scroll down to *"Tally was blocked…"* and click **Open Anyway**, then
     open the app again.
4. If you ever see *"Tally is damaged and can't be opened,"* it's just the
   download-quarantine flag. Open **Terminal** and run:
   ```
   xattr -dr com.apple.quarantine /Applications/Tally.app
   ```
   then open the app again.
5. **Sign in** to claude.ai once in the window that appears. Your login is
   remembered after that.
6. A **ring** appears in your menu bar — outer = session, inner = weekly.
   - **Left-click** it for the detail popover.
   - **Right-click** it for Refresh, Preferences, Launch at Login, and Quit.

## Notes

- It refreshes on its own every few minutes; no buttons to press.
- Runs only in the menu bar (no dock icon).
- Because it reads claude.ai's own (undocumented) usage data, it may occasionally
  stop working if claude.ai changes that data's format. If usage won't load,
  check for an update.
