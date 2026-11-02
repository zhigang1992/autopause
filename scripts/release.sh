#!/usr/bin/env bash
# Build, sign (Developer ID), notarize and package Autopause for self-hosted
# distribution. Output: build/release/Autopause-<version>.zip
#
# Requires: a "Developer ID Application" identity in the keychain, and an
# App Store Connect API key stored with `asc auth login` (used by
# `asc notarization submit`). Override the identity with SIGN_IDENTITY.
set -euo pipefail

cd "$(dirname "$0")/.."

IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Zhigang Fang (7CRYNR44B3)}"
TEAM="${DEVELOPMENT_TEAM:-7CRYNR44B3}"
OUT="build/release"
APP="$OUT/Build/Products/Release/Autopause.app"

rm -rf "$OUT"
mkdir -p "$OUT"

# Hardened runtime + secure timestamp are required for notarization.
xcodebuild -scheme Autopause -configuration Release \
  -derivedDataPath "$OUT" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM" \
  ENABLE_HARDENED_RUNTIME=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  build

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
ZIP="$OUT/Autopause-$VERSION.zip"

# Sparkle's prebuilt helpers ship with their own signature (no Developer ID, no
# secure timestamp), which notarization rejects. Re-sign them inside-out, then
# the framework, then the app so its seal covers the new framework signature.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
SIGN=(codesign --force --options runtime --timestamp --sign "$IDENTITY")
"${SIGN[@]}" "$SPARKLE/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$SPARKLE/Autoupdate"
"${SIGN[@]}" "$SPARKLE/Updater.app"
"${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" --entitlements Autopause/Autopause.entitlements "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"
asc notarization submit --file "$ZIP" --wait

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

# Re-zip so the archive contains the stapled ticket.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# Sparkle: sign the archive with the EdDSA key in the login keychain (create it
# once with Sparkle's `generate_keys`) and rewrite appcast.xml for this version.
SIGN_UPDATE="$OUT/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
SIG_ATTRS=$("$SIGN_UPDATE" "$ZIP")   # sparkle:edSignature="..." length="..."
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
MIN_OS=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")
PUB_DATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
URL="https://github.com/zhigang1992/autopause/releases/download/v$VERSION/Autopause-$VERSION.zip"

cat > appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Autopause</title>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/zhigang1992/autopause/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure url="$URL" type="application/octet-stream" $SIG_ATTRS/>
    </item>
  </channel>
</rss>
EOF

echo "Ready: $ZIP"
echo "Updated appcast.xml for $VERSION. After uploading the zip to the v$VERSION GitHub release, commit and push appcast.xml."
