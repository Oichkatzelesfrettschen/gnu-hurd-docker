#!/bin/bash
# Smoke test: verifies noVNC is reachable and QEMU monitor reports "running".

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SERVICE_NAME="${SERVICE_NAME:-gnu-hurd-dev}"
MONITOR_PORT="${MONITOR_PORT:-9999}"
NOVNC_BIND="${NOVNC_BIND:-127.0.0.1}"
NOVNC_PORT="${NOVNC_PORT:-6080}"

novnc_host="$NOVNC_BIND"
if [ "$novnc_host" = "0.0.0.0" ]; then
    novnc_host="127.0.0.1"
fi

echo "[*] Smoke: noVNC at http://${novnc_host}:${NOVNC_PORT}/vnc.html"
curl -fsSI "http://${novnc_host}:${NOVNC_PORT}/vnc.html" >/dev/null
echo "[OK] noVNC reachable"

echo "[*] Smoke: QEMU monitor status on 127.0.0.1:${MONITOR_PORT}"
status="$(
    MONITOR_PORT="${MONITOR_PORT}" SERVICE_NAME="${SERVICE_NAME}" \
        ./scripts/qemu-monitor-command.sh 'info status' | tr -d '\r' || true
)"
echo "$status" | grep -q "VM status: running"
echo "[OK] monitor reports running"

echo "[*] Smoke: taking screenshot"
MONITOR_PORT="${MONITOR_PORT}" SERVICE_NAME="${SERVICE_NAME}" ./scripts/qemu-screenshot.sh >/dev/null
echo "[OK] screenshot captured"

