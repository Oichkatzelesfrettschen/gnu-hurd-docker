#!/bin/bash
set -euo pipefail

# Run a command in the guest by typing it on the console, and capture output to /share.
#
# This is intended for bootstrap debugging when SSH is broken (eg: sshd crashes on some Hurd images).
#
# Flow:
# - Default: log in (best-effort) using qemu-login-run.sh, then run the command.
# - If --assume-shell is set: skip login and just type into the existing shell prompt.
#
# Usage:
#   MONITOR_PORT=9998 ./scripts/qemu-run-to-share.sh --user root --pass root \
#     --name sshd-test --cmd '/usr/sbin/sshd -t -d -e'
#
# Notes:
# - The command is wrapped in `sh -lc` so you can use shell features.
# - This writes to `/mnt/host` inside the guest (9p mount). The host sees it under `./share/`.
# - If the guest can't mount `/mnt/host` or you aren't logged in, the output won't appear.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

user="root"
pass=""
no_pass=0
delay_ms=200
name=""
cmd=""
guest_out_dir="/mnt/host"
assume_shell=0

usage() {
  cat <<'EOF'
Usage:
  MONITOR_PORT=9998 ./scripts/qemu-run-to-share.sh [options] --name NAME --cmd 'COMMAND'

Options:
  --user NAME         login username (default: root)
  --pass PASS         login password (optional; default: press Enter)
  --no-pass           do not type a password (press Enter)
  --assume-shell      do not attempt login; assume a shell prompt is active
  --delay-ms N        inter-key delay in ms (default: 200)
  --guest-out-dir DIR guest output directory (default: /mnt/host)
  --name NAME         output base name under ./share (required)
  --cmd COMMAND       command to run (required)
  -h, --help          show help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --user) user="${2:?}"; shift 2 ;;
    --pass) pass="${2-}"; shift 2 ;;
    --no-pass) no_pass=1; shift ;;
    --assume-shell) assume_shell=1; shift ;;
    --delay-ms) delay_ms="${2:?}"; shift 2 ;;
    --guest-out-dir) guest_out_dir="${2:?}"; shift 2 ;;
    --name) name="${2:?}"; shift 2 ;;
    --cmd) cmd="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [ -z "$name" ] || [ -z "$cmd" ]; then
  usage >&2
  exit 2
fi

out="${guest_out_dir}/${name}.out"

# Ensure host-side directory exists.
mkdir -p ./share

wrapped="sh -lc '(${cmd}) > ${out} 2>&1; echo rc:$? >> ${out}'"

pass_args=()
if [ "$no_pass" = "1" ] || [ -z "$pass" ]; then
  pass_args=(--no-pass)
else
  pass_args=(--pass "$pass")
fi

if [ "$assume_shell" = "1" ]; then
  MONITOR_HOST="${MONITOR_HOST:-127.0.0.1}" MONITOR_PORT="${MONITOR_PORT:-9999}" \
    "${SCRIPT_DIR}/qemu-shell-run.sh" --delay-ms "$delay_ms" --sleep-s 2 \
      --cmd 'mkdir -p /mnt/host || true' \
      --cmd 'mount -t 9p hostshare /mnt/host -o trans=virtio,version=9p2000.L,nofail >/dev/null 2>&1 || mount /mnt/host >/dev/null 2>&1 || true' \
      --cmd "echo begin:${name} > ${out}" \
      --cmd "date >> ${out}" \
      --cmd "$wrapped"
else
  MONITOR_HOST="${MONITOR_HOST:-127.0.0.1}" MONITOR_PORT="${MONITOR_PORT:-9999}" \
    "${SCRIPT_DIR}/qemu-login-run.sh" --user "$user" "${pass_args[@]}" --delay-ms "$delay_ms" \
      --cmd 'mkdir -p /mnt/host || true' \
      --cmd 'mount -t 9p hostshare /mnt/host -o trans=virtio,version=9p2000.L,nofail >/dev/null 2>&1 || mount /mnt/host >/dev/null 2>&1 || true' \
      --cmd "echo begin:${name} > ${out}" \
      --cmd "date >> ${out}" \
      --cmd "$wrapped"
fi

echo "[OK] wrote guest output to ${out} (host path: ./share/${name}.out)"
