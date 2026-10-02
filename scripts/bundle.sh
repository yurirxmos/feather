#!/usr/bin/env bash
# Builds dist/Feather.app from the SwiftPM executable.
#
# Accessibility and Screen Recording grants are tied to the code signature. Set
# CODESIGN_IDENTITY to a stable identity (e.g. "Apple Development: Name (TEAMID)"); with the
# ad-hoc default ("-") macOS forgets the grants after every rebuild.
#
# Release builds also set SPARKLE_FEED_URL and SPARKLE_PUBLIC_ED_KEY to turn on automatic updates;
# without them the updater stays off.
set -euo pipefail

cd "$(dirname "$0")/.."

IDENTITY="${CODESIGN_IDENTITY:--}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP="dist/Feather.app"

# Swift 6.3's default cross-module optimization can crash while compiling this
# SwiftPM package. The release build remains optimized; this disables only that
# compiler optimization until the toolchain issue is resolved.
swift build -c release -Xswiftc -disable-cmo
BIN_DIR="$(swift build -c release -Xswiftc -disable-cmo --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Feather" "$APP/Contents/MacOS/Feather"
cp -R "$BIN_DIR/Feather_Feather.bundle" "$APP/Contents/Resources/"
# Regenerate with `swift scripts/make-icon.swift`.
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
# SwiftPM only adds @loader_path, which points at Contents/MacOS inside the bundle.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Feather"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.feather.app</string>
    <key>CFBundleName</key><string>Feather</string>
    <key>CFBundleDisplayName</key><string>Feather</string>
    <key>CFBundleExecutable</key><string>Feather</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>pt-BR</string></array>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

if [[ -n "${SPARKLE_FEED_URL:-}" && -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
    PLIST="$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool true" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :SUScheduledCheckInterval integer 3600" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :SUVerifyUpdateBeforeExtraction bool true" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :SURequireSignedFeed bool true" "$PLIST"
fi

# Sign inside out, as Sparkle's documentation describes, instead of relying on --deep. No hardened
# runtime: its library validation rejects Sparkle when the identity has no Team ID (ad-hoc or
# self-signed). Notarization will need it back together with a Developer ID.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
codesign --force --sign "$IDENTITY" "$SPARKLE/XPCServices/Installer.xpc"
codesign --force --preserve-metadata=entitlements --sign "$IDENTITY" "$SPARKLE/XPCServices/Downloader.xpc"
codesign --force --sign "$IDENTITY" "$SPARKLE/Autoupdate"
codesign --force --sign "$IDENTITY" "$SPARKLE/Updater.app"
codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP (signed with: $IDENTITY)"
