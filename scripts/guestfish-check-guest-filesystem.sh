#!/bin/bash
set -euo pipefail

# Check, and optionally repair, the guest root filesystem inside a Hurd qcow2.
#
# Why:
# - qemu-img check inspects the qcow2 container and reports success on images
#   whose guest filesystem is corrupt.  A dirty ext2 root stops the boot at
#   "UNEXPECTED INCONSISTENCY; RUN fsck MANUALLY" and drops to a maintenance
#   shell, so the guest never reaches multi-user state and SSH never answers.
# - Container-level checks cannot see that, so this reads the filesystem itself.
#
# The default mode is read-only and reports without writing, which makes it
# usable as a gate.  --repair runs a forced non-interactive e2fsck, which
# rewrites the image and therefore takes a backup first.
#
# Usage:
#   ./scripts/guestfish-check-guest-filesystem.sh
#   ./scripts/guestfish-check-guest-filesystem.sh --image ./images/other.qcow2
#   ./scripts/guestfish-check-guest-filesystem.sh --repair
#
# Exit status:
#   0  filesystem is clean, or repair completed
#   1  filesystem needs repair (check mode), or repair failed
#   2  prerequisites missing (guestfish absent, image absent)
#
# Notes:
# - The guest names its root wd0s5; libguestfs exposes the same partition as
#   /dev/sda5 on the current Debian GNU/Hurd amd64 images.
# - guestfish e2fsck accepts exactly one of correct, forceall, or forceno.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

image="./images/debian-hurd-amd64.qcow2"
partition="/dev/sda5"
repair=0
no_backup=0

usage() {
    sed -n '3,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --image) image="$2"; shift 2 ;;
        --partition) partition="$2"; shift 2 ;;
        --repair) repair=1; shift ;;
        --no-backup) no_backup=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if ! command -v guestfish >/dev/null 2>&1; then
    echo "[SKIP] guestfish not installed; install libguestfs to check the guest filesystem" >&2
    exit 2
fi

if [ ! -f "$image" ]; then
    echo "[SKIP] image not found: $image" >&2
    exit 2
fi

if [ "$repair" -eq 0 ]; then
    # forceno is the non-interactive read-only pass: it answers "no" to every
    # repair prompt, so a dirty filesystem surfaces as a non-zero exit without
    # the image being written.
    echo "[*] Checking $partition in $image (read-only)"
    if guestfish --ro -a "$image" run : e2fsck "$partition" forceno:true >/dev/null 2>&1; then
        echo "[OK] guest filesystem $partition is clean"
        exit 0
    fi
    echo "[FAIL] guest filesystem $partition reports errors" >&2
    echo "       The guest will stop at a maintenance shell instead of booting." >&2
    echo "       Repair with: $0 --repair --image $image" >&2
    exit 1
fi

if [ "$no_backup" -eq 0 ]; then
    backup="${image}.bak-$(date -u +%Y%m%dT%H%M%SZ)"
    echo "[*] Backing up to $backup"
    cp -- "$image" "$backup"
fi

echo "[*] Repairing $partition in $image (forced, non-interactive)"
guestfish -a "$image" run : e2fsck "$partition" forceall:true

echo "[*] Re-checking after repair"
if guestfish --ro -a "$image" run : e2fsck "$partition" forceno:true >/dev/null 2>&1; then
    echo "[OK] guest filesystem $partition is clean after repair"
    exit 0
fi

echo "[FAIL] $partition still reports errors after a forced e2fsck" >&2
echo "       Inspect manually: virt-rescue -a $image" >&2
exit 1
