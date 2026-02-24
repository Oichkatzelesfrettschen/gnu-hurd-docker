#!/bin/bash
set -euo pipefail

# Provision Debian GNU/Hurd guest from SSH-ready to dev/X11 baseline.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

HOST="${HOST:-localhost}"
PORT="${PORT:-2222}"
ROOT_PASS="${ROOT_PASS:-root}"
AGENTS_PASS="${AGENTS_PASS:-agents}"
PROFILE="${PROFILE:-x11}"
TIMEOUT_SEC="${TIMEOUT_SEC:-900}"

usage() {
    cat <<USAGE
Usage: HOST=localhost PORT=2222 ROOT_PASS=root [PROFILE=dev|x11] $0
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --host) HOST="$2"; shift 2 ;;
        --port) PORT="$2"; shift 2 ;;
        --root-pass) ROOT_PASS="$2"; shift 2 ;;
        --agents-pass) AGENTS_PASS="$2"; shift 2 ;;
        --profile) PROFILE="$2"; shift 2 ;;
        --timeout) TIMEOUT_SEC="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
    esac
done

if ! command -v sshpass >/dev/null 2>&1; then
    echo "[ERROR] sshpass is required" >&2
    exit 1
fi

# Wait for SSH auth first.
HOST="$HOST" PORT="$PORT" USER_NAME=root PASSWORD="$ROOT_PASS" TIMEOUT_SEC="$TIMEOUT_SEC" \
    "${SCRIPT_DIR}/wait-for-guest-ssh.sh"

# Normalize Debian-Ports sources and base network/ssh pieces.
ROOT_PASS="$ROOT_PASS" "${SCRIPT_DIR}/fix-sources-hurd.sh" -h "$HOST" -p "$PORT"

ssh_root=(sshpass -p "$ROOT_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$PORT" "root@$HOST")

echo "[STEP] Creating baseline users/sudo policy..."
"${ssh_root[@]}" bash -s <<EOSSH
set -e
id agents >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo agents
printf 'agents:%s\n' '${AGENTS_PASS}' | chpasswd
mkdir -p /etc/sudoers.d
printf 'agents ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/agents
chmod 0440 /etc/sudoers.d/agents
EOSSH

# Install profile-specific package set.
case "$PROFILE" in
    dev)
        pkg_list="gcc make git vim openssh-client curl wget"
        ;;
    x11)
        pkg_list="gcc make git vim openssh-client curl wget xorg xfce4 lightdm"
        ;;
    *)
        echo "[ERROR] Unsupported PROFILE='$PROFILE' (expected dev|x11)" >&2
        exit 2
        ;;
esac

echo "[STEP] Installing profile packages (${PROFILE})..."
"${ssh_root[@]}" bash -s <<EOSSH
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ${pkg_list}
EOSSH

if [ "$PROFILE" = "x11" ]; then
    echo "[STEP] Enabling LightDM defaults (best-effort)..."
    "${ssh_root[@]}" bash -s <<'EOSSH'
set -e
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-hurd-defaults.conf <<'CONF'
[Seat:*]
user-session=xfce
# autologin-user=root
# autologin-user-timeout=0
CONF
if command -v update-rc.d >/dev/null 2>&1; then
  update-rc.d lightdm defaults || true
fi
EOSSH
fi

echo "[STEP] Final SSH and profile verification..."
HOST="$HOST" PORT="$PORT" USER_NAME=root PASSWORD="$ROOT_PASS" TIMEOUT_SEC=240 VERIFY_CMD="echo provision-ok" \
    "${SCRIPT_DIR}/wait-for-guest-ssh.sh"

if [ "$PROFILE" = "x11" ]; then
    "${ssh_root[@]}" "command -v Xorg >/dev/null && command -v startxfce4 >/dev/null"
fi

echo "[OK] Provisioning complete (${PROFILE})."
echo "[INFO] Root SSH:   ssh -p ${PORT} root@${HOST}"
echo "[INFO] Agents SSH: ssh -p ${PORT} agents@${HOST}"
