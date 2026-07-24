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
#   2  the check could not be performed: bad arguments, guestfish absent, image
#      absent, partition absent, or the appliance failed to run.  This is
#      deliberately distinct from 1, so a caller never reads an environment
#      problem as guest corruption.
#
# Notes:
# - The guest names its root wd0s5; libguestfs exposes the same partition as
#   /dev/sda5 on the current Debian GNU/Hurd amd64 images.
# - guestfish e2fsck accepts exactly one of correct, forceall, or forceno.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INVOCATION_DIR="$PWD"
cd "$REPO_ROOT"

image="./images/debian-hurd-amd64.qcow2"
image_from_caller=0
partition="/dev/sda5"
repair=0
no_backup=0

usage() {
    sed -n '3,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

require_operand() {
    # Under `set -u` a missing operand would abort with a shell diagnostic
    # instead of the documented usage error, so check before dereferencing.
    [ $# -ge 2 ] || { echo "Missing value for $1" >&2; usage >&2; exit 2; }
}

while [ $# -gt 0 ]; do
    case "$1" in
        --image) require_operand "$@"; image="$2"; image_from_caller=1; shift 2 ;;
        --partition) require_operand "$@"; partition="$2"; shift 2 ;;
        --repair) repair=1; shift ;;
        --no-backup) no_backup=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

# The default image path is relative to the repository, but a caller-supplied
# one is relative to wherever they ran this from, and the script has already
# changed directory.
if [ "$image_from_caller" -eq 1 ] && [ "${image#/}" = "$image" ]; then
    image="$INVOCATION_DIR/$image"
fi

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
    check_output="$(guestfish --ro -a "$image" run : e2fsck "$partition" forceno:true 2>&1)" && {
        echo "[OK] guest filesystem $partition is clean"
        exit 0
    }

    # A non-zero exit here means either the filesystem is dirty or the check
    # could not run at all: a missing partition, an appliance that failed to
    # launch, a locked image, a permission error.  Reporting all of them as
    # corruption would send the reader to a repair that cannot help.
    #
    # Both cases arrive wrapped in the same "libguestfs: error: e2fsck:" prefix,
    # so the prefix cannot separate them.  What separates them is whether e2fsck
    # itself ran: a dirty filesystem produces its pass structure and declined
    # repair prompts, while a check that never started produces only the wrapper.
    if ! printf '%s' "$check_output" | grep -qE '^(Pass [0-9]+:|.*Fix\? no|e2fsck [0-9])'; then
        echo "[FAIL] the check could not be performed on $partition in $image" >&2
        printf '%s\n' "$check_output" >&2
        exit 2
    fi

    echo "[FAIL] guest filesystem $partition reports errors" >&2
    printf '%s\n' "$check_output" >&2
    echo "       The guest will stop at a maintenance shell instead of booting." >&2
    echo "       Repair with: $0 --repair --image $image" >&2
    exit 1
fi

if [ "$no_backup" -eq 0 ]; then
    backup="${image}.bak-$(date -u +%Y%m%dT%H%M%SZ)-$$"
    echo "[*] Backing up to $backup"
    # Reflink where the filesystem supports it, so a 2 GB backup is near-instant
    # and costs no space until one of the copies diverges.
    cp --reflink=auto --sparse=always -- "$image" "$backup" 2>/dev/null \
        || cp -- "$image" "$backup"
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
