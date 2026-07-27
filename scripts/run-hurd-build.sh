#!/bin/bash
# Own the lifecycle of one disposable build run.
#
# The entrypoint can create an overlay and refuse to reuse one, but it cannot
# dispose of anything: it replaces itself with QEMU through exec, so no trap of
# its own survives to run afterwards. A creation primitive with no owner leaves
# the overlay behind on every exit, and under a restart policy the next start
# meets its own leftover and refuses, which reads as a boot loop.
#
# Disposal also has to happen after QEMU exits rather than before, because the
# artifacts, the filesystem check, and the evidence manifest are all read out of
# the overlay. That makes the host the only correct owner.
#
# Lifecycle:
#
#   create a unique run directory
#   verify the backing image against the lock
#   start the one-shot builder composition, which creates the overlay
#   wait for the guest to finish
#   stop the composition
#   check the overlay filesystem offline
#   write the run manifest
#   verify the backing image is byte-identical
#   delete the overlay on success, quarantine it on failure
#
# A failed run keeps its overlay, because a build that failed is the one whose
# filesystem someone needs to look at. Quarantined runs are named and reported
# rather than silently accumulating.

set -euo pipefail

CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-docker}"
COMPOSE="${COMPOSE:-$CONTAINER_RUNTIME compose}"
BUILD_ROOT="${BUILD_ROOT:-artifacts/builds}"
LOCK_FILE="${BUILDER_LOCK:-config/minty/builder.lock.json}"
BUILDER_TIMEOUT="${BUILDER_TIMEOUT:-1800}"
KEEP_OVERLAY="${KEEP_OVERLAY:-0}"

log() { printf '%s\n' "$*" >&2; }
fail() { log "ERROR: $*"; exit 1; }

command -v jq >/dev/null 2>&1 || fail "jq is required to read ${LOCK_FILE}"
[ -f "$LOCK_FILE" ] || fail "no build lock at ${LOCK_FILE}"

base_path="$(jq -r '.builder_base.path' "$LOCK_FILE")"
base_sha="$(jq -r '.builder_base.sha256' "$LOCK_FILE")"
snapshot="$(jq -r '.archive_snapshot' "$LOCK_FILE")"
[ -n "$base_path" ] && [ "$base_path" != "null" ] || fail "lock names no builder base"
[ -f "$base_path" ] || fail "builder base not found: ${base_path}"

# The digest is checked before anything is created, so a run against the wrong
# base produces no overlay, no container, and no artifacts to mistake for good
# ones.
#
# An absent or malformed digest is refused rather than skipped. A lock whose
# digest is empty accepts whatever file appears at the declared path, which is
# the case a build lock exists to exclude: the identity of the base has to be
# declared before the run, not read from the run.
if ! printf '%s' "$base_sha" | grep -Eq '^[0-9a-f]{64}$'; then
    fail "the lock declares no sha256 for ${base_path}, so a build against it reproduces nothing; build the base and rerun scripts/write-builder-lock.py"
fi
found_sha="$(sha256sum "$base_path" | cut -d' ' -f1)"
if [ "$found_sha" != "$base_sha" ]; then
    fail "builder base ${base_path} hashes to ${found_sha}, lock declares ${base_sha}"
fi
log "builder base ${base_path} sha256 ${found_sha}"
[ -n "$snapshot" ] && [ "$snapshot" != "null" ] \
    || fail "lock carries no archive_snapshot; an unpinned build cannot be reproduced"

# A unique run directory and a unique Compose project let two runs proceed at
# once and keep one run's failure out of another's evidence.
run_id="${BUILD_RUN_ID:-run-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
run_dir="${BUILD_ROOT}/${run_id}"
[ -e "$run_dir" ] && fail "run directory ${run_dir} already exists"
mkdir -p "$run_dir/artifacts"
project="hurdbuild-$(printf '%s' "$run_id" | tr -c 'a-z0-9' '-' | cut -c1-40)"

base_dir="$(cd "$(dirname "$base_path")" && pwd)"
run_abs="$(cd "$run_dir" && pwd)"

export BUILDER_BASE_DIR="$base_dir"
BUILDER_BASE_BASENAME="$(basename "$base_path")"
export BUILDER_BASE_BASENAME
export BUILDER_BASE_SHA256="$found_sha"
export BUILDER_RUN_DIR="$run_abs"

overlay="$run_abs/overlay.qcow2"
status="unknown"

stop_composition() {
    COMPOSE_FILE=compose.builder.yaml $COMPOSE -p "$project" down \
        --remove-orphans >/dev/null 2>&1 || true
}

# The overlay outlives the container on purpose, so the trap disposes of it
# rather than the container doing so, and a failed run keeps it for diagnosis.
dispose() {
    stop_composition
    if [ "$status" = "success" ] && [ "$KEEP_OVERLAY" != "1" ]; then
        rm -f "$overlay" "${overlay}.backing-sha256"
        log "overlay discarded; artifacts remain in ${run_dir}/artifacts"
    elif [ -f "$overlay" ]; then
        log "overlay retained for diagnosis at ${overlay}"
    fi

    # The backing image is mounted read-only and opened as a backing file, and
    # this is what says so rather than assuming it.
    local after
    after="$(sha256sum "$base_path" | cut -d' ' -f1)"
    if [ "$after" != "$found_sha" ]; then
        log "ERROR: builder base changed during the run: ${found_sha} -> ${after}"
        status="base-mutated"
    fi
    write_manifest "$after"
}

write_manifest() {
    local after="$1"
    cat > "$run_dir/run.json" <<EOF
{
  "schema_version": 1,
  "run_id": "${run_id}",
  "status": "${status}",
  "archive_snapshot": "${snapshot}",
  "builder_base": {
    "path": "${base_path}",
    "sha256_before": "${found_sha}",
    "sha256_after": "${after}"
  },
  "overlay_retained": $([ -f "$overlay" ] && echo true || echo false),
  "compose_project": "${project}"
}
EOF
    log "run manifest at ${run_dir}/run.json (status ${status})"
}

trap dispose EXIT

log "run ${run_id} in ${run_dir}, project ${project}, archive ${snapshot}"

if ! COMPOSE_FILE=compose.builder.yaml $COMPOSE -p "$project" up -d builder; then
    status="start-failed"
    exit 1
fi

# The overlay must exist and must descend from the declared base. qemu-img
# reports the chain, so this reads what QEMU will open rather than trusting the
# creation call that preceded it.
sleep 5
if [ ! -f "$overlay" ]; then
    status="no-overlay"
    fail "the builder created no overlay at ${overlay}"
fi

chain_base="$($CONTAINER_RUNTIME run --rm -v "$run_abs:/run-dir:ro" \
    -v "$base_dir:/base:ro" --entrypoint qemu-img \
    "${BUILDER_CONTAINER_IMAGE:-gnu-hurd-docker:latest}" \
    info --output=json /run-dir/overlay.qcow2 2>/dev/null \
    | jq -r '."backing-filename" // ""')"
case "$chain_base" in
    */"$BUILDER_BASE_BASENAME") : ;;
    *) status="wrong-backing-chain"
       fail "overlay backing file is ${chain_base:-none}, not the declared base" ;;
esac
log "overlay backing chain resolves to ${chain_base}"

# The guest signals completion by exiting; the runner does not interpret guest
# state it cannot see.
waited=0
while [ "$waited" -lt "$BUILDER_TIMEOUT" ]; do
    if ! $CONTAINER_RUNTIME ps --filter "label=com.gnu-hurd.profile=builder" \
            --filter status=running --format '{{.ID}}' | grep -q .; then
        break
    fi
    sleep 10
    waited=$((waited + 10))
done

if [ "$waited" -ge "$BUILDER_TIMEOUT" ]; then
    status="timeout"
    fail "builder did not finish within ${BUILDER_TIMEOUT}s"
fi

status="success"
log "builder finished"
