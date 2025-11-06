#!/bin/bash
# Orchestrate container boot, SSH enablement, sources fix, users, and dev setup
# Requires: docker, docker-compose, telnet, expect, sshpass on host
set -euo pipefail

ROOT_PASS=${ROOT_PASS:-root}
AGENTS_PASS=${AGENTS_PASS:-agents}
HOST=localhost
SSH_PORT=2222
SERIAL_PORT=${SERIAL_PORT:-5555}

# 1) Boot container
if ! docker ps --format '{{.Names}}' | grep -q '^gnu-hurd-dev$'; then
  docker-compose up -d
fi

echo "Waiting for serial (telnet $HOST:$SERIAL_PORT) ..."
for i in {1..120}; do
  if nc -z "$HOST" "$SERIAL_PORT" 2>/dev/null; then break; fi
  sleep 2
done

# 2) Enable SSH inside guest and set root password (via serial automation)
# Enable SSH with password auth
./scripts/install-ssh-hurd.sh

# 3) Fix Debian-Ports sources and upgrade
ROOT_PASS="$ROOT_PASS" ./scripts/fix-sources-hurd.sh -h "$HOST" -p "$SSH_PORT"

# 4) Create agents sudo user via SSH
sshpass -p "$ROOT_PASS" ssh -o StrictHostKeyChecking=no -p "$SSH_PORT" root@"$HOST" bash -s <<EOSSH
set -e
id agents >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo agents
printf 'agents:%s\n' "$AGENTS_PASS" | chpasswd
mkdir -p /etc/sudoers.d
printf 'agents ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/agents
chmod 0440 /etc/sudoers.d/agents
EOSSH

# 5) Optional: basic dev toolchain (quick set)
sshpass -p "$ROOT_PASS" ssh -o StrictHostKeyChecking=no -p "$SSH_PORT" root@"$HOST" \
  'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y gcc make git vim openssh-client'

echo "\nProvisioning complete. Try: ssh -p $SSH_PORT root@localhost (pwd: $ROOT_PASS) or agents@$HOST (pwd: $AGENTS_PASS)."