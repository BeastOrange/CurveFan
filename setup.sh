#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SOCKET_PATH="/var/run/curvefan-helper.socket"
HELPER_BIN="/Library/PrivilegedHelperTools/curvefan-helper"
PLIST_PATH="/Library/LaunchDaemons/com.curvefan.helper.plist"
APP_DEST="/Applications/CurveFan.app"

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_status() {
    echo "CurveFan Installation Status:"
    echo "=============================="
    if pgrep -f curvefan-helper > /dev/null 2>&1; then
        echo -e "  Helper daemon: ${GREEN}RUNNING${NC}"
    else
        echo -e "  Helper daemon: ${RED}NOT RUNNING${NC}"
    fi
    if [ -f "$HELPER_BIN" ]; then
        echo -e "  Helper binary: ${GREEN}$HELPER_BIN${NC}"
    else
        echo -e "  Helper binary: ${RED}NOT INSTALLED${NC}"
    fi
    if [ -f "$PLIST_PATH" ]; then
        echo -e "  LaunchDaemon:  ${GREEN}$PLIST_PATH${NC}"
    else
        echo -e "  LaunchDaemon:  ${RED}NOT INSTALLED${NC}"
    fi
    if [ -d "$APP_DEST" ]; then
        echo -e "  App bundle:    ${GREEN}$APP_DEST${NC}"
    else
        echo -e "  App bundle:    ${RED}NOT INSTALLED${NC}"
    fi
    if [ -S "$SOCKET_PATH" ]; then
        echo -e "  Socket:        ${GREEN}$SOCKET_PATH${NC}"
        ls -l "$SOCKET_PATH"
    else
        echo -e "  Socket:        ${YELLOW}NOT ACTIVE${NC}"
    fi
}

do_install() {
    if [ "$(id -u)" = "0" ] && [ -n "${SUDO_USER:-}" ]; then
        log_info "Building as $SUDO_USER to avoid root-owned .build artifacts..."
        sudo -u "$SUDO_USER" swift build -c release || { log_error "Build failed"; exit 1; }
        sudo -u "$SUDO_USER" bash build_app.sh release || { log_error "App bundle build failed"; exit 1; }
    else
        log_info "Building CurveFan..."
        swift build -c release || { log_error "Build failed"; exit 1; }
        bash build_app.sh release || { log_error "App bundle build failed"; exit 1; }
    fi

    log_info "Installing helper daemon..."
    sudo mkdir -p /Library/PrivilegedHelperTools

    if [ -f .build/release/CurveFanHelper ]; then
        HELPER_SRC=".build/release/CurveFanHelper"
    elif [ -f .build/apple/Products/Release/CurveFanHelper ]; then
        HELPER_SRC=".build/apple/Products/Release/CurveFanHelper"
    else
        log_error "Cannot find CurveFanHelper binary"
        exit 1
    fi

    sudo cp "$HELPER_SRC" "$HELPER_BIN"
    sudo chown root:wheel "$HELPER_BIN"
    sudo chmod 755 "$HELPER_BIN"
    log_info "Helper binary installed"

    log_info "Installing app bundle..."
    sudo rm -rf "$APP_DEST"
    sudo cp -R ".build/release/CurveFan.app" "$APP_DEST"
    sudo chown -R root:wheel "$APP_DEST"
    sudo chmod -R u+rwX,go+rX "$APP_DEST"
    log_info "App installed at $APP_DEST"

    log_info "Setting up LaunchDaemon..."
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    if [ -f "$SCRIPT_DIR/com.curvefan.helper.plist" ]; then
        sudo cp "$SCRIPT_DIR/com.curvefan.helper.plist" "$PLIST_PATH"
    else
        sudo tee "$PLIST_PATH" > /dev/null << 'PLISTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.curvefan.helper</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Library/PrivilegedHelperTools/curvefan-helper</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/var/log/curvefan-helper.log</string>
    <key>StandardOutPath</key>
    <string>/var/log/curvefan-helper.log</string>
</dict>
</plist>
PLISTEOF
    fi
    sudo chown root:wheel "$PLIST_PATH"
    sudo chmod 644 "$PLIST_PATH"

    log_info "Loading daemon..."
    sudo launchctl unload "$PLIST_PATH" 2>/dev/null || true
    sudo launchctl load -w "$PLIST_PATH"
    sleep 1

    if pgrep -f curvefan-helper > /dev/null 2>&1; then
        log_info "CurveFan helper daemon is running"
    else
        log_error "Daemon failed to start. Check logs: /var/log/curvefan-helper.log"
        exit 1
    fi

    log_info ""
    log_info "Installation complete!"
    log_info "You can now use the CurveFan app."
    log_info ""
    log_warn "If the app does not open, run: sudo xattr -cr $APP_DEST"
}

case "${1:-}" in
    --check)
        check_status
        exit 0
        ;;
    --uninstall)
        echo "Use uninstall.sh instead"
        exit 0
        ;;
    *)
        if [ "$(id -u)" != "0" ]; then
            log_warn "This script needs sudo for daemon installation."
            log_info "Running with sudo..."
        fi
        do_install
        ;;
esac
