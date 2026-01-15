#!/bin/bash
set -euo pipefail

# Offline bootstrap fixes for Debian GNU/Hurd qcow2 images using guestfish.
#
# Goals:
# - Keep init/getty stable (avoid replacing console getty, which can cause init respawn storms).
# - Fix /run tmpfs mounting bugs in Debian initscripts (some images ship a broken mount_run()).
# - Ensure basic writable dirs exist with sane perms: /run, /tmp, /dev/shm.
#
# This script is intentionally conservative:
# - It edits only a small set of files.
# - It prints diffs for review before writing.
# - It creates a timestamped backup by default.
#
# Usage:
#   ./scripts/guestfish-bootstrap-hurd-console.sh
#   ./scripts/guestfish-bootstrap-hurd-console.sh --image ./images/debian-hurd-amd64.qcow2
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

image="./images/debian-hurd-amd64.qcow2"
root_part="/dev/sda5"
no_backup=0
dry_run=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/guestfish-bootstrap-hurd-console.sh [options]

Options:
  --image PATH         qcow2 path (default: ./images/debian-hurd-amd64.qcow2)
  --root-part DEV      root partition (default: /dev/sda5)
  --dry-run            show diffs only, do not write
  --no-backup          do not create a qcow2 backup
  -h, --help           show help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --image) image="${2:?}"; shift 2 ;;
    --root-part) root_part="${2:?}"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --no-backup) no_backup=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[ERROR] Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if ! command -v guestfish >/dev/null 2>&1; then
  echo "[ERROR] guestfish not found. Install libguestfs." >&2
  exit 1
fi
if [ ! -f "$image" ]; then
  echo "[ERROR] qcow2 not found: $image" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

inittab_orig="${tmp_dir}/inittab.orig"
inittab_new="${tmp_dir}/inittab.new"
mountfn_orig="${tmp_dir}/mount-functions.orig"
mountfn_new="${tmp_dir}/mount-functions.new"

echo "[*] Reading guest files from $image (root $root_part)..."
LIBGUESTFS_BACKEND=direct guestfish --ro -a "$image" <<EOF >/dev/null
run
mount $root_part /
download /etc/inittab $inittab_orig
download /lib/init/mount-functions.sh $mountfn_orig
EOF

cp "$inittab_orig" "$inittab_new"
cp "$mountfn_orig" "$mountfn_new"

#
# 1) Ensure console is stable
#
python3 - "$inittab_new" <<'PY'
import re
import sys

path = sys.argv[1]
data = open(path, "r", encoding="utf-8", errors="replace").read().splitlines(True)

out = []

have_tty1 = False
have_console = False

for line in data:
    # Drop any previously injected agent notes to keep the file "upstream-ish".
    if "Codex:" in line:
        continue

    # Drop unsafe shells on tty1/console; they cause init respawn storms on Hurd.
    if line.startswith("1:") and "/bin/sh" in line:
        continue
    if line.startswith("c:") and "/bin/sh" in line:
        continue

    # Keep only a single getty on tty1/console.
    if line.startswith("1:") and "/sbin/getty" in line and "tty1" in line:
        if have_tty1:
            continue
        have_tty1 = True
    if line.startswith("c:") and "/sbin/getty" in line and "console" in line:
        if have_console:
            continue
        have_console = True

    out.append(line)

if not have_tty1:
    # Ensure at least one interactive getty exists on tty1.
    out.append("1:2345:respawn:/sbin/getty --noclear 38400 tty1\n")

if not have_console:
    # Ensure Hurd console getty exists; replacing this with a shell causes respawn storms.
    out.append("c:23:respawn:/sbin/getty 38400 console\n")

open(path, "w", encoding="utf-8").write("".join(out))
PY

#
# 2) Fix mount_run() implementation issues
#
# Some upstream hurd-amd64 images have shipped a broken `mount_run()` which
# contains an unconditional `exit 0`, causing early-boot mount scripts to bail
# out and leaving `/run` unusable.
#
# Additionally, if a previous bootstrap run injected a GNU guard block, remove it
# so the system can use the normal tmpfs-on-/run behavior when it works.
#
python3 - "$mountfn_new" <<'PY'
import re
import sys

path = sys.argv[1]
data = open(path, "r", encoding="utf-8", errors="replace").read()

# Locate mount_run() and:
# - remove an incorrect early 'exit 0'
# - remove a previously injected GNU guard (if present)

if "mount_run()" not in data or "mount_run() {" not in data:
    sys.stderr.write("[WARN] mount_run() not found; leaving mount-functions.sh unchanged\n")
    sys.exit(0)

# Remove an incorrect early-exit if present (seen in some images).
data2, _n_exit = re.subn(
    r"(\n\s*# Needed to determine if root is being mounted read-only\.\n\s*read_fstab\s*\n)\s*exit\s+0\s*\n",
    r"\1",
    data,
    count=1,
    flags=re.M,
)

# Remove previously injected GNU guard block (best-effort).
lines = data2.splitlines(True)
out = []
skip = False
removed = 0
for i, line in enumerate(lines):
    if not skip and line.startswith("\tcase \"$KERNEL\" in\n"):
        # Look ahead for our unique marker.
        window = "".join(lines[i : i + 10])
        if "GNU/Hurd: avoid tmpfs mounts for /run" in window:
            skip = True
            removed += 1
            continue
    if skip:
        if line.startswith("\tesac\n"):
            skip = False
        continue
    out.append(line)

open(path, "w", encoding="utf-8").write("".join(out))
PY

echo "[*] Diffs:"
echo "---- /etc/inittab"
diff -u "$inittab_orig" "$inittab_new" || true
echo "---- /lib/init/mount-functions.sh"
diff -u "$mountfn_orig" "$mountfn_new" || true

if [ "$dry_run" = "1" ]; then
  echo "[OK] dry-run complete (no changes written)"
  exit 0
fi

if [ "$no_backup" != "1" ]; then
  backup="${image}.bak.$(date +%Y%m%d-%H%M%S)"
  echo "[*] Backing up qcow2 -> $backup"
  cp -a "$image" "$backup"
fi

echo "[*] Writing patched files to qcow2..."
LIBGUESTFS_BACKEND=direct guestfish -a "$image" <<EOF >/dev/null
run
mount $root_part /
upload $inittab_new /etc/inittab
upload $mountfn_new /lib/init/mount-functions.sh

# Ensure directories exist with sane perms
mkdir-p /run
chmod 0755 /run
mkdir-p /run/lock
chmod 1777 /run/lock
mkdir-p /tmp
chmod 1777 /tmp

# Disable ssh autostart (sshd crashes on some images; start it manually after fixing)
rm-f /etc/rc2.d/S02ssh
EOF

echo "[OK] Patched image bootstrap for init/getty stability + mount_run fix + ssh disable: $image"
