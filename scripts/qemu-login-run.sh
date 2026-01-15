#!/bin/bash
set -euo pipefail

# Log in on the guest console (VNC) by typing via QEMU monitor sendkey,
# then run one or more shell commands.
#
# This is a pragmatic workaround when:
# - SSH isn't working (sshd crash / no banner)
# - serial console output is blank
# - you still have VGA via VNC/noVNC
#
# Assumptions:
# - Guest is at a getty login prompt on the VGA console.
# - You know the username/password.
#
# Usage:
#   MONITOR_PORT=9998 ./scripts/qemu-login-run.sh --user root --pass root \\
#     --cmd 'mount -t tmpfs tmpfs /run || true' \\
#     --cmd 'mount -t tmpfs tmpfs /tmp || true' \\
#     --cmd '/etc/init.d/ssh restart || true'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

user="root"
pass=""
no_pass=0
delay_ms=200
cmds=()

usage() {
  cat <<'EOF'
Usage:
  MONITOR_PORT=9998 ./scripts/qemu-login-run.sh [options] --cmd '...' [--cmd '...']...

Options:
  --user NAME         login username (default: root)
  --pass PASS         login password (optional; default: press Enter)
  --no-pass           do not type a password (press Enter)
  --delay-ms N        inter-key delay in ms (default: 200)
  --cmd COMMAND       command to run after login (repeatable)
  -h, --help          show help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --user) user="${2:?}"; shift 2 ;;
    --pass) pass="${2-}"; shift 2 ;;
    --no-pass) no_pass=1; shift ;;
    --delay-ms) delay_ms="${2:?}"; shift 2 ;;
    --cmd) cmds+=("${2:?}"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [ "${#cmds[@]}" -lt 1 ]; then
  echo "[ERROR] at least one --cmd is required" >&2
  exit 2
fi

export MONITOR_HOST="${MONITOR_HOST:-127.0.0.1}"
export MONITOR_PORT="${MONITOR_PORT:-9999}"

echo "[*] Typing login sequence to ${MONITOR_HOST}:${MONITOR_PORT}"

# Try to wake the console and clear any half-typed input.
# (On some images the keyboard queue is slow; avoid flooding it.)
MONITOR_HOST="$MONITOR_HOST" MONITOR_PORT="$MONITOR_PORT" \
  "${SCRIPT_DIR}/qemu-sendkey.sh" ret >/dev/null || true
MONITOR_HOST="$MONITOR_HOST" MONITOR_PORT="$MONITOR_PORT" \
  "${SCRIPT_DIR}/qemu-sendkey.sh" ret >/dev/null || true
MONITOR_HOST="$MONITOR_HOST" MONITOR_PORT="$MONITOR_PORT" \
  "${SCRIPT_DIR}/qemu-sendkey.sh" ctrl-u >/dev/null || true

MONITOR_HOST="$MONITOR_HOST" MONITOR_PORT="$MONITOR_PORT" \
  "${SCRIPT_DIR}/qemu-type.sh" --delay-ms "$delay_ms" --clear-line --enter "$user"

# Give getty a moment to prompt for password
sleep 2

if [ "$no_pass" = "1" ] || [ -z "$pass" ]; then
  MONITOR_HOST="$MONITOR_HOST" MONITOR_PORT="$MONITOR_PORT" \
    "${SCRIPT_DIR}/qemu-sendkey.sh" ret >/dev/null || true
else
  MONITOR_HOST="$MONITOR_HOST" MONITOR_PORT="$MONITOR_PORT" \
    "${SCRIPT_DIR}/qemu-type.sh" --delay-ms "$delay_ms" --clear-line --enter "$pass"
fi

sleep 2

for cmd in "${cmds[@]}"; do
  echo "[*] Running: $cmd"
  MONITOR_HOST="$MONITOR_HOST" MONITOR_PORT="$MONITOR_PORT" \
    "${SCRIPT_DIR}/qemu-type.sh" --delay-ms "$delay_ms" --enter "$cmd"
  sleep 1
done

echo "[OK] commands typed; check the VNC/noVNC console output for results"
