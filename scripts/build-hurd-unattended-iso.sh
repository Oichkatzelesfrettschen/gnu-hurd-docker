#!/bin/bash
set -euo pipefail

# Build an unattended Debian GNU/Hurd installer ISO by patching grub.cfg
# and injecting a preseed file at /preseed.cfg.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

BASE_ISO="${BASE_ISO:-}"
OUTPUT_ISO="${OUTPUT_ISO:-}"
PRESEED_FILE="${PRESEED_FILE:-infrastructure/unattended/preseed.cfg}"

if [ -z "$BASE_ISO" ] || [ -z "$OUTPUT_ISO" ]; then
    echo "Usage: BASE_ISO=/path/base.iso OUTPUT_ISO=/path/output-auto.iso [PRESEED_FILE=...] $0" >&2
    exit 2
fi

if [ ! -f "$BASE_ISO" ]; then
    echo "[ERROR] BASE_ISO not found: $BASE_ISO" >&2
    exit 1
fi
if [ ! -f "$PRESEED_FILE" ]; then
    echo "[ERROR] PRESEED_FILE not found: $PRESEED_FILE" >&2
    exit 1
fi
if ! command -v xorriso >/dev/null 2>&1; then
    echo "[ERROR] xorriso is required" >&2
    exit 1
fi

workdir="$(mktemp -d -t hurd-auto-iso.XXXXXX)"
cleanup() {
    rm -rf "$workdir"
}
trap cleanup EXIT

orig_grub="${workdir}/grub.cfg.orig"
patched_grub="${workdir}/grub.cfg"

xorriso -indev "$BASE_ISO" -osirrox on -extract /boot/grub/grub.cfg "$orig_grub" >/dev/null 2>&1
cp "$orig_grub" "$patched_grub"

# Set a short timeout and default to "Automated install" entry.
# In the current mini.iso grub.cfg, this entry index is 6.
sed -i 's/^set timeout=.*/set timeout=5/' "$patched_grub"
sed -i 's/^set default=.*/set default=6/' "$patched_grub"

# Inject deterministic boot parameters for unattended install.
# Keep TERM=mach-gnu-color for better compatibility with Hurd installer text mode.
sed -i 's@set options="auto=true priority=critical TERM=mach-gnu-color"@set options="auto=true priority=critical preseed/file=/preseed.cfg netcfg/choose_interface=auto TERM=mach-gnu-color"@' "$patched_grub"

mkdir -p "$(dirname "$OUTPUT_ISO")"
rm -f "$OUTPUT_ISO"

# Replay the original boot catalog/MBR/GPT and only replace two files.
xorriso \
    -indev "$BASE_ISO" \
    -outdev "$OUTPUT_ISO" \
    -boot_image any replay \
    -map "$PRESEED_FILE" /preseed.cfg \
    -map "$patched_grub" /boot/grub/grub.cfg \
    -commit >/dev/null

echo "[OK] Unattended ISO created: $OUTPUT_ISO"
echo "[INFO] Base ISO: $BASE_ISO"
echo "[INFO] Preseed: $PRESEED_FILE"
