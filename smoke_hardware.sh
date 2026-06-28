#!/bin/bash
set -euo pipefail

SOCKET_PATH="${CURVEFAN_SOCKET_PATH:-/var/run/curvefan-helper.socket}"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
IPC_SEND=(swift "$ROOT_DIR/Scripts/ipc_send.swift")

if [ ! -S "$SOCKET_PATH" ]; then
    echo "error: helper socket not found at $SOCKET_PATH" >&2
    echo "run: sudo bash setup.sh" >&2
    exit 1
fi

request() {
    local json="$1"
    "${IPC_SEND[@]}" "$json"
}

assert_success() {
    local label="$1"
    local response="$2"
    python3 - "$label" "$response" <<'PY'
import json
import sys

label, raw = sys.argv[1], sys.argv[2]
try:
    payload = json.loads(raw)
except json.JSONDecodeError as exc:
    print(f"{label}: invalid JSON response: {exc}", file=sys.stderr)
    sys.exit(1)
if payload.get("success") is not True:
    print(f"{label}: helper returned failure: {raw}", file=sys.stderr)
    sys.exit(1)
PY
}

assert_fan_info() {
    local response="$1"
    python3 - "$response" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
info = payload.get("fanInfo") or {}
actual = float(info.get("actualRPM", -1))
minimum = float(info.get("minRPM", -1))
maximum = float(info.get("maxRPM", -1))
fan_count = int(info.get("fanCount", 0))
if fan_count < 1:
    raise SystemExit("getFanInfo: fanCount must be at least 1")
if not (0 <= minimum <= maximum <= 20000):
    raise SystemExit(f"getFanInfo: invalid RPM range {minimum}-{maximum}")
if not (0 <= actual <= 20000):
    raise SystemExit(f"getFanInfo: invalid actual RPM {actual}")
PY
}

run_required() {
    local label="$1"
    local json="$2"
    local response
    response="$(request "$json")"
    echo "$response"
    assert_success "$label" "$response"
}

run_required "ping" '{"ping":{}}'
run_required "FNum" '{"readKey":{"key":"FNum"}}'
run_required "F0Ac" '{"readKey":{"key":"F0Ac"}}'

temperature_ok=0
for key in Tc0P Tp01 Tp0D Tg0D Tg0P Tm0P; do
    response="$(request "{\"readKey\":{\"key\":\"$key\"}}")"
    echo "$response"
    if python3 - "$response" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
value = payload.get("value")
if payload.get("success") is True and isinstance(value, (int, float)) and -40 <= value <= 130:
    sys.exit(0)
sys.exit(1)
PY
    then
        temperature_ok=1
        break
    fi
done

if [ "$temperature_ok" -ne 1 ]; then
    echo "error: no readable temperature key returned a plausible value" >&2
    exit 1
fi

fan_info="$(request '{"getFanInfo":{"fan":0}}')"
echo "$fan_info"
assert_success "getFanInfo" "$fan_info"
assert_fan_info "$fan_info"

if [ "${CURVEFAN_SMOKE_RESTORE:-0}" = "1" ]; then
    run_required "restoreFanControl" '{"restoreFanControl":{"fan":0}}'
fi

echo "hardware smoke completed"
