#!/bin/bash
# Fix and optimize apt sources for Debian GNU/Hurd (i386) on Debian-Ports (Nov 2025 best-practice)
# Requires: sshpass on host; SSH running in guest (root access)
# Usage: ROOT_PASS=root scripts/fix-sources-hurd.sh [-h host] [-p port]
set -euo pipefail
n# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ssh-helpers.sh
source "$SCRIPT_DIR/lib/ssh-helpers.sh"

HOST=localhost
PORT=2222
ROOT_PASS=${ROOT_PASS:-root}

while getopts ":h:p:" opt; do
  case $opt in
    h) HOST="$OPTARG" ;;
    p) PORT="$OPTARG" ;;
    *) echo "Usage: ROOT_PASS=... $0 [-h host] [-p port]" >&2; exit 2 ;;
  esac
done

ssh_cmd=(sshpass -p "$ROOT_PASS" ssh -o StrictHostKeyChecking=no -p "$PORT" root@"$HOST")

# Write sources.list for debian-ports (unstable + unreleased) and install keyring
"${ssh_cmd[@]}" bash -s <<'EOSSH'
set -euo pipefail
n# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ssh-helpers.sh
source "$SCRIPT_DIR/lib/ssh-helpers.sh"
backup=/etc/apt/sources.list.$(date +%Y%m%d%H%M%S).bak
[ -f /etc/apt/sources.list ] && cp -f /etc/apt/sources.list "$backup" || true
cat > /etc/apt/sources.list <<'EOF'
# Debian-Ports (GNU/Hurd i386) - Best practice (Nov 2025)
# Unofficial port: no security repo; track unstable and unreleased
# More info: https://www.debian.org/ports/hurd/
deb http://deb.debian.org/debian-ports unstable main
deb http://deb.debian.org/debian-ports unreleased main
# Optional source repos:
# deb-src http://deb.debian.org/debian-ports unstable main
# deb-src http://deb.debian.org/debian-ports unreleased main
EOF

# Ensure DNS works (fallback nameservers if empty)
if ! grep -qE 'nameserver\s' /etc/resolv.conf 2>/dev/null; then
  printf '%s\n' 'nameserver 1.1.1.1' 'nameserver 8.8.8.8' >> /etc/resolv.conf || true
fi

# First update (may need to allow insecure to fetch keyring)
apt-get -o Acquire::AllowInsecureRepositories=true update || true
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends --allow-unauthenticated \
  ca-certificates gnupg debian-ports-archive-keyring || true

# Proper update/upgrade with trusted key
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade

# Pin default release to unstable
mkdir -p /etc/apt/apt.conf.d
cat > /etc/apt/apt.conf.d/90defaultrelease <<'EOF'
APT::Default-Release "unstable";
EOF

# Networking helpers and SSH hardening baseline
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  sudo netbase ifupdown isc-dhcp-client inetutils-ping openssh-server random-egd

# Make sure eth0 is configured for DHCP
mkdir -p /etc/network
if ! grep -q 'auto eth0' /etc/network/interfaces 2>/dev/null; then
  cat >> /etc/network/interfaces <<'EOF'
auto eth0
allow-hotplug eth0
iface eth0 inet dhcp
EOF
fi

# Bring up network (best-effort)
if command -v ifup >/dev/null 2>&1; then ifup eth0 || true; fi
if command -v dhclient >/dev/null 2>&1; then dhclient -v eth0 || true; fi

# Ensure SSH is enabled
if [ -x /etc/init.d/ssh ]; then /etc/init.d/ssh restart || true; fi
update-rc.d ssh defaults || true

echo "[fix-sources-hurd] DONE: sources updated, keyring installed, system upgraded."
EOSSH

echo "OK: Debian-Ports sources fixed and system upgraded on $HOST:$PORT"