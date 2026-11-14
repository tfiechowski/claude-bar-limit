#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="dist/ClaudeLimit.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.claudelimit.app</string>
<key>CFBundleExecutable</key><string>ClaudeLimit</string>
<key>CFBundleName</key><string>ClaudeLimit</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xcrun swiftc -parse-as-library -O -target "$(uname -m)-apple-macos13.0" ClaudeLimit.swift -o "$APP/Contents/MacOS/ClaudeLimit"
codesign --force --sign - "$APP"
cd dist && /usr/bin/zip -qr ClaudeLimit-macOS.zip ClaudeLimit.app
printf '\nCreated %s/dist/ClaudeLimit-macOS.zip\n' "$(cd .. && pwd)"
