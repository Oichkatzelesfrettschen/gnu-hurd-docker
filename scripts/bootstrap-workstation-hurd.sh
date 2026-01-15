#!/bin/bash
# Bootstrap a GNU/Hurd guest into a usable dev workstation (best-effort).
# This script runs commands via SSH inside the guest. It does NOT require serial.
#
# Notes:
# - Debian GNU/Hurd repositories can be incomplete; many desktop packages may not exist.
# - This script is "strict on required steps" and "best-effort on optional groups".
#
# Usage:
#   ROOT_PASS=root SSH_PORT=2222 ./scripts/bootstrap-workstation-hurd.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ssh-helpers.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/ssh-helpers.sh"

HOST="${HOST:-localhost}"
SSH_PORT="${SSH_PORT:-2222}"
ROOT_PASS="${ROOT_PASS:-root}"

require_cmd sshpass ssh

ssh_cmd=(sshpass -p "$ROOT_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$SSH_PORT" root@"$HOST")

run_guest() {
  "${ssh_cmd[@]}" bash -lc "$1"
}

log_step() { printf '[workstation] %s\n' "$*" >&2; }

log_step "Checking SSH connectivity to ${HOST}:${SSH_PORT}..."
run_guest 'echo ok'

log_step "Ensuring DNS fallback..."
run_guest "grep -qE 'nameserver\\s' /etc/resolv.conf || printf '%s\n' 'nameserver 1.1.1.1' 'nameserver 8.8.8.8' >> /etc/resolv.conf || true"

log_step "Updating apt metadata..."
run_guest "DEBIAN_FRONTEND=noninteractive apt-get update"

log_step "Upgrading base system (best-effort)..."
run_guest "DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade || true"

log_step "Installing baseline dev tools..."
run_guest "DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \\
  ca-certificates \\
  sudo \\
  vim-tiny \\
  less \\
  netbase \\
  inetutils-ping \\
  curl \\
  wget \\
  git \\
  build-essential \\
  pkg-config \\
  make \\
  cmake \\
  ninja-build \\
  python3 \\
  python3-pip \\
  openssh-client \\
  locales \\
  tzdata"

log_step "Creating a non-root user 'dev' (if missing)..."
run_guest "id dev >/dev/null 2>&1 || (useradd -m -s /bin/bash dev && echo 'dev:dev' | chpasswd)"
run_guest "usermod -aG sudo dev || true"

log_step "Attempting to install Xfce desktop (optional)..."
run_guest "DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \\
  xorg \\
  xfce4 \\
  xfce4-goodies \\
  lightdm \\
  dbus-x11 \\
  xterm \\
  fonts-dejavu \\
  sudo || true"

log_step "Done. Next manual steps (inside guest):"
log_step "- Start a graphical console (depends on guest image capabilities)."
log_step "- Verify SSH works, then install additional packages as needed."

