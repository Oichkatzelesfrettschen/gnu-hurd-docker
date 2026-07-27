#!/bin/bash
# Collect one guest's baseline in a single boot.
#
# Every closure verdict this repository holds was resolved against an empty dpkg
# status file, so a report says what the archive permits on an empty system
# rather than what this image would accept. The status file is what closes that,
# and a boot is expensive enough that collecting one artifact from it wastes the
# other nine.
#
# The guest is reached over SSH on a port the caller names. Nothing here mutates
# the canonical image: the caller boots a disposable overlay, and this script
# only reads. The one write it makes is to the host's output directory.

set -uo pipefail

SSH_KEY="${MINTY_SSH_KEY:-ssh-test-keys/hurd_test_key}"
SSH_PORT="${GUEST_SSH_PORT:-2222}"
SSH_USER="${GUEST_SSH_USER:-root}"
OUT="${OUTPUT_DIR:-evidence/guest-state}"
HOST="${GUEST_SSH_HOST:-127.0.0.1}"
# A disposable guest presents a key nobody has seen. accept-new against a
# per-run file records it once and verifies it thereafter, where disabling the
# check would accept any host for every later run.
KNOWN_HOSTS="${GUEST_KNOWN_HOSTS:-${OUT}/.known_hosts}"

log() { printf '%s\n' "$*" >&2; }

# A collection that half-succeeds must say which half. Each capture records its
# own exit status rather than leaving an empty file to be read as an empty
# answer.
FAILED=0

remote() {
    ssh -i "$SSH_KEY" -p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=20 \
        -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=${KNOWN_HOSTS}" \
        "${SSH_USER}@${HOST}" "$@" 2>/dev/null
}

capture() {
    local name="$1"; shift
    if remote "$@" > "${OUT}/${name}" ; then
        log "captured ${name}"
    else
        log "not captured: ${name}"
        printf 'not captured: the guest did not answer this query\n' > "${OUT}/${name}"
        FAILED=$((FAILED + 1))
    fi
}

mkdir -p "$OUT"

if ! remote 'echo up' | grep -q up; then
    log "not run: the guest did not answer on ${HOST}:${SSH_PORT}"
    exit 2
fi

# apt reads installed state as RFC822 paragraphs, so the status export is a
# separate mechanism with its own validation.
MINTY_SSH_KEY="$SSH_KEY" MINTY_SSH_PORT="$SSH_PORT" GUEST_SSH_USER="$SSH_USER" \
    GUEST_KNOWN_HOSTS="$KNOWN_HOSTS" OUTPUT_DIR="$OUT" \
    ./scripts/export-guest-package-state.sh \
    || log "package state export reported not run"

capture uname.txt 'uname -a'
capture nproc.txt 'nproc'
capture debian_version.txt 'cat /etc/debian_version'
capture dpkg-architecture.txt 'dpkg --print-architecture'
capture apt-version.txt 'apt-get --version'
capture dpkg-version.txt 'dpkg --version'
capture apt-sources.txt 'cat /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null'
capture apt-preferences.txt 'cat /etc/apt/preferences /etc/apt/preferences.d/* 2>/dev/null'
capture kernel-packages.txt 'dpkg-query -W -f=${binary:Package}\t${Version}\n gnumach-image-* hurd mig 2>/dev/null'
capture desktop-mode.txt 'cat /etc/hurd-desktop.mode /etc/hurd-desktop.session 2>/dev/null'
capture df.txt 'df -h'
capture free.txt 'free -m'

log "collection finished with ${FAILED} uncaptured item(s) in ${OUT}"
[ "$FAILED" -eq 0 ]
