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
#   record the identity of the container that started
#   wait for that container to finish
#   check the overlay filesystem offline
#   verify the backing image is byte-identical
#   write the run manifest
#   delete the overlay on success, quarantine it on failure
#   stop the composition
#
# Every wait and inspection names the container ID Compose reported for this
# project's builder service. A label the composition also carries identifies the
# class of builder containers rather than this one, so a concurrent or abandoned
# run answers the question this run asked.
#
# The postconditions are evaluated before disposal because the overlay is what
# any of them failing sends someone to look at, and a failure that flips the
# status also fails the process. A manifest reading `base-mutated` beside exit 0
# reports a successful build to every caller that reads the exit status.
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

# A unique Compose project keeps two runs' containers apart and does nothing
# about the host port each publishes, so a fixed default collides on the second
# concurrent run and the second run's SSH reaches the first run's guest. An
# unset port is allocated from the ephemeral range by binding it and reading
# back what the kernel assigned.
if [ -z "${BUILDER_SSH_PORT:-}" ]; then
    BUILDER_SSH_PORT="$(python3 -c 'import socket
probe = socket.socket()
probe.bind(("127.0.0.1", 0))
print(probe.getsockname()[1])
probe.close()')"
fi
export BUILDER_SSH_PORT

log() { printf '%s\n' "$*" >&2; }
fail() { log "ERROR: $*"; exit 1; }

command -v jq >/dev/null 2>&1 || fail "jq is required to read ${LOCK_FILE}"
[ -f "$LOCK_FILE" ] || fail "no build lock at ${LOCK_FILE}"

script_root="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/builder-image-preflight.sh
source "${script_root}/lib/builder-image-preflight.sh"

# The image identity is settled before an overlay exists. A run that discovers
# it started the wrong container has already created a disposable artifact whose
# owner exits with it, and the evidence it goes on to write cites a commit whose
# code never ran.
BUILDER_SOURCE_COMMIT="${BUILDER_SOURCE_COMMIT:-$(git rev-parse HEAD 2>/dev/null || true)}"
if [ "${BUILDER_SKIP_IMAGE_PREFLIGHT:-0}" = "1" ]; then
    log "image preflight skipped by request; the run cites no source commit"
    BUILDER_SOURCE_COMMIT=""
else
    [ -n "$BUILDER_SOURCE_COMMIT" ] || fail "no git commit to bind the run to"
    [ -n "${BUILDER_CONTAINER_IMAGE:-}" ] \
        || fail "BUILDER_CONTAINER_IMAGE must name the image built from ${BUILDER_SOURCE_COMMIT}; a mutable tag records no source"
    builder_image_matches_commit "$BUILDER_CONTAINER_IMAGE" "$BUILDER_SOURCE_COMMIT" \
        || fail "the builder image is not commit ${BUILDER_SOURCE_COMMIT}"
    log "builder image ${BUILDER_CONTAINER_IMAGE} is commit ${BUILDER_SOURCE_COMMIT}"
fi
export BUILDER_CONTAINER_IMAGE BUILDER_SOURCE_COMMIT

# A build request turns the run from a dependency campaign into a package build.
BUILD_REQUEST="${BUILD_REQUEST:-}"
if [ -n "$BUILD_REQUEST" ]; then
    [ -f "$BUILD_REQUEST" ] || fail "no build request at ${BUILD_REQUEST}"
fi

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
container_id=""
container_image_id=""
container_repository_digest=""
container_exit_status="not read"
qemu_version=""
entrypoint_sha256=""
mach_console="not run"
source_build="not run"
install_test="not run"

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

# The one container this run started. Compose reports it for this project's
# builder service, so every wait and inspection below names an identity rather
# than a class: the composition's `com.gnu-hurd.profile=builder` label is
# carried by every builder container on the host, and filtering on it lets a
# concurrent or abandoned run decide when this run's guest has stopped.
builder_running() {
    [ -n "$container_id" ] || return 1
    [ "$($CONTAINER_RUNTIME inspect -f '{{.State.Running}}' "$container_id" \
        2>/dev/null)" = "true" ]
}

# Read the immutable identity of what actually ran. `BUILDER_CONTAINER_IMAGE`
# defaults to a local tag, which names whatever that tag points at on the
# invoking host at the moment Compose resolved it, so the manifest records the
# image ID the container was created from. The QEMU binary and the entrypoint
# conduct the build, and both live in that image, so they are read from the
# running container rather than from the repository working tree.
record_container_identity() {
    container_image_id="$($CONTAINER_RUNTIME inspect -f '{{.Image}}' \
        "$container_id" 2>/dev/null || true)"
    if [ -n "$container_image_id" ]; then
        container_repository_digest="$($CONTAINER_RUNTIME image inspect \
            -f '{{if .RepoDigests}}{{index .RepoDigests 0}}{{end}}' \
            "$container_image_id" 2>/dev/null || true)"
    fi
    qemu_version="$($CONTAINER_RUNTIME exec "$container_id" \
        qemu-system-x86_64 --version 2>/dev/null | head -1 || true)"
    entrypoint_sha256="$($CONTAINER_RUNTIME exec "$container_id" \
        sha256sum /entrypoint.sh 2>/dev/null | cut -d' ' -f1 || true)"
    log "builder container ${container_id} from image ${container_image_id:-unread}"
}

# A container that exited before the runner asked has already recorded why. The
# code is read from the container that ran rather than inferred from whether a
# process is still listed.
read_container_exit_status() {
    [ -n "$container_id" ] || return 0
    local code
    code="$($CONTAINER_RUNTIME inspect -f '{{.State.ExitCode}}' "$container_id" \
        2>/dev/null || true)"
    if printf '%s' "$code" | grep -Eq '^[0-9]+$'; then
        container_exit_status="$code"
    fi
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
    local entry_status=$?

    # The entrypoint can fail before it creates an overlay. Capture its own
    # words before Compose removes the stopped container, because an absent
    # overlay alone does not say whether the base, mount, or qemu-img failed.
    COMPOSE_FILE=compose.builder.yaml $COMPOSE -p "$project" logs --no-color \
        >"$run_dir/container.log" 2>&1 || true
    read_container_exit_status

    # Every postcondition is evaluated before anything is deleted. The backing
    # image is mounted read-only and opened as a backing file, and this is what
    # says so rather than assuming it; a base that moved is also the case whose
    # overlay someone needs, so discovering it after the discard would destroy
    # the evidence the finding calls for.
    local after
    after="$(sha256sum "$base_path" | cut -d' ' -f1)"
    if [ "$after" != "$found_sha" ]; then
        log "ERROR: builder base changed during the run: ${found_sha} -> ${after}"
        status="base-mutated"
    fi
    if [ "$status" = "success" ] && [ "$container_exit_status" != "0" ]; then
        log "ERROR: builder container exited ${container_exit_status}"
        status="container-exit-nonzero"
    fi

    if [ "$status" = "success" ] && [ "$KEEP_OVERLAY" != "1" ]; then
        rm -f "$overlay" "${overlay}.backing-sha256"
        log "overlay discarded; artifacts remain in ${run_dir}/artifacts"
    elif [ -f "$overlay" ]; then
        log "overlay retained for diagnosis at ${overlay}"
    fi

    write_manifest "$after"
    stop_composition

    # A postcondition that fails after the script body succeeded leaves the
    # process status saying the build worked, and a caller reads the status
    # rather than the manifest. The trap therefore carries its own verdict out.
    if [ "$entry_status" -eq 0 ] && [ "$status" != "success" ]; then
        log "run ${run_id} failed its postconditions: ${status}"
        exit 1
    fi
    exit "$entry_status"
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
  "guest_console": {
    "transcript": "serial.log",
    "captured": $([ -s "$run_dir/serial.log" ] && echo true || echo false),
    "carries_kernel_output": $(grep -qEi 'gnumach|mach operating system|mach [0-9]+\.[0-9]' "$run_dir/serial.log" 2>/dev/null && echo true || echo false)
  },
  "overlay_retained": $([ -f "$overlay" ] && echo true || echo false),
  "compose_project": "${project}",
  "builder_container": {
    "requested_reference": "${BUILDER_CONTAINER_IMAGE:-gnu-hurd-docker:latest}",
    "container_id": "${container_id}",
    "image_id": "${container_image_id}",
    "repository_digest": "${container_repository_digest}",
    "exit_status": "${container_exit_status}",
    "qemu_version": "${qemu_version}",
    "entrypoint_sha256": "${entrypoint_sha256}",
    "ssh_port": ${BUILDER_SSH_PORT}
  },
  "source_commit": "${BUILDER_SOURCE_COMMIT}",
  "package_build": {
    "requested": $([ -n "$BUILD_REQUEST" ] && echo true || echo false),
    "mach_console": "${mach_console}",
    "source_build": "${source_build}",
    "install_test": "${install_test}"
  }
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

container_id="$(COMPOSE_FILE=compose.builder.yaml $COMPOSE -p "$project" \
    ps -q builder 2>/dev/null | head -1)"
if [ -z "$container_id" ]; then
    status="no-container"
    fail "Compose reported no builder container for project ${project}"
fi
record_container_identity

# The overlay must exist and must descend from the declared base. qemu-img
# reports the chain, so this reads what QEMU will open rather than trusting the
# creation call that preceded it.
# The entrypoint validates its QEMU configuration before it creates the overlay.
# A fixed five-second delay races that work on a busy host and mislabels a live
# startup as an absent overlay. Wait for the artifact or a stopped container.
overlay_waited=0
while [ ! -f "$overlay" ] && [ "$overlay_waited" -lt 60 ]; do
    builder_running || break
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
# so an empty or partial journal rejects a run that otherwise looks clean. A
# build request keeps the guest up past the dependency campaign for the source
# build stage below, so only a dependency-only run takes the final halt here.
executor_args=(--plan "$batch_plan" --journal "$batch_journal" --run-dir "$run_dir")
[ -n "$BUILD_REQUEST" ] || executor_args+=(--final-halt)
if ! scripts/execute-builder-batches.sh "${executor_args[@]}"; then
    status="batch-execution-failed"
    exit 1
fi

planned_batches="$(jq '.batches | length' "$batch_plan")"
completed_batches="$(jq '[.records[] | select(.outcome == "completed")] | length' "$batch_journal")"
if [ "$completed_batches" -ne "$planned_batches" ]; then
    status="batch-journal-incomplete"
    fail "batch journal records ${completed_batches} completed batches, plan requires ${planned_batches}"
fi

# A build request turns the campaign guest into a package-build guest: the
# serial console is proved before the build so its transcript covers the build,
# then the unmodified source build runs as the unprivileged account, then the
# guest halts explicitly because the executor left it running for this stage.
if [ -n "$BUILD_REQUEST" ]; then
    require_console="$(jq -r '.require_mach_console // false' "$BUILD_REQUEST")"
    console_args=(--run-dir "$run_dir")
    [ "$require_console" = "true" ] && console_args+=(--require)
    if scripts/enable-guest-mach-console.sh "${console_args[@]}"; then
        mach_console="ran"
    else
        mach_console="failed"
        status="mach-console-failed"
        exit 1
    fi

    if scripts/build-hurd-source-package.sh --request "$BUILD_REQUEST" --run-dir "$run_dir"; then
        source_build="completed"
    else
        source_build="$(jq -r '.outcome // "failed"' "$run_dir/build-run.json" 2>/dev/null || echo failed)"
        status="source-build-failed"
        exit 1
    fi

    export GUEST_SSH_HOST="${GUEST_SSH_HOST:-127.0.0.1}"
    export GUEST_SSH_PORT="${GUEST_SSH_PORT:-$BUILDER_SSH_PORT}"
    export GUEST_SSH_USER=root
    export GUEST_SSH_KEY="${GUEST_SSH_KEY:-ssh-test-keys/hurd_test_key}"
    export GUEST_KNOWN_HOSTS="${GUEST_KNOWN_HOSTS:-${run_dir}/known_hosts}"
    # shellcheck source=scripts/lib/guest-ssh.sh
    source "${script_root}/lib/guest-ssh.sh"
    guest_ssh_exec "$run_dir/artifacts/final-halt.stdout" "$run_dir/artifacts/final-halt.stderr" \
        "sync; halt" || true
fi

# The executor requests the final clean halt. The runner waits for QEMU itself
# because only the VM process proves that the guest shutdown reached QEMU.
waited=0
while [ "$waited" -lt "$BUILDER_TIMEOUT" ]; do
    builder_running || break
    sleep 10
    waited=$((waited + 10))
done

if [ "$waited" -ge "$BUILDER_TIMEOUT" ]; then
    status="timeout"
    fail "builder did not finish within ${BUILDER_TIMEOUT}s"
fi

# QEMU exiting says the VM process ended and not how it ended. The container's
# recorded code carries that, and a nonzero one rejects a run whose guest work
# otherwise journaled clean.
read_container_exit_status
if [ "$container_exit_status" != "0" ]; then
    status="container-exit-nonzero"
    fail "builder container ${container_id} exited ${container_exit_status}"
fi

if ! check_overlay_offline; then
    status="offline-check-failed"
    exit 1
fi

if [ -n "$BUILD_REQUEST" ]; then
    manifest_args=(--package "$run_dir/artifacts/package" --request "$BUILD_REQUEST" \
        --output "$run_dir/artifact-manifest.json" --run "$run_dir/build-run.json")
    if scripts/write-package-build-manifest.py "${manifest_args[@]}"; then
        install_test="pending"
    else
        status="manifest-write-failed"
        exit 1
    fi
    build_outcome="$(jq -r '.outcome // "failed"' "$run_dir/build-run.json" 2>/dev/null || echo failed)"
    if [ "$build_outcome" != "completed" ]; then
        status="source-build-failed"
        exit 1
    fi

    # The install test runs in its own overlay, its own Compose project, and
    # its own SSH port, because testing inside the overlay that produced the
    # packages would answer a question about that overlay's build-dependency
    # closure rather than about the package's own declared dependencies. Its
    # probe package is the first required binary; a request naming none is a
    # request this stage cannot exercise, and it is skipped and named rather
    # than silently reported as passing.
    probe_package="$(jq -r '.required_binary_packages[0] // empty' "$BUILD_REQUEST")"
    if [ -n "$probe_package" ]; then
        if env -u BUILDER_SSH_PORT \
                BUILD_ROOT="$(dirname "$run_dir")" \
                BUILD_RUN_ID="$(basename "$run_dir")-installtest" \
                scripts/run-hurd-install-test.sh \
                --package "$run_dir/artifacts/package" \
                --artifact-manifest "$run_dir/artifact-manifest.json" \
                --probe-package "$probe_package"; then
            install_test="passed"
        else
            install_test="failed"
            status="install-test-failed"
            exit 1
        fi
    else
        install_test="skipped-no-probe-package"
    fi
fi

status="success"
log "builder finished"
