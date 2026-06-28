#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

HELPER_BIN="/Library/PrivilegedHelperTools/curvefan-helper"
PLIST_PATH="/Library/LaunchDaemons/com.curvefan.helper.plist"
DATA_HOME="${SUDO_USER:-$USER}"
DATA_DIR="$(eval echo "~$DATA_HOME")/Library/Application Support/CurveFan"
KEEP_DATA=0

for arg in "$@"; do
    case "$arg" in
        --keep-data)
            KEEP_DATA=1
            ;;
        *)
            log_error "Unknown option: $arg"
            echo "Usage: bash uninstall.sh [--keep-data]"
            exit 1
            ;;
    esac
done

if [ "$(id -u)" != "0" ]; then
    log_info "Running with sudo..."
    exec sudo "$0" "$@"
fi

log_info "Stopping CurveFan daemon..."
sudo launchctl unload "$PLIST_PATH" 2>/dev/null || true

log_info "Removing files..."
rm -f "$HELPER_BIN"
rm -f "$PLIST_PATH"
rm -rf /Applications/CurveFan.app

if [ "$KEEP_DATA" = "1" ]; then
    log_info "Keeping user data."
else
    log_info "Removing user data. Use --keep-data to preserve presets."
    rm -rf "$DATA_DIR"
fi

log_info "Uninstall complete."
