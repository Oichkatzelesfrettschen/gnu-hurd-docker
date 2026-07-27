#!/bin/bash
# Export the guest's installed-package state as an evidence artifact.
#
# Every closure verdict this repository has recorded was resolved against a
# private apt tree whose dpkg status file is empty, which is what
# provenance.installed_baseline names. On an empty system a transaction has no
# installed package to displace, so `native_packages_removed` is empty by
# construction rather than by observation, and a resolved set is a statement
# about what the archive permits somewhere rather than about what this image
# would accept.
#
# The status file is what closes that gap. Seeding the resolver's tree with it
# turns availability into a prediction about the real guest: whether an install
# would replace an installed package, whether a foreign transaction would
# displace the native userland, and whether the Mint visual manifest lands
# without removing anything.
#
# The export carries package identity only. dpkg status paragraphs also carry
# maintainer addresses and package descriptions, which are archive text rather
# than machine state, so the fields kept are the ones a resolver reads.

set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-gnu-hurd-dev}"
SSH_KEY="${MINTY_SSH_KEY:-ssh-test-keys/hurd_test_key}"
SSH_PORT="${MINTY_SSH_PORT:-${SSH_PORT:-2222}}"
SSH_USER="${GUEST_SSH_USER:-root}"
OUTPUT_DIR="${OUTPUT_DIR:-evidence/guest-state}"

log() { printf '%s\n' "$*" >&2; }

if [ ! -f "$SSH_KEY" ]; then
    log "not run: no SSH key at ${SSH_KEY}, so the guest was never queried"
    exit 2
fi

mkdir -p "$OUTPUT_DIR"

# apt reads installed state as RFC822 paragraphs, so a table of columns is not
# an input it can take. dpkg-query renders the paragraphs directly, which avoids
# copying /var/lib/dpkg/status wholesale and carrying every maintainer address
# and long description into a committed artifact.
#
# Status is spelled from its three parts rather than the abbreviated form,
# because apt parses "install ok installed" and not "ii".
#
# The format string is quoted for the remote shell, not just for this one. ssh
# concatenates its arguments and the remote shell reparses them, so an unquoted
# format containing spaces arrives as several words and dpkg-query reads only
# the first. A quoted heredoc keeps the dpkg field syntax out of both shells.
read -r -d '' query <<'REMOTE' || true
dpkg-query -W -f='Package: ${binary:Package}
Status: ${db:Status-Want} ${db:Status-Eflag} ${db:Status-Status}
Priority: ${Priority}
Architecture: ${Architecture}
Multi-Arch: ${Multi-Arch}
Essential: ${Essential}
Version: ${Version}

'
REMOTE

if ! raw="$(ssh -i "$SSH_KEY" -p "$SSH_PORT" \
        -o BatchMode=yes -o ConnectTimeout=20 \
        "${SSH_USER}@127.0.0.1" "$query" 2>/dev/null)"; then
    log "not run: the guest did not answer on port ${SSH_PORT}"
    exit 2
fi

if [ -z "$raw" ]; then
    log "not run: the guest returned no package state"
    exit 2
fi

architecture="$(ssh -i "$SSH_KEY" -p "$SSH_PORT" -o BatchMode=yes \
    "${SSH_USER}@127.0.0.1" 'dpkg --print-architecture' 2>/dev/null || echo "")"
kernel="$(ssh -i "$SSH_KEY" -p "$SSH_PORT" -o BatchMode=yes \
    "${SSH_USER}@127.0.0.1" 'uname -a' 2>/dev/null || echo "")"

destination="${OUTPUT_DIR}/${architecture:-unknown}-dpkg-status"

# A field dpkg-query has no value for renders as an empty value, and apt treats
# an empty Priority or Multi-Arch as a malformed paragraph rather than an absent
# field, so those lines are dropped instead of emitted blank.
printf '%s\n' "$raw" \
    | awk 'NF == 1 && /:$/ { next } { print }' \
    | awk 'BEGIN { blank = 0 }
           /^$/ { blank++; next }
           { if (blank && NR > 1) print ""; blank = 0; print }' \
    > "$destination"
printf '\n' >> "$destination"

digest="$(sha256sum "$destination" | cut -d' ' -f1)"
count="$(grep -c '^Package: ' "$destination" || true)"

# The manifest is what a resolver run cites; the digest is what says two runs
# read the same guest.
cat > "${OUTPUT_DIR}/${architecture:-unknown}-dpkg-status.json" <<EOF
{
  "schema_version": 2,
  "kind": "guest-dpkg-status",
  "architecture": "${architecture}",
  "kernel": "${kernel}",
  "package_count": ${count},
  "manifest": "$(basename "$destination")",
  "manifest_sha256": "${digest}",
  "source_image_sha256": "${GUEST_IMAGE_SHA256:-}"
}
EOF

log "exported ${count} packages for ${architecture:-unknown} to ${destination}"
