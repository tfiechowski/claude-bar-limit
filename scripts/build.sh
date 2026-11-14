#!/bin/bash
# Builds dist/ClaudeLimit.app (universal: arm64 + x86_64). Needs Xcode Command Line Tools (build-time only).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
BUNDLE_ID="dev.tfi.claudelimit"
APP="dist/ClaudeLimit.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for ARCH in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -parse-as-library -O \
    -target "$ARCH-apple-macos13.0" \
    App/*.swift -o "$TMP/ClaudeLimit-$ARCH"
done
lipo -create "$TMP"/ClaudeLimit-arm64 "$TMP"/ClaudeLimit-x86_64 -output "$APP/Contents/MacOS/ClaudeLimit"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleExecutable</key><string>ClaudeLimit</string>
<key>CFBundleName</key><string>ClaudeLimit</string>
<key>CFBundleDisplayName</key><string>ClaudeLimit</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>MIT License. Unofficial; not affiliated with Anthropic.</string>
</dict></plist>
PLIST

# Ad-hoc signature only. This is NOT Developer ID signing and the app is NOT notarized.
codesign --force --sign - "$APP"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
echo "Built $APP (v$VERSION)"
lipo -info "$APP/Contents/MacOS/ClaudeLimit"
