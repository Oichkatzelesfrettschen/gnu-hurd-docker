#!/bin/bash
set -euo pipefail

# Type one or more shell commands into the guest via the QEMU monitor sendkey
# channel, assuming you already have a working shell prompt on the VGA console.
#
# Why:
# - Some Debian GNU/Hurd images have flaky getty/login and sshd crashes.
# - Once you reach a `root@...#` prompt, logging in again just floods the
#   keyboard queue ("rkbd: queue full").
#
# Usage:
#   MONITOR_PORT=9998 ./scripts/qemu-shell-run.sh --cmd 'id' --cmd 'uname -a'
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

delay_ms=400
sleep_s=2
cmds=()

usage() {
  cat <<'EOF'
Usage:
  MONITOR_PORT=9998 ./scripts/qemu-shell-run.sh [options] --cmd '...' [--cmd '...']...

Options:
  --delay-ms N        inter-key delay in ms (default: 400)
  --sleep-s N         sleep between commands in seconds (default: 2)
  --cmd COMMAND       command to run (repeatable)
  -h, --help          show help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --delay-ms) delay_ms="${2:?}"; shift 2 ;;
    --sleep-s) sleep_s="${2:?}"; shift 2 ;;
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

echo "[*] Typing shell commands to ${MONITOR_HOST}:${MONITOR_PORT} (delay=${delay_ms}ms)"

# Best-effort attempt to avoid partially typed junk.
MONITOR_HOST="$MONITOR_HOST" MONITOR_PORT="$MONITOR_PORT" \
  "${SCRIPT_DIR}/qemu-sendkey.sh" ctrl-u >/dev/null || true

for cmd in "${cmds[@]}"; do
  echo "[*] CMD: $cmd"
  MONITOR_HOST="$MONITOR_HOST" MONITOR_PORT="$MONITOR_PORT" \
    "${SCRIPT_DIR}/qemu-type.sh" --delay-ms "$delay_ms" --clear-line --enter "$cmd"
  sleep "$sleep_s"
done

echo "[OK] commands typed; use noVNC/VNC/screenshot to verify output"

