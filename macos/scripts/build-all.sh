#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/test-core.sh
swift build --build-system native -c release
APP="$PWD/build/TabLink.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TabLink .build/release/TabLinkWatchdog "$APP/Contents/MacOS/"
cp -R Resources/. "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TabLink</string>
<key>CFBundleIdentifier</key><string>com.tablink.mac</string>
<key>CFBundleName</key><string>TabLink</string>
<key>CFBundleDisplayName</key><string>TabLink</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.4</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHumanReadableCopyright</key><string>TabLink contributors. Includes scrcpy, Apache-2.0.</string>
<key>NSLocalNetworkUsageDescription</key><string>Find and connect to your Android tablet over local Wi-Fi.</string>
<key>NSBonjourServices</key><array><string>_adb-tls-connect._tcp</string><string>_adb-tls-pairing._tcp</string></array>
<key>CFBundleIconFile</key><string>TabLink</string>
</dict></plist>
PLIST
chmod +x "$APP/Contents/Resources/adb"
codesign --force --sign - "$APP/Contents/MacOS/TabLinkWatchdog"
codesign --force --sign - "$APP/Contents/MacOS/TabLink"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
