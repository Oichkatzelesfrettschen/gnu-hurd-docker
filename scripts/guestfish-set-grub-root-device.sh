#!/bin/bash
set -euo pipefail

# Patch the guest's GRUB config to change the device name used for the root fs.
#
# Why:
# - Some host/QEMU combinations trigger GNU/Hurd IDE I/O errors (wd0).
# - Switching QEMU to SCSI can avoid the IDE DMA path, but GRUB needs to pass
#   root=...device:sd0 (instead of ...device:wd0).
#
# This script performs an offline edit on the qcow2 using guestfish.
#
# Usage:
#   ./scripts/guestfish-set-grub-root-device.sh --to sd0
#   ./scripts/guestfish-set-grub-root-device.sh --from wd0 --to sd0 --image ./images/debian-hurd-amd64.qcow2
#
# Notes:
# - Creates a timestamped backup next to the qcow2 unless --no-backup is set.
# - Default partition is /dev/sda1 (matches current upstream images).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

image="./images/debian-hurd-amd64.qcow2"
partition="/dev/sda1"
from="wd0"
to=""
no_backup=0
dry_run=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/guestfish-set-grub-root-device.sh --to sd0 [options]

Options:
  --image PATH         qcow2 path (default: ./images/debian-hurd-amd64.qcow2)
  --partition DEV      guestfish device partition (default: /dev/sda1)
  --from NAME          current GRUB root device name (default: wd0)
  --to NAME            new GRUB root device name (required)
  --dry-run            show diff only, do not write
  --no-backup          do not create a qcow2 backup

Example (switch to SCSI):
  ./scripts/guestfish-set-grub-root-device.sh --to sd0
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --image) image="${2:?}"; shift 2 ;;
    --partition) partition="${2:?}"; shift 2 ;;
    --from) from="${2:?}"; shift 2 ;;
    --to) to="${2:?}"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --no-backup) no_backup=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [ -z "$to" ]; then
  echo "ERROR: --to is required" >&2
  usage
  exit 2
fi

if ! command -v guestfish >/dev/null 2>&1; then
  echo "ERROR: guestfish not found. Install libguestfs (package often named 'libguestfs')." >&2
  exit 1
fi

if [ ! -f "$image" ]; then
  echo "ERROR: qcow2 not found: $image" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

orig="${tmp_dir}/grub.cfg.orig"
patched="${tmp_dir}/grub.cfg.patched"

echo "[*] Reading /boot/grub/grub.cfg from $image (partition $partition)..."
guestfish --ro -a "$image" <<EOF >/dev/null
run
mount $partition /
download /boot/grub/grub.cfg $orig
EOF

if ! grep -q "device:${from}" "$orig"; then
  echo "ERROR: did not find 'device:${from}' in grub.cfg; refusing to patch." >&2
  echo "Hint: inspect $orig and adjust --from/--to or --partition." >&2
  exit 1
fi

sed "s/device:${from}/device:${to}/g" "$orig" >"$patched"

echo "[*] Proposed changes:"
diff -u "$orig" "$patched" || true

if [ "$dry_run" = "1" ]; then
  echo "[OK] dry-run complete (no changes written)"
  exit 0
fi

if [ "$no_backup" != "1" ]; then
  backup="${image}.bak.$(date +%Y%m%d-%H%M%S)"
  echo "[*] Backing up qcow2 -> $backup"
  cp -a "$image" "$backup"
fi

echo "[*] Writing patched grub.cfg..."
guestfish -a "$image" <<EOF >/dev/null
run
mount $partition /
upload $patched /boot/grub/grub.cfg
EOF

echo "[OK] Patched GRUB root device: ${from} -> ${to}"

