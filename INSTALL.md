# Installing Tally

A menu bar app that shows your live claude.ai usage, and flags when a local model
(Ollama / LM Studio) is working. **macOS 13 (Ventura) or later.**

> **Unofficial** — not affiliated with or endorsed by Anthropic. It shows *your*
> usage, read through *your* own claude.ai login on your Mac. Nothing is sent
> anywhere else.

## Steps

1. **Get the app from Releases.** On this project's GitHub page, open the
   **Releases** section (right-hand sidebar) and download the
   **`Tally-<version>.zip`** asset (e.g. `Tally-1.4.zip`) from the latest
   release's **Assets**.
   > ⚠️ Do **not** use the green **Code → Download ZIP** button — that gives you
   > the *source code*, not the app.
2. **Double-click the zip.** macOS unzips it and **`Tally.app` appears right next
   to the zip** (you can't browse *inside* a `.zip` in Finder — double-clicking
   to extract it is how you open it).
3. **Drag `Tally.app` into your Applications folder.**
4. **Double-click it.** Releases are signed with an Apple Developer ID and
   notarized by Apple, so it opens normally — no right-click, no security
   warnings, no Terminal commands.
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
- If you run **Ollama** or **LM Studio**, a green dot appears in the menu bar
  while a local model is generating, and you get a notification when a long job
  finishes. Turn it off under *Preferences → Local Models*.

## If you built it yourself

A copy you build in Xcode is signed **ad-hoc** rather than with a Developer ID,
so macOS will block the first launch. Right-click (or Control-click) `Tally.app`
→ **Open** → **Open**. Once only. If macOS says it's *"damaged"*, it isn't —
that's just the download flag; clear it with:

```
xattr -dr com.apple.quarantine /Applications/Tally.app
```

This only applies to your own builds. Downloads from Releases are notarized and
need none of it.
