#!/bin/bash
set -euo pipefail

# Run a command in the guest by typing it on the console, and capture output on the host
# via a temporary TCP listener.
#
# This is a fallback when:
# - SSH is broken (sshd crash)
# - 9p/virtfs is unavailable in the guest
#
# Networking assumption:
# - QEMU user-mode networking is used (default in this repo)
# - The host is reachable from the guest as 10.0.2.2
#
# Usage:
#   MONITOR_PORT=9998 ./scripts/qemu-run-to-host.sh --user root --pass root \
#     --name sshd-test --cmd '/usr/sbin/sshd -t -d -e'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

user="root"
pass=""
no_pass=0
delay_ms=200
name=""
cmd=""
listen_port="${LISTEN_PORT:-45678}"
timeout_secs="${TIMEOUT_SECS:-25}"

usage() {
  cat <<'EOF'
Usage:
  MONITOR_PORT=9998 ./scripts/qemu-run-to-host.sh [options] --name NAME --cmd 'COMMAND'

Options:
  --user NAME         login username (default: root)
  --pass PASS         login password (optional; default: press Enter)
  --no-pass           do not type a password (press Enter)
  --delay-ms N        inter-key delay in ms (default: 200)
  --name NAME         output base name under ./share (required)
  --cmd COMMAND       command to run (required)
  --listen-port PORT  host listen port (default: 45678, or LISTEN_PORT)
  --timeout-secs N    listener timeout (default: 25, or TIMEOUT_SECS)
  -h, --help          show help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --user) user="${2:?}"; shift 2 ;;
    --pass) pass="${2-}"; shift 2 ;;
    --no-pass) no_pass=1; shift ;;
    --delay-ms) delay_ms="${2:?}"; shift 2 ;;
    --name) name="${2:?}"; shift 2 ;;
    --cmd) cmd="${2:?}"; shift 2 ;;
    --listen-port) listen_port="${2:?}"; shift 2 ;;
    --timeout-secs) timeout_secs="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [ -z "$name" ] || [ -z "$cmd" ]; then
  usage >&2
  exit 2
fi

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "[ERROR] Missing command: $1" >&2; exit 127; }; }
require_cmd nc
require_cmd timeout

mkdir -p ./share
out_path="./share/${name}.out"
rm -f "$out_path"

echo "[*] Listening on 0.0.0.0:${listen_port} for up to ${timeout_secs}s -> ${out_path}"
(
  # netcat-openbsd: use `-l -p <port>`.
  # Use timeout to avoid hanging forever if the guest doesn't connect.
  timeout "${timeout_secs}" nc -l -p "${listen_port}" >"${out_path}" 2>/dev/null || true
) &
listener_pid="$!"

# Send the command output to host over TCP.
# Use a single pipeline so we don't require multiple connections.
guest_sender="sh -lc 'rc=0; { (${cmd}) 2>&1; rc=\\$?; echo rc:\${rc}; } | nc 10.0.2.2 ${listen_port} || true'"

pass_args=()
if [ "$no_pass" = "1" ] || [ -z "$pass" ]; then
  pass_args=(--no-pass)
else
  pass_args=(--pass "$pass")
fi

MONITOR_HOST="${MONITOR_HOST:-127.0.0.1}" MONITOR_PORT="${MONITOR_PORT:-9999}" \
  "${SCRIPT_DIR}/qemu-login-run.sh" --user "$user" "${pass_args[@]}" --delay-ms "$delay_ms" \
    --cmd "$guest_sender"

wait "$listener_pid" >/dev/null 2>&1 || true

if [ ! -s "$out_path" ]; then
  echo "[FAIL] No output captured. Possible causes: login failed, guest lacks nc, or guest networking down." >&2
  exit 3
fi

echo "[OK] captured guest output to ${out_path}"
