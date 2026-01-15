#!/bin/bash
# Check whether the guest forwarded SSH port is reachable and presents an SSH banner.
#
# This distinguishes:
# - port open (TCP connect works)
# - sshd banner (protocol speaks)
# - auth works (out of scope for this check)

set -euo pipefail

HOST="${HOST:-127.0.0.1}"
SSH_PORT="${SSH_PORT:-2222}"
TIMEOUT_SECS="${TIMEOUT_SECS:-3}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "[ERROR] Missing command: $1" >&2; exit 127; }; }
require_cmd nc
require_cmd timeout

echo "[*] Checking TCP connect to ${HOST}:${SSH_PORT}"
if ! timeout "${TIMEOUT_SECS}" nc -z "${HOST}" "${SSH_PORT}" >/dev/null 2>&1; then
    echo "[FAIL] Cannot connect to ${HOST}:${SSH_PORT}" >&2
    exit 1
fi
echo "[OK] Port is open"

echo "[*] Checking SSH banner (first line)"
banner="$(
    timeout "${TIMEOUT_SECS}" bash -lc "echo | nc -w ${TIMEOUT_SECS} ${HOST} ${SSH_PORT} | tr -d '\\r' | head -n 1" || true
)"

if echo "$banner" | grep -qE '^SSH-'; then
    echo "[OK] Banner: $banner"
    exit 0
fi

echo "[FAIL] No SSH banner received (possible sshd crash or guest not listening)" >&2
if [ -n "$banner" ]; then
    echo "Got: $banner" >&2
fi
exit 2

