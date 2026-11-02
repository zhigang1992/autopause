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

codesign --verify --deep --strict --verbose=2 "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"
asc notarization submit --file "$ZIP" --wait

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

# Re-zip so the archive contains the stapled ticket.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Ready: $ZIP"
