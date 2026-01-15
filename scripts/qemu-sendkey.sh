#!/bin/bash
set -euo pipefail

# Send QEMU monitor "sendkey" sequences via telnet/expect.
#
# Examples:
#   MONITOR_PORT=9998 ./scripts/qemu-sendkey.sh esc
#   MONITOR_PORT=9998 ./scripts/qemu-sendkey.sh ret
#   MONITOR_PORT=9998 ./scripts/qemu-sendkey.sh ctrl-alt-f2
#
# For key names, see: QEMU monitor `help sendkey`

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

if [ "${1:-}" = "" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  echo "Usage: MONITOR_PORT=9998 ./scripts/qemu-sendkey.sh <key-seq>"
  exit 2
fi

key_seq="$1"
shift || true

MONITOR_HOST="${MONITOR_HOST:-127.0.0.1}"
MONITOR_PORT="${MONITOR_PORT:-9999}"

MONITOR_HOST="${MONITOR_HOST}" MONITOR_PORT="${MONITOR_PORT}" \
  "${SCRIPT_DIR}/qemu-monitor-command.sh" "sendkey ${key_seq}" >/dev/null

echo "[OK] sendkey ${key_seq} -> ${MONITOR_HOST}:${MONITOR_PORT}"

