# Releasing Juicage

Three places have to agree: the **GitHub release**, the **Sparkle appcast**, and
the **Homebrew cask**. If one is missed the release still looks correct from the
build machine, so work through the list rather than from memory.

## Before you build

- [ ] `git status` clean, on `main`, everything pushed
- [ ] Bump `MARKETING_VERSION` in `ClaudeUsage.xcodeproj/project.pbxproj`
      (both configurations). `CURRENT_PROJECT_VERSION` follows it automatically;
      Sparkle compares `CFBundleVersion`, so a fixed value would stop the
      updater ever seeing a new release.

## Build

```sh
./package-release.sh
```

Signing selects itself: a Developer ID in the keychain is used and notarized,
and without one the build falls back to ad-hoc. The script refuses to package a
single-architecture binary, re-signs Sparkle's nested helpers innermost-first,
and verifies the bundle afterwards. Build output is kept in
`.release-build/build.log`.

Produces on the Desktop:
- `Juicage-<version>.dmg` — what people download
- `Juicage-<version>.zip` — what Sparkle downloads
- an updated `appcast.xml` in the repo

## Verify — on a second Mac

**This is the step that matters.** Architecture, signing and notarization
problems are invisible on the machine that produced the build, because it
already trusts its own output.

- [ ] Transfer by AirDrop or a download so the file carries a quarantine flag —
      a direct copy bypasses Gatekeeper and proves nothing
- [ ] `xattr -p com.apple.quarantine <dmg>` returns a value
- [ ] Open the **DMG**, drag to Applications, launch. No prompt of any kind.
- [ ] `lipo -info` shows `x86_64 arm64`
- [ ] `spctl -a -vv -t exec` reports `accepted / source=Notarized Developer ID`
- [ ] `xcrun stapler validate` passes
- [ ] Confirm existing history survives the upgrade
- [ ] Extract archives with `ditto -x -k`, never `unzip` — Info-ZIP drops macOS
      metadata and a valid signature will appear broken

## Publish

- [ ] `gh release create v<version> <dmg> <zip> --latest` with notes from
      `docs/release-notes/<version>.md`
- [ ] **Commit and push `appcast.xml`** — the release is invisible to installed
      copies until this lands
- [ ] Confirm the URL in the appcast returns HTTP 200 before announcing
- [ ] **Update the Homebrew cask** in `ryanbarnett-2am/homebrew-juicage`:
      `version` and the DMG's `sha256`. Take the hash from the published asset,
      not the local file
- [ ] `brew style` and `brew audit --cask --online` before pushing the cask

## After

- [ ] `brew info --cask juicage` reports the new version
- [ ] `curl` the appcast and confirm the newest `<sparkle:version>`
- [ ] Close the milestone's issues

## Testing without publishing

Build Release, re-sign Sparkle's helpers, install to `/Applications`, and skip
`package-release.sh` entirely. Nothing touches the appcast, so no installed copy
sees anything. Bump the version so the About menu identifies the build.

Batch changes into fewer, larger releases rather than shipping several in a day,
and install a feature locally and use it before releasing it.
