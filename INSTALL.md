# Installing Tally

A menu bar app that shows your live claude.ai usage. **macOS 13 (Ventura) or later.**

> **Unofficial** — not affiliated with or endorsed by Anthropic. It shows *your*
> usage, read through *your* own claude.ai login on your Mac. Nothing is sent
> anywhere else.

## Steps

1. **Get the app from Releases.** On this project's GitHub page, open the
   **Releases** section (right-hand sidebar) and download the **`Tally-<version>.zip`** asset (e.g.
   `Tally-1.3.zip`) from the latest release's **Assets**.
   > ⚠️ Do **not** use the green **Code → Download ZIP** button — that gives you
   > the *source code*, not the app.
2. **Double-click that zip.** macOS unzips it and **`Tally.app` appears right
   next to the zip** (you can't browse *inside* a `.zip` in Finder — double-clicking
   to extract it is how you open it).
3. **Drag that `Tally.app` into your Applications folder.**
4. **First launch — don't double-click it.** Because this app isn't distributed
   through the App Store, macOS will refuse a normal double-click. Instead:
   - **Right-click** (or Control-click) `Tally.app` → choose **Open** →
     then click **Open** in the dialog that appears.
   - You only have to do this **once**. After that it opens normally.
5. **If macOS still blocks it**, open **System Settings → Privacy & Security**,
   scroll down until you see *"Tally was blocked from use…"*, click
   **Open Anyway**, then open the app again.
6. **If it says "Tally is damaged and can't be opened"** — it isn't damaged,
   that's just macOS's download flag. Open the **Terminal** app and paste this,
   then press Return:
   ```
   xattr -dr com.apple.quarantine /Applications/Tally.app
   ```
   Then open Tally again. (This is safe — it only clears the "downloaded from
   the internet" marker.)
7. **Sign in** to claude.ai once in the window that appears. Your login is
   remembered after that.
8. A **ring** appears in your menu bar — outer = session, inner = weekly.
   - **Left-click** it for the detail popover.
   - **Right-click** it for Refresh, Preferences, Launch at Login, and Quit.

## Notes

- It refreshes on its own every few minutes; no buttons to press.
- Runs only in the menu bar (no dock icon).
- Because it reads claude.ai's own (undocumented) usage data, it may occasionally
  stop working if claude.ai changes that data's format. If usage won't load,
  check for an update.
- If you run **Ollama** or **LM Studio**, a green dot appears in the menu bar
  while a local model is generating, and you get a notification when a long job
  finishes. Turn it off under *Preferences → Local Models*.
