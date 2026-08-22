#!/bin/bash
# Builds a Release version of ClaudeUsage and packages it into a shareable zip
# on your Desktop. Run it from anywhere:  ./package-release.sh
#
# Signing picks itself automatically:
#   • A "Developer ID Application" certificate in your keychain  → signed with it,
#     then notarized + stapled if notarytool credentials exist. Recipients just
#     double-click; no Gatekeeper override at all.
#   • Otherwise                                                   → ad-hoc signed,
#     which works on any Mac but needs a one-time right-click → Open.
set -e
cd "$(dirname "$0")"

# Use the full Xcode toolchain (not the Command Line Tools, which can't build apps).
XCODEBUILD="/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"
[ -x "$XCODEBUILD" ] || XCODEBUILD="$(xcode-select -p)/usr/bin/xcodebuild"

BUILD="./.release-build"
APP="$BUILD/Build/Products/Release/Tally.app"
NOTARY_PROFILE="tally"   # created by: xcrun notarytool store-credentials "tally"
# ZIP name is set after the build, so it can carry the app's version number.

# Look for a Developer ID Application certificate. Note this is NOT the same as an
# "Apple Development" certificate — that one is tied to this account and its
# registered machines, so an app signed with it fails to launch on anyone else's
# Mac ("damaged / can't be opened") and right-click→Open often can't rescue it.
SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')"

if [ -n "$SIGN_ID" ]; then
  echo "Signing with: $SIGN_ID"
  SIGN_ARGS=(CODE_SIGN_IDENTITY="$SIGN_ID" CODE_SIGN_STYLE=Manual
             OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime")
else
  echo "No Developer ID found — signing ad-hoc."
  SIGN_ARGS=(CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="")
fi

echo "Building Release…"
rm -rf "$BUILD"
# CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO keeps the debug-only
# com.apple.security.get-task-allow entitlement out of the build. Notarization
# rejects any binary carrying it, and Xcode injects it by default.
"$XCODEBUILD" -project ClaudeUsage.xcodeproj -scheme ClaudeUsage \
  -configuration Release -derivedDataPath "$BUILD" \
  -destination 'platform=macOS' \
  "${SIGN_ARGS[@]}" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build >/dev/null

echo "Packaging…"
# Name the zip after the app's actual version, so a downloaded file identifies
# itself (Tally-1.4.zip) instead of every release being a generic "Tally.zip".
ABS_APP="$(cd "$(dirname "$APP")" && pwd)/Tally.app"
VERSION="$(defaults read "$ABS_APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo dev)"
ZIP="$HOME/Desktop/Tally-$VERSION.zip"

rm -f "$ZIP"
# Strip any quarantine flag before zipping so we don't ship it to recipients.
xattr -cr "$APP" 2>/dev/null || true
ditto -c -k --keepParent "$APP" "$ZIP"

# Notarize, but only when we signed with a real Developer ID *and* credentials
# are stored. Apple notarizes the zip, then the ticket is stapled onto the .app
# so it validates offline — which means re-zipping afterwards.
if [ -n "$SIGN_ID" ] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "Notarizing (a few minutes)…"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Notarized: $(xcrun stapler validate "$APP" 2>&1 | tail -1)"
elif [ -n "$SIGN_ID" ]; then
  echo "⚠️  Signed with Developer ID but NOT notarized —"
  echo "    run: xcrun notarytool store-credentials \"$NOTARY_PROFILE\""
fi

echo "Signature: $(codesign -dv "$APP" 2>&1 | grep -E '^Signature' || echo 'unknown')"
echo "Entitlements: $(codesign -d --entitlements - "$APP" 2>&1 | grep -c '\[Key\]') key(s)"
echo "✅ Done → $ZIP"
