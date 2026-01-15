#!/bin/bash
set -euo pipefail

# Minimal guest bootstrap helper when SSH is broken.
#
# Uses qemu-login-run.sh to type commands on the guest VGA console via QEMU monitor.
# This is intentionally "best effort": it cannot prove commands executed; use
# ./scripts/qemu-run-to-share.sh or screenshots to verify.
#
# Examples:
#   MONITOR_PORT=9998 ./scripts/guest-bootstrap.sh --user root --pass root
#   MONITOR_PORT=9998 ./scripts/guest-bootstrap.sh --user root --pass root --only-mounts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

user="root"
pass=""
no_pass=0
delay_ms=200
only_mounts=0

usage() {
  cat <<'EOF'
Usage:
  MONITOR_PORT=9998 ./scripts/guest-bootstrap.sh --user USER --pass PASS [options]

Options:
  --user USER         login username (default: root)
  --pass PASS         login password (optional; default: press Enter)
  --no-pass           do not type a password (press Enter)
  --delay-ms N        inter-key delay in ms (default: 200)
  --only-mounts       only attempt tmpfs + 9p mounts (no service restarts)
  -h, --help          show help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --user) user="${2:?}"; shift 2 ;;
    --pass) pass="${2-}"; shift 2 ;;
    --no-pass) no_pass=1; shift ;;
    --delay-ms) delay_ms="${2:?}"; shift 2 ;;
    --only-mounts) only_mounts=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

cmds=(
  # /run: many services assume it exists and is writable.
  'mkdir -p /run /run/shm || true'
  'mount -t tmpfs tmpfs /run -o mode=0755 >/dev/null 2>&1 || true'
  'chmod 0755 /run >/dev/null 2>&1 || true'
  'mkdir -p /run/shm || true'
  'chmod 1777 /run/shm >/dev/null 2>&1 || true'

  # /tmp: avoid changing fstab here; just try to ensure it's usable.
  'chmod 1777 /tmp >/dev/null 2>&1 || true'

  # 9p host share (optional; depends on guest support).
  'mkdir -p /mnt/host || true'
  'mount -t 9p hostshare /mnt/host -o trans=virtio,version=9p2000.L,nofail >/dev/null 2>&1 || mount /mnt/host >/dev/null 2>&1 || true'
)

if [ "$only_mounts" != "1" ]; then
  cmds+=(
    # Restart cron/syslog if present (non-fatal).
    '/etc/init.d/sysklogd restart >/dev/null 2>&1 || true'
    '/etc/init.d/cron restart >/dev/null 2>&1 || true'
  )
fi

args=(--user "$user" --delay-ms "$delay_ms")
if [ "$no_pass" = "1" ] || [ -z "$pass" ]; then
  args+=(--no-pass)
else
  args+=(--pass "$pass")
fi
for c in "${cmds[@]}"; do
  args+=(--cmd "$c")
done

MONITOR_HOST="${MONITOR_HOST:-127.0.0.1}" MONITOR_PORT="${MONITOR_PORT:-9999}" \
  "${SCRIPT_DIR}/qemu-login-run.sh" "${args[@]}"

echo "[OK] bootstrap commands typed; verify via screenshots or /mnt/host output"
