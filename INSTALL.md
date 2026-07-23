# Installing Tally

A menu bar app that shows your live claude.ai usage. **macOS 13 (Ventura) or later.**

> **Unofficial** — not affiliated with or endorsed by Anthropic. It shows *your*
> usage, read through *your* own claude.ai login on your Mac. Nothing is sent
> anywhere else.

## Steps

1. **Get the app from Releases.** On this project's GitHub page, open the
   **Releases** section (right-hand sidebar) and download **`Tally.zip`** from the
   latest release's **Assets**.
   > ⚠️ Do **not** use the green **Code → Download ZIP** button — that gives you
   > the *source code*, not the app.
2. **Double-click `Tally.zip`.** macOS unzips it and **`Tally.app` appears right
   next to the zip** (you can't browse *inside* a `.zip` in Finder — double-clicking
   to extract it is how you open it).
3. **Drag that `Tally.app` into your Applications folder.**
4. **First launch needs one extra step** (the app isn't from the App Store):
   - **Right-click** the app → **Open** → **Open**.
   - If macOS still blocks it, open **System Settings → Privacy & Security**,
     scroll down to *"Tally was blocked…"* and click **Open Anyway**, then
     open the app again.
5. If you ever see *"Tally is damaged and can't be opened,"* it's just the
   download-quarantine flag. Open **Terminal** and run:
   ```
   xattr -dr com.apple.quarantine /Applications/Tally.app
   ```
   then open the app again.
6. **Sign in** to claude.ai once in the window that appears. Your login is
   remembered after that.
7. A **ring** appears in your menu bar — outer = session, inner = weekly.
   - **Left-click** it for the detail popover.
   - **Right-click** it for Refresh, Preferences, Launch at Login, and Quit.

## Notes

- It refreshes on its own every few minutes; no buttons to press.
- Runs only in the menu bar (no dock icon).
- Because it reads claude.ai's own (undocumented) usage data, it may occasionally
  stop working if claude.ai changes that data's format. If usage won't load,
  check for an update.
