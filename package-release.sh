#!/bin/bash
# Builds a Release version of ClaudeUsage and packages it into a shareable zip
# on your Desktop. Run it from anywhere:  ./package-release.sh
set -e
cd "$(dirname "$0")"

# Use the full Xcode toolchain (not the Command Line Tools, which can't build apps).
XCODEBUILD="/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"
[ -x "$XCODEBUILD" ] || XCODEBUILD="$(xcode-select -p)/usr/bin/xcodebuild"

BUILD="./.release-build"
APP="$BUILD/Build/Products/Release/Tally.app"
ZIP="$HOME/Desktop/Tally.zip"

echo "Building Release…"
rm -rf "$BUILD"
# Sign AD-HOC (CODE_SIGN_IDENTITY="-"), not with the Apple Development cert.
# A development certificate is tied to this developer account and its registered
# machines, so an app signed with it fails to launch on anyone else's Mac
# ("damaged / can't be opened") and the right-click→Open override often can't
# rescue it. Ad-hoc is treated as "unsigned but intact": Gatekeeper asks for a
# one-time override, which works on any Mac. (Proper fix would be a Developer ID
# certificate + notarization, which needs a paid Apple Developer account.)
"$XCODEBUILD" -project ClaudeUsage.xcodeproj -scheme ClaudeUsage \
  -configuration Release -derivedDataPath "$BUILD" \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  build >/dev/null

echo "Packaging…"
rm -f "$ZIP"
# Strip any quarantine flag before zipping so we don't ship it to recipients.
xattr -cr "$APP" 2>/dev/null || true
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Signature: $(codesign -dv "$APP" 2>&1 | grep -E '^Signature' || echo 'unknown')"
echo "✅ Done → $ZIP"
