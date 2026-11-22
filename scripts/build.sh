#!/bin/bash
# Builds dist/ClaudeBarLimit.app (universal: arm64 + x86_64). Needs Xcode Command Line Tools (build-time only).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
BUNDLE_ID="dev.tfi.claudebarlimit"
APP="dist/ClaudeBarLimit.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for ARCH in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -parse-as-library -O \
    -target "$ARCH-apple-macos13.0" \
    App/*.swift -o "$TMP/ClaudeBarLimit-$ARCH"
done
lipo -create "$TMP"/ClaudeBarLimit-arm64 "$TMP"/ClaudeBarLimit-x86_64 -output "$APP/Contents/MacOS/ClaudeBarLimit"

# App icon: assets/AppIcon.png (1024x1024) -> AppIcon.icns
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for SZ in 16 32 128 256 512; do
  sips -z $SZ $SZ assets/AppIcon.png --out "$ICONSET/icon_${SZ}x${SZ}.png" >/dev/null
  sips -z $((SZ*2)) $((SZ*2)) assets/AppIcon.png --out "$ICONSET/icon_${SZ}x${SZ}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleExecutable</key><string>ClaudeBarLimit</string>
<key>CFBundleName</key><string>ClaudeBarLimit</string>
<key>CFBundleDisplayName</key><string>ClaudeBarLimit</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
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
lipo -info "$APP/Contents/MacOS/ClaudeBarLimit"
