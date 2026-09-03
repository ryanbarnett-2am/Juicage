# Juicage

Unofficial macOS menu bar app showing claude.ai usage, plus a live indicator for
local Ollama / LM Studio models. Public repo, notarized, self-updating.

Read `docs/PRODUCT.md` for what this is and deliberately isn't, `RELEASING.md`
before shipping anything, and the GitHub issues for the backlog. Those three are
the source of truth — don't reconstruct intent from conversation.

## Layout

| | |
|---|---|
| This repo | `~/Developer/ClaudeUsage` — Swift/SwiftUI menu bar app |
| Homebrew tap | `~/Developer/homebrew-juicage` → `ryanbarnett-2am/homebrew-juicage` |
| Electron build | `~/Developer/tally-electron` — cross-platform, unreleased |

**Never put code in Dropbox.** It lived there once and Dropbox's sync corrupted
the Xcode project with conflicted copies. Stale copies still sit under
`~/Library/CloudStorage/Dropbox/` — ignore them; they are not the project.

## Three names, all deliberate

- **Folder, `.xcodeproj`, scheme: `ClaudeUsage`** — the original codename.
- **Bundle identifier: `twoam.Tally`** — frozen. macOS keys the saved claude.ai
  sign-in to it, so changing it signs every user out for no visible benefit.
- **The app: `Juicage`** — the only name a user sees.

Do not "tidy" any of these.

## Build and release

```sh
./package-release.sh          # build, sign, notarize, DMG, appcast
```

Follow `RELEASING.md`. The short version of what it protects against:

- **Test on a second Mac.** Both serious bugs were invisible on the build
  machine: seven releases shipped arm64-only, and two arrived "damaged" because
  a zip cannot reliably carry Sparkle's versioned framework.
- **Ship the DMG, not the zip.** The zip exists only for Sparkle's updater.
  Extract with `ditto -x -k`, never `unzip` — Info-ZIP drops macOS metadata and
  makes a valid signature look broken.
- **Three places must agree**: GitHub release, `appcast.xml` (push it or no
  installed copy hears about the release), and the tap's cask (version + DMG
  sha256 — this has been forgotten once).

To test without publishing: build Release, re-sign Sparkle's nested helpers,
install to `/Applications`. Never run `package-release.sh`, which rewrites the
appcast.

## Constraints worth not rediscovering

- **The usage API is undocumented.** No token counts anywhere — `percent` is the
  only unit, and it's model-weighted so it can't be converted to tokens. When it
  breaks, show "Couldn't load usage" rather than stale numbers looking live.
- **App Sandbox is off, deliberately.** Local-model monitoring needs to read
  Ollama's log and run the `lms` CLI, both sandbox-blocked. Explained in the
  README because it's a fair thing to ask about.
- **Sparkle's nested helpers must be re-signed.** Xcode signs the app and the
  framework but not executables inside a framework, so `Updater.app`,
  `Autoupdate` and two XPC services reach Apple carrying Sparkle's own
  signature and notarization rejects the archive. Innermost first.
- **`CURRENT_PROJECT_VERSION` follows `MARKETING_VERSION`.** Sparkle compares
  `CFBundleVersion`; pinned at `1` it would never find an update.
- **History cannot be backfilled.** `UsageHistory` records from launch,
  independent of anything drawing it. Window identity snaps to the minute —
  the API returns reset times a second apart between polls, and keying on the
  exact timestamp counted one window as several.

## git

`gh` holds two accounts and the **work one is active**, which cannot see this
personal repo — pushes fail with "Repository not found", which looks like an
auth problem and isn't. Per push:

```sh
gh auth switch --user ryanbarnett-2am
git -c credential.helper='!gh auth git-credential' push origin main
gh auth switch --user ryanbarnett-rrcg     # leave it as you found it
```

## Working style

Ryan is a hobbyist Swift developer — step-by-step, jargon-light. He tests on a
second Mac and finds real bugs there; take those reports seriously and diagnose
rather than guess. Show a rendered image before building a visual feature: two
were built twice for want of one.
