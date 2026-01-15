#!/bin/bash
set -euo pipefail

# Host-side smoke test: validates repo consistency and basic prerequisites.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "$REPO_ROOT"

echo "[*] Validating repository configuration..."
"$SCRIPT_DIR/validate-config.sh"

echo ""
echo "[*] Checking container runtime detection..."
# shellcheck source=lib/container-runtime.sh
source "$SCRIPT_DIR/lib/container-runtime.sh"
check_runtime_compatibility || true

echo ""
if [[ -f images/debian-hurd-amd64.qcow2 ]]; then
  echo "[OK] Found images/debian-hurd-amd64.qcow2"
else
  echo "[WARN] Missing images/debian-hurd-amd64.qcow2"
  echo "      Dev (bind):    ./scripts/setup-hurd-amd64.sh"
  echo "      Dev + KVM:     ./scripts/setup-hurd-amd64.sh && ./scripts/docker-orchestration.sh up-kvm"
  echo "      Volume (auto): AUTO_DOWNLOAD_IMAGE=1 ./scripts/docker-orchestration.sh up-volume"
fi

echo ""
echo "[OK] Host smoke test complete"
