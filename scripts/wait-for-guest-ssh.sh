#!/bin/bash
set -euo pipefail

# Wait for guest SSH readiness and optionally verify command execution.

HOST="${HOST:-localhost}"
PORT="${PORT:-2222}"
USER_NAME="${USER_NAME:-root}"
PASSWORD="${PASSWORD:-root}"
TIMEOUT_SEC="${TIMEOUT_SEC:-900}"
INTERVAL_SEC="${INTERVAL_SEC:-5}"
VERIFY_CMD="${VERIFY_CMD:-echo ssh-ready}"
REQUIRE_AUTH="${REQUIRE_AUTH:-1}"

usage() {
    cat <<USAGE
Usage: HOST=localhost PORT=2222 USER_NAME=root PASSWORD=root [opts] $0

Options:
  --host HOST
  --port PORT
  --user USER
  --password PASS
  --timeout SEC
  --interval SEC
  --verify-cmd CMD
  --no-auth-check     only wait for TCP port to open
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --host) HOST="$2"; shift 2 ;;
        --port) PORT="$2"; shift 2 ;;
        --user) USER_NAME="$2"; shift 2 ;;
        --password) PASSWORD="$2"; shift 2 ;;
        --timeout) TIMEOUT_SEC="$2"; shift 2 ;;
        --interval) INTERVAL_SEC="$2"; shift 2 ;;
        --verify-cmd) VERIFY_CMD="$2"; shift 2 ;;
        --no-auth-check) REQUIRE_AUTH=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
    esac
done

if ! command -v nc >/dev/null 2>&1; then
    echo "[ERROR] nc is required" >&2
    exit 1
fi

if [ "$REQUIRE_AUTH" = "1" ] && ! command -v sshpass >/dev/null 2>&1; then
    echo "[ERROR] sshpass is required for auth checks" >&2
    exit 1
fi

start_ts="$(date +%s)"
echo "[INFO] Waiting for SSH at ${HOST}:${PORT} (timeout=${TIMEOUT_SEC}s)"

while true; do
    now_ts="$(date +%s)"
    elapsed="$((now_ts - start_ts))"
    if [ "$elapsed" -ge "$TIMEOUT_SEC" ]; then
        echo "[ERROR] Timeout waiting for SSH after ${elapsed}s" >&2
        exit 1
    fi

    if nc -z "$HOST" "$PORT" >/dev/null 2>&1; then
        if [ "$REQUIRE_AUTH" = "0" ]; then
            echo "[OK] TCP SSH port is open at ${HOST}:${PORT}"
            exit 0
        fi

        if sshpass -p "$PASSWORD" ssh \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=5 \
            -p "$PORT" "$USER_NAME@$HOST" "$VERIFY_CMD" >/dev/null 2>&1; then
            echo "[OK] SSH authentication and command check succeeded"
            exit 0
        fi
    fi

    printf '.'
    sleep "$INTERVAL_SEC"
done
