#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TABLINK_SIGN_IDENTITY:?Set TABLINK_SIGN_IDENTITY to your Developer ID Application identity}"
: "${TABLINK_NOTARY_PROFILE:?Set TABLINK_NOTARY_PROFILE to an existing notarytool keychain profile}"
APP="$PWD/build/TabLink.app"
codesign --force --options runtime --timestamp --sign "$TABLINK_SIGN_IDENTITY" "$APP/Contents/MacOS/TabLinkWatchdog"
codesign --force --options runtime --timestamp --sign "$TABLINK_SIGN_IDENTITY" "$APP/Contents/Resources/adb"
codesign --force --options runtime --timestamp --sign "$TABLINK_SIGN_IDENTITY" "$APP"
ditto -c -k --keepParent "$APP" build/TabLink-notarization.zip
xcrun notarytool submit build/TabLink-notarization.zip --keychain-profile "$TABLINK_NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
codesign --verify --deep --strict "$APP"
