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
BUILDER_SSH_PORT="${BUILDER_SSH_PORT:-2223}"
export BUILDER_SSH_PORT

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
batch_plan="$run_dir/batch-plan.json"
batch_journal="$run_dir/batch-journal.json"
status="unknown"
qcow2_check="not run"
guest_filesystem_as_left="not run"
guest_filesystem_after_repair="not run"
backing_rebased="false"

# The runner is the only layer that has the actual qcow2 and can prove it is
# present and hashes to the lock. The planner then binds that proved base to the
# exported status and seeded resolver transaction before QEMU starts, so a run
# directory never contains an unbound package schedule.
python3 scripts/plan-builder-batches.py --lock "$LOCK_FILE" \
    --output "$batch_plan"
batch_plan_sha="$(jq -r '.plan_sha256' "$batch_plan")"
if ! printf '%s' "$batch_plan_sha" | grep -Eq '^[0-9a-f]{64}$'; then
    fail "batch planner wrote no valid plan sha256 to ${batch_plan}"
fi
log "builder batch plan ${batch_plan} sha256 ${batch_plan_sha}"
python3 scripts/write-builder-batch-journal.py --plan "$batch_plan" \
    --journal "$batch_journal" --initialize
log "builder batch journal ${batch_journal} records guest actions"

stop_composition() {
    COMPOSE_FILE=compose.builder.yaml $COMPOSE -p "$project" down \
        --remove-orphans >/dev/null 2>&1 || true
}

check_overlay_offline() {
    local qemu_check_log="$run_dir/qemu-img-check.json"
    local as_left_log="$run_dir/offline-fsck-as-left.log"
    local repair_log="$run_dir/offline-fsck-repair.log"
    local as_left_status=0

    command -v guestfish >/dev/null 2>&1 \
        || { log "ERROR: guestfish is required for the guest filesystem check"; return 1; }

    # The overlay's header records the backing path the container saw, which
    # exists in no host directory, so every host tool that follows the chain
    # fails to open it. `qemu-img rebase -u` rewrites that one header field to
    # the host copy of the same file and copies no data. The chain assertion
    # above has already read the recorded name, so the identity the run declared
    # is established before the field is rewritten, and the checker then needs
    # no privilege to recreate the container's filesystem layout.
    if ! qemu-img rebase -u -b "${base_dir}/${BUILDER_BASE_BASENAME}" \
            -F qcow2 "$overlay" >/dev/null 2>&1; then
        log "ERROR: cannot point the overlay at the host copy of its backing image"
        return 1
    fi
    backing_rebased="true"

    if ! qemu-img check -U --output=json "$overlay" >"$qemu_check_log" 2>&1; then
        log "ERROR: qcow2 check failed; see ${qemu_check_log}"
        return 1
    fi
    if [ "$(jq -r '."check-errors" // -1' "$qemu_check_log")" != "0" ]; then
        log "ERROR: qcow2 check reports errors; see ${qemu_check_log}"
        return 1
    fi
    qcow2_check="clean"

    # `forceno:true` answers every repair prompt negatively, so this pass reads
    # the filesystem exactly as the guest left it and changes nothing. It is an
    # observation rather than a gate: the Hurd's ext2fs leaves i_dtime unset on
    # unlink, so a read-only pass over any Hurd-written ext2 root reports
    # deleted inodes with zero dtime and the bitmap differences that follow from
    # them. Gating on it would refuse every run this project can produce.
    guestfish --ro -a "$overlay" run : e2fsck /dev/sda5 forceno:true \
        >"$as_left_log" 2>&1 || as_left_status=$?
    if [ "$as_left_status" -eq 0 ]; then
        guest_filesystem_as_left="consistent"
    else
        guest_filesystem_as_left="differences reported"
    fi

    # This pass is the gate. A full non-interactive repair is what the guest
    # image discipline prescribes after a guest stops, and the overlay is
    # disposable, so repairing it costs nothing and produces the filesystem the
    # artifacts are read from. A repair that cannot complete is the finding that
    # separates the unlink convention from actual damage.
    if ! guestfish -a "$overlay" run : e2fsck /dev/sda5 correct:true \
            forceall:false >"$repair_log" 2>&1; then
        log "ERROR: the guest filesystem repair pass failed; see ${repair_log}"
        return 1
    fi
    guest_filesystem_after_repair="clean"
}

# The overlay outlives the container on purpose, so the trap disposes of it
# rather than the container doing so, and a failed run keeps it for diagnosis.
dispose() {
    # The entrypoint can fail before it creates an overlay. Capture its own
    # words before Compose removes the stopped container, because an absent
    # overlay alone does not say whether the base, mount, or qemu-img failed.
    COMPOSE_FILE=compose.builder.yaml $COMPOSE -p "$project" logs --no-color \
        >"$run_dir/container.log" 2>&1 || true
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
  "batch_plan": {
    "path": "batch-plan.json",
    "sha256": "${batch_plan_sha}"
  },
  "batch_journal": "batch-journal.json",
  "offline_checks": {
    "backing_rebased_to_host_path": ${backing_rebased},
    "qcow2": "${qcow2_check}",
    "qcow2_transcript": "qemu-img-check.json",
    "guest_filesystem_as_left": "${guest_filesystem_as_left}",
    "guest_filesystem_as_left_transcript": "offline-fsck-as-left.log",
    "guest_filesystem_after_repair": "${guest_filesystem_after_repair}",
    "guest_filesystem_after_repair_transcript": "offline-fsck-repair.log"
  },
  "guest_console_capture": "not run; the builder publishes no serial surface and the entrypoint writes no console transcript, so a Mach console message is unobserved",
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
# The entrypoint validates its QEMU configuration before it creates the overlay.
# A fixed five-second delay races that work on a busy host and mislabels a live
# startup as an absent overlay. Wait for the artifact or a stopped container.
overlay_waited=0
while [ ! -f "$overlay" ] && [ "$overlay_waited" -lt 60 ]; do
    if ! $CONTAINER_RUNTIME ps --filter "label=com.gnu-hurd.profile=builder" \
            --filter status=running --format '{{.ID}}' | grep -q .; then
        break
    fi
    sleep 2
    overlay_waited=$((overlay_waited + 2))
done
if [ ! -f "$overlay" ]; then
    status="no-overlay"
    fail "the builder created no overlay at ${overlay} within ${overlay_waited}s"
fi

command -v qemu-img >/dev/null 2>&1 || fail "qemu-img is required to inspect the overlay chain"
chain_base="$(qemu-img info -U --output=json "$overlay" \
    | jq -r '."backing-filename" // ""')"
case "$chain_base" in
    */"$BUILDER_BASE_BASENAME") : ;;
    *) status="wrong-backing-chain"
       fail "overlay backing file is ${chain_base:-none}, not the declared base" ;;
esac
log "overlay backing chain resolves to ${chain_base}"

# A clean QEMU exit alone only says that the guest stopped. The executor records
# the guest APT work and issues the final halt after all planned rounds finish,
# so an empty or partial journal rejects a run that otherwise looks clean.
if ! scripts/execute-builder-batches.sh --plan "$batch_plan" --journal "$batch_journal" \
        --run-dir "$run_dir" --final-halt; then
    status="batch-execution-failed"
    exit 1
fi

planned_batches="$(jq '.batches | length' "$batch_plan")"
completed_batches="$(jq '[.records[] | select(.outcome == "completed")] | length' "$batch_journal")"
if [ "$completed_batches" -ne "$planned_batches" ]; then
    status="batch-journal-incomplete"
    fail "batch journal records ${completed_batches} completed batches, plan requires ${planned_batches}"
fi

# The executor requests the final clean halt. The runner waits for QEMU itself
# because only the VM process proves that the guest shutdown reached QEMU.
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

if ! check_overlay_offline; then
    status="offline-check-failed"
    exit 1
fi

status="success"
log "builder finished"
