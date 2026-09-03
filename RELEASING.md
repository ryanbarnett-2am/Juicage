# Releasing Juicage

Three places have to agree: the **GitHub release**, the **Sparkle appcast**, and
the **Homebrew cask**. Miss one and the release still looks fine from here —
which is exactly how each of the mistakes below happened.

## Before you build

- [ ] `git status` clean, on `main`, everything pushed
- [ ] Bump `MARKETING_VERSION` in `ClaudeUsage.xcodeproj/project.pbxproj`
      (both configs). `CURRENT_PROJECT_VERSION` follows it automatically —
      Sparkle compares `CFBundleVersion`, and when it was pinned to `1` the
      updater ran happily and never found an update.

## Build

```sh
./package-release.sh
```

Signing picks itself: a Developer ID in the keychain gets used and notarized;
without one it falls back to ad-hoc. The script refuses to package a
single-architecture binary, and verifies the bundle after re-signing Sparkle's
nested helpers.

Produces on the Desktop:
- `Juicage-<version>.dmg` — what people download
- `Juicage-<version>.zip` — what Sparkle downloads
- an updated `appcast.xml` in the repo

## Verify — on a second Mac

**This is the step that matters.** Every serious bug so far was invisible on the
machine that built it:

- releases 1.0–1.6 were **Apple Silicon only**, because `-destination
  'platform=macOS'` builds just the host architecture
- 1.6/1.6.1 arrived **"damaged"** because a zip can't reliably reproduce
  Sparkle's versioned framework, and some unzip tools break the signature

Checks:
- [ ] Open the **DMG** on another Mac, drag to Applications, launch. No warnings.
- [ ] `lipo -info` shows `x86_64 arm64`
- [ ] `spctl -a -vv -t exec` says `accepted / source=Notarized Developer ID`
- [ ] Extract with `ditto -x -k`, never `unzip` — Info-ZIP drops macOS metadata
      and makes a valid signature look broken

## Publish

- [ ] `gh release create v<version> <dmg> <zip> --latest` with notes
- [ ] **Commit and push `appcast.xml`** — without it the release ships and no
      installed copy ever hears about it
- [ ] **Update the Homebrew cask** in `ryanbarnett-2am/homebrew-juicage`:
      `version` and the DMG's `sha256`. The hash changes every release; a stale
      cask silently installs the old build. This has been forgotten once.
- [ ] `brew style` and `brew audit --cask --online` before pushing the cask

## After

- [ ] `brew info --cask juicage` reports the new version
- [ ] `curl` the appcast and confirm the newest `<sparkle:version>`
- [ ] Close the milestone's issues

## Don't

- Ship several releases in a day. Eight in one day is churn for everyone else;
  batch instead.
- Publish a feature nobody has seen running. Build it locally, install it, look
  at it, *then* release — see below.

## Testing without publishing

Build Release, re-sign Sparkle's helpers, install to `/Applications`, and skip
`package-release.sh` entirely. Nothing touches the appcast, so no existing user
sees anything. Bump the version so the About menu tells you which build you're on.
