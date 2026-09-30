#!/usr/bin/env bash
# Builds dist/Feather.app from the SwiftPM executable.
#
# Accessibility and Screen Recording grants are tied to the code signature. Set
# CODESIGN_IDENTITY to a stable identity (e.g. "Apple Development: Name (TEAMID)"); with the
# ad-hoc default ("-") macOS forgets the grants after every rebuild.
set -euo pipefail

cd "$(dirname "$0")/.."

IDENTITY="${CODESIGN_IDENTITY:--}"
VERSION="${VERSION:-0.1.0}"
APP="dist/Feather.app"

# Swift 6.3's default cross-module optimization can crash while compiling this
# SwiftPM package. The release build remains optimized; this disables only that
# compiler optimization until the toolchain issue is resolved.
swift build -c release -Xswiftc -disable-cmo
BIN_DIR="$(swift build -c release -Xswiftc -disable-cmo --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Feather" "$APP/Contents/MacOS/Feather"
cp -R "$BIN_DIR/Feather_Feather.bundle" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.feather.app</string>
    <key>CFBundleName</key><string>Feather</string>
    <key>CFBundleDisplayName</key><string>Feather</string>
    <key>CFBundleExecutable</key><string>Feather</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>pt-BR</string></array>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP (signed with: $IDENTITY)"
