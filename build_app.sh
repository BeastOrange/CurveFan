#!/bin/bash
set -euo pipefail

APP_NAME="CurveFan"
CONFIGURATION="${1:-release}"
PRODUCT_DIR=".build/${CONFIGURATION}"
APP_DIR="${PRODUCT_DIR}/${APP_NAME}.app"
EXECUTABLE="${PRODUCT_DIR}/${APP_NAME}"
ICON_SOURCE="CurveFan/Assets/AppIcon.png"
ICONSET_DIR="${PRODUCT_DIR}/AppIcon.iconset"
ICON_FILE="${PRODUCT_DIR}/AppIcon.icns"

swift build -c "$CONFIGURATION"

if [ ! -x "$EXECUTABLE" ]; then
    echo "error: cannot find executable at $EXECUTABLE" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "CurveFan/Info.plist" "$APP_DIR/Contents/Info.plist"
chmod 755 "$APP_DIR/Contents/MacOS/$APP_NAME"

# Embed the privileged helper so the app can self-install on first launch.
HELPER_BIN=".build/${CONFIGURATION}/CurveFanHelper"
if [ ! -x "$HELPER_BIN" ]; then
    echo "error: cannot find helper executable at $HELPER_BIN" >&2
    exit 1
fi
cp "$HELPER_BIN" "$APP_DIR/Contents/Resources/CurveFanHelper"
chmod 755 "$APP_DIR/Contents/Resources/CurveFanHelper"

for script in setup.sh uninstall.sh; do
    if [ ! -f "$script" ]; then
        echo "error: cannot find required resource script $script" >&2
        exit 1
    fi
    cp "$script" "$APP_DIR/Contents/Resources/$script"
    chmod 755 "$APP_DIR/Contents/Resources/$script"
done

if [ -f "$ICON_SOURCE" ]; then
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"
    sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
    sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
    sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
    sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
    sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
    cp "$ICON_FILE" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

echo "Built CurveFan.app at $APP_DIR"
