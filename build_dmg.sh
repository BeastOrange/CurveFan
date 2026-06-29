#!/bin/bash
# build_dmg.sh — builds a distribution DMG with drag-to-Applications layout
# Usage: bash build_dmg.sh [version]
set -euo pipefail

VERSION="${1:-1.0.0}"
DMG_NAME="CurveFan-${VERSION}.dmg"
TMP_DMG="$(mktemp /tmp/curvefan_tmp_XXXX.dmg)"
STAGING="$(mktemp -d)"
VOL_NAME="CurveFan"

cleanup() { rm -rf "$STAGING" "$TMP_DMG" 2>/dev/null || true; }
trap cleanup EXIT

echo "Building release..."
swift build -c release
bash build_app.sh release

echo "Staging..."
cp -R .build/release/CurveFan.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "Creating DMG..."
hdiutil create -megabytes 120 -volname "$VOL_NAME" -fs HFS+ -ov -o "$TMP_DMG"
hdiutil attach "$TMP_DMG" -mountpoint "/Volumes/$VOL_NAME" -noautoopen -quiet
cp -R "$STAGING/CurveFan.app"  "/Volumes/$VOL_NAME/"
ln -s /Applications             "/Volumes/$VOL_NAME/Applications"

# Window layout via Finder AppleScript
osascript << APPLESCRIPT
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {400, 100, 880, 380}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set position of item "CurveFan.app"  of container window to {120, 140}
        set position of item "Applications"  of container window to {360, 140}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

hdiutil detach "/Volumes/$VOL_NAME" -quiet
hdiutil convert "$TMP_DMG" -format UDZO -o "$DMG_NAME" -quiet

echo ""
echo "Done → $DMG_NAME"
echo ""
echo "User install flow:"
echo "  1. Open $DMG_NAME"
echo "  2. Drag CurveFan.app → Applications"
echo "  3. Double-click CurveFan.app → password dialog → done"
