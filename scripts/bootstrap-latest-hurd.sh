#!/bin/bash
set -euo pipefail

# End-to-end best-effort bootstrap for the newest Debian GNU/Hurd amd64 image:
# 1) resolve/download latest image
# 2) boot container with latest-image alias
# 3) run provisioning workflow (SSH + sources + user + base tooling)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

RUNTIME="${CONTAINER_RUNTIME:-docker}"
ROOT_PASS="${ROOT_PASS:-root}"
AGENTS_PASS="${AGENTS_PASS:-agents}"

if [[ "$RUNTIME" == "podman" ]]; then
    SSH_PORT="${SSH_PORT:-2223}"
    SERIAL_PORT="${SERIAL_PORT:-5556}"
    SERVICE_NAME="${SERVICE_NAME:-gnu-hurd-dev-podman}"
    UP_TARGET="up-podman-latest"
else
    SSH_PORT="${SSH_PORT:-2222}"
    SERIAL_PORT="${SERIAL_PORT:-5555}"
    SERVICE_NAME="${SERVICE_NAME:-gnu-hurd-dev}"
    UP_TARGET="up-latest"
fi

echo "[INFO] Runtime: ${RUNTIME}"
echo "[INFO] Service: ${SERVICE_NAME}"
echo "[INFO] SSH port: ${SSH_PORT}"
echo "[INFO] Serial port: ${SERIAL_PORT}"
echo ""

echo "[STEP] Resolving/downloading latest hurd-amd64 image..."
make setup-latest

echo ""
echo "[STEP] Booting latest image via make ${UP_TARGET}..."
CONTAINER_RUNTIME="$RUNTIME" make "$UP_TARGET"

echo ""
echo "[STEP] Running best-effort provisioning workflow..."
NONINTERACTIVE=1 \
CONTAINER_RUNTIME="$RUNTIME" \
SERVICE_NAME="$SERVICE_NAME" \
ROOT_PASS="$ROOT_PASS" \
AGENTS_PASS="$AGENTS_PASS" \
SSH_PORT="$SSH_PORT" \
SERIAL_PORT="$SERIAL_PORT" \
"${SCRIPT_DIR}/bringup-and-provision.sh"

echo ""
echo "[OK] Latest-image bootstrap flow completed."
echo "[INFO] Connect with: ssh -p ${SSH_PORT} root@localhost"
