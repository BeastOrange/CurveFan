#!/bin/bash
# install.sh — run from inside the mounted DMG: sudo bash /Volumes/CurveFan/install.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SRC="$SCRIPT_DIR/CurveFan.app"
HELPER_SRC="$SCRIPT_DIR/CurveFanHelper"
HELPER_DST="/Library/PrivilegedHelperTools/curvefan-helper"
PLIST_PATH="/Library/LaunchDaemons/com.curvefan.helper.plist"
APP_DST="/Applications/CurveFan.app"

[ "$(id -u)" != "0" ] && exec sudo "$0" "$@"

echo "[1/4] Clearing quarantine..."
xattr -cr "$APP_SRC" 2>/dev/null || true
xattr -cr "$HELPER_SRC" 2>/dev/null || true

echo "[2/4] Installing app..."
rm -rf "$APP_DST"
cp -R "$APP_SRC" "$APP_DST"
chown -R root:wheel "$APP_DST"
chmod -R u+rwX,go+rX "$APP_DST"

echo "[3/4] Installing helper daemon..."
mkdir -p /Library/PrivilegedHelperTools
cp "$HELPER_SRC" "$HELPER_DST"
chown root:wheel "$HELPER_DST"
chmod 755 "$HELPER_DST"

cat > "$PLIST_PATH" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>      <string>com.curvefan.helper</string>
    <key>ProgramArguments</key>
    <array><string>/Library/PrivilegedHelperTools/curvefan-helper</string></array>
    <key>RunAtLoad</key>  <true/>
    <key>KeepAlive</key>  <true/>
    <key>StandardErrorPath</key> <string>/var/log/curvefan-helper.log</string>
    <key>StandardOutPath</key>   <string>/var/log/curvefan-helper.log</string>
</dict>
</plist>
PLIST
chown root:wheel "$PLIST_PATH"
chmod 644 "$PLIST_PATH"

echo "[4/4] Loading daemon..."
launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load -w "$PLIST_PATH"
sleep 1

pgrep -f curvefan-helper >/dev/null && echo "✓ Helper is running" || { echo "✗ Helper failed — check /var/log/curvefan-helper.log"; exit 1; }
echo ""
echo "Installation complete. Open CurveFan from /Applications."
echo ""
echo "If macOS still blocks the app:"
echo "  sudo xattr -cr /Applications/CurveFan.app"
