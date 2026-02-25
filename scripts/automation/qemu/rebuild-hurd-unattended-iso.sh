#!/bin/bash
set -euo pipefail

# Rebuild the unattended Hurd installer ISO from a locally cached base ISO.
# This does not download anything and is safe to run offline.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "$REPO_ROOT"

BASE_ISO="${BASE_ISO:-infrastructure/cache/images/installers/debian-hurd-amd64-installer.latest-mini.iso}"
OUTPUT_ISO="${OUTPUT_ISO:-infrastructure/cache/images/installers/debian-hurd-amd64-installer.latest-mini-auto.iso}"
PRESEED_FILE="${PRESEED_FILE:-infrastructure/unattended/preseed.cfg}"

if [ ! -f "$BASE_ISO" ]; then
    echo "[ERROR] Missing base ISO: $BASE_ISO" >&2
    echo "[HINT] Run: make setup-daily-installer" >&2
    exit 1
fi
if [ ! -f "$PRESEED_FILE" ]; then
    echo "[ERROR] Missing preseed file: $PRESEED_FILE" >&2
    exit 1
fi

echo "[INFO] Rebuilding unattended ISO from local cache"
echo "[INFO] Base: $BASE_ISO"
echo "[INFO] Output: $OUTPUT_ISO"
echo "[INFO] Preseed: $PRESEED_FILE"

BASE_ISO="$BASE_ISO" \
OUTPUT_ISO="$OUTPUT_ISO" \
PRESEED_FILE="$PRESEED_FILE" \
    "${REPO_ROOT}/scripts/build-hurd-unattended-iso.sh"

echo "[SUCCESS] Unattended ISO rebuilt"
