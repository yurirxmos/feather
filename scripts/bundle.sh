#!/usr/bin/env bash
# Builds dist/ContextBar.app from the SwiftPM executable.
#
# Accessibility and Screen Recording grants are tied to the code signature. Set
# CODESIGN_IDENTITY to a stable identity (e.g. "Apple Development: Name (TEAMID)"); with the
# ad-hoc default ("-") macOS forgets the grants after every rebuild.
set -euo pipefail

cd "$(dirname "$0")/.."

IDENTITY="${CODESIGN_IDENTITY:--}"
VERSION="${VERSION:-0.1.0}"
APP="dist/ContextBar.app"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ContextBar" "$APP/Contents/MacOS/ContextBar"
cp -R "$BIN_DIR/ContextBar_ContextBar.bundle" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.contextbar.app</string>
    <key>CFBundleName</key><string>Context Bar</string>
    <key>CFBundleDisplayName</key><string>Context Bar</string>
    <key>CFBundleExecutable</key><string>ContextBar</string>
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
