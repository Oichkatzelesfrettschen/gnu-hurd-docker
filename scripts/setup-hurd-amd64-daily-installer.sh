#!/bin/bash
set -euo pipefail

# Download latest Debian installer mini.iso for hurd-amd64 (daily build),
# verify SHA256 when available, and prepare a fresh QCOW2 disk target.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

INSTALLER_DIR="${INSTALLER_DIR:-infrastructure/cache/images/installers}"
FRESH_IMAGE_DIR="${FRESH_IMAGE_DIR:-images}"
FRESH_QCOW2_SIZE="${FRESH_QCOW2_SIZE:-20G}"

echo ""
echo "================================================================"
echo "  Debian GNU/Hurd x86_64 Daily Installer Setup"
echo "================================================================"
echo ""

resolver_report="$("${SCRIPT_DIR}/resolve-latest-hurd-amd64-daily-installer.sh" report)"
if [ -z "$resolver_report" ]; then
    echo "[ERROR] Failed to resolve daily installer metadata" >&2
    exit 1
fi

daily_root=""
latest_build=""
build_date=""
artifact_path=""
artifact_url=""
sha256=""
while IFS='=' read -r key value; do
    case "$key" in
        DAILY_ROOT) daily_root="$value" ;;
        LATEST_BUILD) latest_build="$value" ;;
        BUILD_DATE) build_date="$value" ;;
        ARTIFACT_PATH) artifact_path="$value" ;;
        ARTIFACT_URL) artifact_url="$value" ;;
        SHA256) sha256="$value" ;;
    esac
done <<< "$resolver_report"

if [ -z "$latest_build" ] || [ -z "$artifact_url" ] || [ -z "$artifact_path" ] || [ -z "$build_date" ]; then
    echo "[ERROR] Resolver returned incomplete metadata" >&2
    echo "$resolver_report" >&2
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "[ERROR] curl is required" >&2
    exit 1
fi
if ! command -v qemu-img >/dev/null 2>&1; then
    echo "[ERROR] qemu-img is required (install qemu-utils on host)" >&2
    exit 1
fi
if ! command -v sha256sum >/dev/null 2>&1; then
    echo "[ERROR] sha256sum is required" >&2
    exit 1
fi

mkdir -p "$INSTALLER_DIR" "$FRESH_IMAGE_DIR"

safe_build="${latest_build//:/-}"
installer_basename="debian-hurd-amd64-installer-${safe_build}-mini.iso"
installer_path="${INSTALLER_DIR}/${installer_basename}"
installer_latest_alias="${INSTALLER_DIR}/debian-hurd-amd64-installer.latest-mini.iso"
installer_auto_basename="debian-hurd-amd64-installer-${safe_build}-mini-auto.iso"
installer_auto_path="${INSTALLER_DIR}/${installer_auto_basename}"
installer_auto_latest_alias="${INSTALLER_DIR}/debian-hurd-amd64-installer.latest-mini-auto.iso"

fresh_qcow2_basename="debian-hurd-amd64-fresh-${build_date}.qcow2"
fresh_qcow2_path="${FRESH_IMAGE_DIR}/${fresh_qcow2_basename}"
fresh_qcow2_alias="${FRESH_IMAGE_DIR}/debian-hurd-amd64.fresh.qcow2"

echo "[INFO] Daily root: ${daily_root}"
echo "[INFO] Latest build: ${latest_build}"
echo "[INFO] Installer artifact: ${artifact_path}"
echo "[INFO] Installer output: ${installer_path}"
echo "[INFO] Fresh disk output: ${fresh_qcow2_path} (${FRESH_QCOW2_SIZE})"
echo ""

if [ -f "$installer_path" ]; then
    echo "[SKIP] Installer already exists: ${installer_path}"
else
    echo "[STEP] Downloading installer ISO..."
    curl -fL "$artifact_url" -o "$installer_path"
fi

if [ -n "$sha256" ]; then
    echo "[STEP] Verifying installer SHA256..."
    actual_sha256="$(sha256sum "$installer_path" | awk '{print $1}')"
    if [ "$actual_sha256" != "$sha256" ]; then
        echo "[ERROR] SHA256 mismatch for ${installer_basename}" >&2
        echo "        expected: ${sha256}" >&2
        echo "        actual:   ${actual_sha256}" >&2
        exit 1
    fi
    echo "[OK] SHA256 verified"
else
    echo "[WARN] No SHA256 entry found for ${artifact_path}; skipped checksum verification"
fi

ln -sfn "$installer_basename" "$installer_latest_alias"

echo "[STEP] Building unattended installer ISO..."
BASE_ISO="$installer_path" \
OUTPUT_ISO="$installer_auto_path" \
PRESEED_FILE="${REPO_ROOT}/infrastructure/unattended/preseed.cfg" \
    "${SCRIPT_DIR}/build-hurd-unattended-iso.sh"
ln -sfn "$installer_auto_basename" "$installer_auto_latest_alias"

if [ -f "$fresh_qcow2_path" ]; then
    echo "[SKIP] Fresh QCOW2 already exists: ${fresh_qcow2_path}"
else
    echo "[STEP] Creating fresh QCOW2 target disk..."
    qemu-img create -f qcow2 "$fresh_qcow2_path" "$FRESH_QCOW2_SIZE" >/dev/null
    echo "[OK] Created fresh QCOW2 disk"
fi

ln -sfn "$fresh_qcow2_basename" "$fresh_qcow2_alias"

echo ""
echo "[SUCCESS] Daily installer assets prepared:"
echo "  - ${installer_path}"
echo "  - ${installer_latest_alias} -> ${installer_basename}"
echo "  - ${installer_auto_path}"
echo "  - ${installer_auto_latest_alias} -> ${installer_auto_basename}"
echo "  - ${fresh_qcow2_path}"
echo "  - ${fresh_qcow2_alias} -> ${fresh_qcow2_basename}"
echo ""
echo "[INFO] Installer boot (Docker):"
echo "  QEMU_CDROM=/opt/hurd-installer/debian-hurd-amd64-installer.latest-mini-auto.iso \\"
echo "  QEMU_BOOT_ORDER=d HURD_IMAGE_BASENAME=debian-hurd-amd64.fresh.qcow2 make up"
echo ""
echo "[INFO] Installer boot (Podman):"
echo "  QEMU_CDROM=/opt/hurd-installer/debian-hurd-amd64-installer.latest-mini-auto.iso \\"
echo "  QEMU_BOOT_ORDER=d HURD_IMAGE_BASENAME=debian-hurd-amd64.fresh.qcow2 \\"
echo "  PODMAN_COMPOSE_PROVIDER=podman-compose CONTAINER_RUNTIME=podman make up-podman"
