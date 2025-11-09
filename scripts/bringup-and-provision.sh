#!/bin/bash
# Orchestrate container boot, SSH enablement, sources fix, users, and dev setup
# Requires: docker, telnet, expect, sshpass on host
# WHY: Ensure container and SSH sessions are cleaned on abnormal exit
# WHAT: Track container name and SSH connections for cleanup
# HOW: cleanup() stops container only if we started it; kills SSH sessions
set -euo pipefail

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ssh-helpers.sh
source "$SCRIPT_DIR/lib/ssh-helpers.sh"
# shellcheck source=lib/container-helpers.sh
source "$SCRIPT_DIR/lib/container-helpers.sh"

ROOT_PASS=${ROOT_PASS:-root}
AGENTS_PASS=${AGENTS_PASS:-agents}
HOST=localhost
SSH_PORT=2222
SERIAL_PORT=${SERIAL_PORT:-5555}
CONTAINER_NAME="gnu-hurd-dev"

# Track cleanup state
CLEANUP_NEEDED=false
CONTAINER_STARTED_BY_SCRIPT=false
SSH_SESSIONS=()

cleanup() {
    local exit_code=$?
    
    if [ "$CLEANUP_NEEDED" = true ]; then
        echo ""
        echo "[INFO] Cleaning up..."
        
        # Kill SSH background processes
        for pid in "${SSH_SESSIONS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
                echo "  [INFO] Terminated SSH session: PID $pid"
            fi
        done
        
        # Stop container only if this script started it
        if [ "$CONTAINER_STARTED_BY_SCRIPT" = true ]; then
            if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
                echo "  [INFO] Stopping container: $CONTAINER_NAME"
                docker compose down 2>/dev/null || true
            fi
        fi
    fi
    
    exit $exit_code
}

trap cleanup EXIT INT TERM

# 1) Boot container
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  docker compose up -d
  CONTAINER_STARTED_BY_SCRIPT=true
  CLEANUP_NEEDED=true
fi

echo "Waiting for serial (telnet $HOST:$SERIAL_PORT) ..."
for _ in {1..120}; do
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