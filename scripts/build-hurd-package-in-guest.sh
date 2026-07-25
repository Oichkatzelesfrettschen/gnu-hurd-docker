#!/usr/bin/env bash
# Rebuild a Debian source package inside the running Hurd guest and install it.
#
# The archive gap this closes is a build gap rather than a porting gap. A
# package such as mate-settings-daemon ships an Architecture: hurd-i386 binary
# at the same source version the main archive carries, so the source already
# builds on the Hurd; hurd-amd64 simply has no upload of it. Rebuilding on the
# guest produces the binary from that same source.
#
# debian-ports publishes binaries only. Source comes from the main Debian
# archive, which is architecture-independent, so a deb-src line pointing there
# serves both Hurd ports.
#
# The guest writes straight through to the qcow2 with no overlay, so this
# demands a snapshot name and refuses to run without one. The rollback is the
# snapshot, and a build that fills the disk or half-installs a package is
# exactly what a rollback is for.

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
usage: build-hurd-package-in-guest.sh --snapshot NAME PACKAGE [PACKAGE...]

  --snapshot NAME   qcow2 snapshot taken before this runs; required
  --ssh-port PORT   host port forwarded to guest 22 (default 2222)
  --ssh-key PATH    private key (default ssh-test-keys/hurd_test_key)
  --user NAME       guest user (default root)
  --dry-run         print the guest script instead of running it
EOF
    exit 2
}

SNAPSHOT=""
SSH_PORT="${RUNTIME_EVIDENCE_SSH_PORT:-2222}"
SSH_KEY="${RUNTIME_EVIDENCE_SSH_KEY:-ssh-test-keys/hurd_test_key}"
SSH_USER="${RUNTIME_EVIDENCE_SSH_USER:-root}"
DRY_RUN=0
PACKAGES=()

while [ $# -gt 0 ]; do
    case "$1" in
        --snapshot) SNAPSHOT="${2:-}"; shift 2 ;;
        --ssh-port) SSH_PORT="${2:-}"; shift 2 ;;
        --ssh-key) SSH_KEY="${2:-}"; shift 2 ;;
        --user) SSH_USER="${2:-}"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage ;;
        -*) printf 'unknown option: %s\n' "$1" >&2; usage ;;
        *) PACKAGES+=("$1"); shift ;;
    esac
done

[ -n "$SNAPSHOT" ] || { printf 'a snapshot name is required\n' >&2; usage; }
[ "${#PACKAGES[@]}" -gt 0 ] || { printf 'name at least one source package\n' >&2; usage; }

# The build script runs on the guest.  It installs build dependencies, fetches
# the source from the main archive, builds without signing, and installs the
# resulting binaries.  DEB_BUILD_OPTIONS drops tests and documentation, because
# a guest with one processor spends most of a build in them.
guest_script() {
    cat <<EOF
set -eux
export DEBIAN_FRONTEND=noninteractive
export DEB_BUILD_OPTIONS="nocheck nodoc parallel=1"

if ! grep -qs 'deb-src .*deb.debian.org/debian sid main' /etc/apt/sources.list /etc/apt/sources.list.d/*; then
    echo 'deb-src http://deb.debian.org/debian sid main' >> /etc/apt/sources.list
fi

apt-get update
apt-get install -y --no-install-recommends build-essential dpkg-dev fakeroot devscripts

mkdir -p /var/tmp/hurd-rebuild
cd /var/tmp/hurd-rebuild

for source in ${PACKAGES[*]}; do
    apt-get build-dep -y --no-install-recommends "\$source"
    apt-get source "\$source"
    directory=\$(find . -maxdepth 1 -type d -name "\$source-*" | head -1)
    cd "\$directory"
    dpkg-buildpackage -us -uc -b
    cd ..
    # Installing with apt rather than dpkg resolves the new binaries' own
    # runtime dependencies from the archive in the same step.
    apt-get install -y --no-install-recommends ./*.deb || dpkg -i ./*.deb
    rm -f ./*.deb
done

echo "rebuild complete"
EOF
}

if [ "$DRY_RUN" -eq 1 ]; then
    guest_script
    exit 0
fi

printf 'snapshot asserted: %s\n' "$SNAPSHOT" >&2
printf 'building on the guest: %s\n' "${PACKAGES[*]}" >&2

guest_script | ssh \
    -i "$SSH_KEY" \
    -p "$SSH_PORT" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=15 \
    -o BatchMode=yes \
    "${SSH_USER}@127.0.0.1" \
    "sh -s"
