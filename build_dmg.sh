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
hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG_NAME"

echo ""
echo "Done → $DMG_NAME"
echo ""
echo "User install flow:"
echo "  1. Open $DMG_NAME"
echo "  2. Drag CurveFan.app → Applications"
echo "  3. Double-click CurveFan.app → password dialog → done"
