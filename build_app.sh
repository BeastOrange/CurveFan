#!/bin/bash
set -euo pipefail

APP_NAME="CurveFan"
CONFIGURATION="${1:-release}"
PRODUCT_DIR=".build/${CONFIGURATION}"
APP_DIR="${PRODUCT_DIR}/${APP_NAME}.app"
EXECUTABLE="${PRODUCT_DIR}/${APP_NAME}"

swift build -c "$CONFIGURATION"

if [ ! -x "$EXECUTABLE" ]; then
    echo "error: cannot find executable at $EXECUTABLE" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "CurveFan/Info.plist" "$APP_DIR/Contents/Info.plist"
chmod 755 "$APP_DIR/Contents/MacOS/$APP_NAME"

echo "Built CurveFan.app at $APP_DIR"
