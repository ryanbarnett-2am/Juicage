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
"$XCODEBUILD" -project ClaudeUsage.xcodeproj -scheme ClaudeUsage \
  -configuration Release -derivedDataPath "$BUILD" \
  -destination 'platform=macOS' build >/dev/null

echo "Packaging…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "✅ Done → $ZIP"
