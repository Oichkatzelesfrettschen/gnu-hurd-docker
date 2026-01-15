#!/bin/bash
set -euo pipefail

# Container-level smoke test (no guest assumptions).
# Verifies compose config, container start/stop, and that QEMU is spawned.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "$REPO_ROOT"

# shellcheck source=lib/container-runtime.sh
source "${SCRIPT_DIR}/lib/container-runtime.sh"

SERVICE_NAME="${SERVICE_NAME:-gnu-hurd-dev}"

echo "[*] Validating repo invariants..."
./scripts/validate-config.sh
./scripts/validate-security-config.sh

echo ""
echo "[*] Ensuring compose configs parse..."
container_compose -f docker-compose.yml config >/dev/null
container_compose -f docker-compose.yml -f docker-compose.bind.yml config >/dev/null
container_compose -f docker-compose.yml -f docker-compose.kvm.yml config >/dev/null

echo ""
echo "[*] Starting container (bind mode)..."
./scripts/docker-orchestration.sh up

echo ""
echo "[*] Waiting for QEMU process to appear..."
for _ in {1..60}; do
  runtime="$(get_container_runtime)"
  if "$runtime" exec "$SERVICE_NAME" pgrep -x qemu-system-x86_64 >/dev/null 2>&1; then
    echo "[OK] QEMU process running inside container"
    break
  fi
  sleep 2
done

runtime="$(get_container_runtime)"
if ! "$runtime" exec "$SERVICE_NAME" pgrep -x qemu-system-x86_64 >/dev/null 2>&1; then
  echo "[ERROR] QEMU process not found in container after timeout" >&2
  echo "[INFO] Recent container logs:" >&2
  ./scripts/docker-orchestration.sh logs >&2 || true
  exit 1
fi

echo ""
echo "[*] Container health (if available):"
if command -v jq >/dev/null 2>&1; then
  "$runtime" inspect "$SERVICE_NAME" --format '{{json .State.Health}}' 2>/dev/null | jq . || true
else
  "$runtime" inspect "$SERVICE_NAME" --format '{{json .State.Health}}' 2>/dev/null || true
fi

echo ""
echo "[OK] Container smoke test complete"
