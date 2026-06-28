#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOCKET_PATH="${TMPDIR:-/tmp}/curvefan-helper-test-$$.socket"
LOG_FILE="${TMPDIR:-/tmp}/curvefan-helper-test-$$.log"

cleanup() {
    if [ -n "${HELPER_PID:-}" ]; then
        kill "$HELPER_PID" 2>/dev/null || true
        wait "$HELPER_PID" 2>/dev/null || true
    fi
    rm -f "$SOCKET_PATH" "$LOG_FILE"
}
trap cleanup EXIT

swift build -c debug --product CurveFanHelper >/dev/null

CURVEFAN_SOCKET_PATH="$SOCKET_PATH" \
CURVEFAN_HELPER_FAKE_SMC=1 \
"$ROOT_DIR/.build/debug/CurveFanHelper" >"$LOG_FILE" 2>&1 &
HELPER_PID=$!

for _ in $(seq 1 50); do
    [ -S "$SOCKET_PATH" ] && break
    sleep 0.1
done

if [ ! -S "$SOCKET_PATH" ]; then
    echo "helper did not create test socket" >&2
    cat "$LOG_FILE" >&2 || true
    exit 1
fi

export CURVEFAN_SOCKET_PATH="$SOCKET_PATH"
swift "$ROOT_DIR/Scripts/ipc_send.swift" '{"ping":{}}' | grep '"success":true' >/dev/null
swift "$ROOT_DIR/Scripts/ipc_send.swift" '{"readKey":{"key":"FNum"}}' | grep '"value":1' >/dev/null
swift "$ROOT_DIR/Scripts/ipc_send.swift" '{"readKey":{"key":"F0Ac"}}' | grep '"value":2400' >/dev/null
swift "$ROOT_DIR/Scripts/ipc_send.swift" '{"readKeyData":{"key":"Tc0P"}}' | grep -F '"data":[42,0]' >/dev/null
swift "$ROOT_DIR/Scripts/ipc_send.swift" '{"getFanInfo":{"fan":0}}' | grep '"fanCount":1' >/dev/null

echo "local IPC smoke completed"
