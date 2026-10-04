#!/bin/bash
# Own the lifecycle of one disposable install-test run: a second overlay over
# the same locked base that never held a build dependency, so a runtime
# dependency the build overlay concealed shows up here rather than nowhere.
#
# This is a distinct overlay and a distinct Compose project from the build run
# that produced the packages under test, with its own run directory and its
# own ephemeral SSH port, because the two guests must never be the same guest:
# a build overlay carries every build dependency the campaign installed, and
# testing inside it would answer a question about that overlay rather than
# about the package.
#
# Lifecycle:
#
#   create a unique run directory
#   verify the backing image against the lock (same base as the build run)
#   start a fresh builder composition, which creates a fresh overlay
#   record the identity of the container that started
#   wait for the guest to answer SSH
#   run the install test against the produced .debs
#   halt the guest explicitly
#   check the overlay filesystem offline
#   write the run manifest, binding the lock, the base, and the artifact
#     manifest under test
#   delete the overlay on success, quarantine it on failure

set -euo pipefail

CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-docker}"
COMPOSE="${COMPOSE:-$CONTAINER_RUNTIME compose}"
BUILD_ROOT="${BUILD_ROOT:-artifacts/builds}"
LOCK_FILE="${BUILDER_LOCK:-config/minty/builder.lock.json}"
BUILDER_TIMEOUT="${BUILDER_TIMEOUT:-1800}"
KEEP_OVERLAY="${KEEP_OVERLAY:-0}"

package_dir=""
artifact_manifest=""
probe_package=""
while [ $# -gt 0 ]; do
    case "$1" in
        --package) package_dir="$2"; shift 2 ;;
        --artifact-manifest) artifact_manifest="$2"; shift 2 ;;
        --probe-package) probe_package="$2"; shift 2 ;;
        *) printf 'install-test run: unknown argument %s\n' "$1" >&2; exit 2 ;;
    esac
done
[ -n "$package_dir" ] && [ -d "$package_dir" ] || {
    printf 'install-test run: --package naming an existing directory is required\n' >&2; exit 2; }
[ -n "$artifact_manifest" ] && [ -f "$artifact_manifest" ] || {
    printf 'install-test run: --artifact-manifest naming an existing file is required\n' >&2; exit 2; }

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

base_path="$(jq -r '.builder_base.path' "$LOCK_FILE")"
base_sha="$(jq -r '.builder_base.sha256' "$LOCK_FILE")"
[ -n "$base_path" ] && [ "$base_path" != "null" ] || fail "lock names no builder base"
[ -f "$base_path" ] || fail "builder base not found: ${base_path}"
if ! printf '%s' "$base_sha" | grep -Eq '^[0-9a-f]{64}$'; then
    fail "the lock declares no sha256 for ${base_path}"
fi
found_sha="$(sha256sum "$base_path" | cut -d' ' -f1)"
if [ "$found_sha" != "$base_sha" ]; then
    fail "builder base ${base_path} hashes to ${found_sha}, lock declares ${base_sha}"
fi
log "builder base ${base_path} sha256 ${found_sha}"

lock_sha="$(sha256sum "$LOCK_FILE" | cut -d' ' -f1)"
artifact_manifest_sha="$(sha256sum "$artifact_manifest" | cut -d' ' -f1)"

run_id="${BUILD_RUN_ID:-installtest-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
run_dir="${BUILD_ROOT}/${run_id}"
[ -e "$run_dir" ] && fail "run directory ${run_dir} already exists"
mkdir -p "$run_dir/artifacts"
project="hurdinstall-$(printf '%s' "$run_id" | tr -c 'a-z0-9' '-' | cut -c1-40)"

base_dir="$(cd "$(dirname "$base_path")" && pwd)"
run_abs="$(cd "$run_dir" && pwd)"

export BUILDER_BASE_DIR="$base_dir"
BUILDER_BASE_BASENAME="$(basename "$base_path")"
export BUILDER_BASE_BASENAME
export BUILDER_BASE_SHA256="$found_sha"
export BUILDER_RUN_DIR="$run_abs"

overlay="$run_abs/overlay.qcow2"
status="unknown"
qcow2_check="not run"
guest_filesystem_as_left="not run"
guest_filesystem_after_repair="not run"
backing_rebased="false"
container_id=""
container_image_id=""
container_repository_digest=""
container_exit_status="not read"
install_test_status="not run"

stop_composition() {
    COMPOSE_FILE=compose.builder.yaml $COMPOSE -p "$project" down \
        --remove-orphans >/dev/null 2>&1 || true
}

builder_running() {
    [ -n "$container_id" ] || return 1
    [ "$($CONTAINER_RUNTIME inspect -f '{{.State.Running}}' "$container_id" \
        2>/dev/null)" = "true" ]
}

record_container_identity() {
    container_image_id="$($CONTAINER_RUNTIME inspect -f '{{.Image}}' \
        "$container_id" 2>/dev/null || true)"
    if [ -n "$container_image_id" ]; then
        container_repository_digest="$($CONTAINER_RUNTIME image inspect \
            -f '{{if .RepoDigests}}{{index .RepoDigests 0}}{{end}}' \
            "$container_image_id" 2>/dev/null || true)"
    fi
    log "builder container ${container_id} from image ${container_image_id:-unread}"
}

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

    guestfish --ro -a "$overlay" run : e2fsck /dev/sda5 forceno:true \
        >"$as_left_log" 2>&1 || as_left_status=$?
    if [ "$as_left_status" -eq 0 ]; then
        guest_filesystem_as_left="consistent"
    else
        guest_filesystem_as_left="differences reported"
    fi

    if ! guestfish -a "$overlay" run : e2fsck /dev/sda5 correct:true \
            forceall:false >"$repair_log" 2>&1; then
        log "ERROR: the guest filesystem repair pass failed; see ${repair_log}"
        return 1
    fi
    guest_filesystem_after_repair="clean"
}

write_manifest() {
    local after="$1"
    cat > "$run_dir/run.json" <<EOF
{
  "schema_version": 1,
  "kind": "hurd-native-package-install-test-run",
  "run_id": "${run_id}",
  "status": "${status}",
  "builder_lock": {
    "path": "${LOCK_FILE}",
    "sha256": "${lock_sha}"
  },
  "builder_base": {
    "path": "${base_path}",
    "sha256_before": "${found_sha}",
    "sha256_after": "${after}"
  },
  "artifact_manifest_under_test": {
    "path": "${artifact_manifest}",
    "sha256": "${artifact_manifest_sha}"
  },
  "offline_checks": {
    "backing_rebased_to_host_path": ${backing_rebased},
    "qcow2": "${qcow2_check}",
    "qcow2_transcript": "qemu-img-check.json",
    "guest_filesystem_as_left": "${guest_filesystem_as_left}",
    "guest_filesystem_as_left_transcript": "offline-fsck-as-left.log",
    "guest_filesystem_after_repair": "${guest_filesystem_after_repair}",
    "guest_filesystem_after_repair_transcript": "offline-fsck-repair.log"
  },
  "overlay_retained": $([ -f "$overlay" ] && echo true || echo false),
  "compose_project": "${project}",
  "builder_container": {
    "requested_reference": "${BUILDER_CONTAINER_IMAGE:-gnu-hurd-docker:latest}",
    "container_id": "${container_id}",
    "image_id": "${container_image_id}",
    "repository_digest": "${container_repository_digest}",
    "exit_status": "${container_exit_status}",
    "ssh_port": ${BUILDER_SSH_PORT}
  },
  "source_commit": "${BUILDER_SOURCE_COMMIT}",
  "install_test": "${install_test_status}"
}
EOF
    log "install-test run manifest at ${run_dir}/run.json (status ${status})"
}

dispose() {
    local entry_status=$?

    COMPOSE_FILE=compose.builder.yaml $COMPOSE -p "$project" logs --no-color \
        >"$run_dir/container.log" 2>&1 || true
    read_container_exit_status

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

    if [ "$entry_status" -eq 0 ] && [ "$status" != "success" ]; then
        log "install-test run ${run_id} failed its postconditions: ${status}"
        exit 1
    fi
    exit "$entry_status"
}
trap dispose EXIT

log "install-test run ${run_id} in ${run_dir}, project ${project}"

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

export GUEST_SSH_HOST="${GUEST_SSH_HOST:-127.0.0.1}"
export GUEST_SSH_PORT="${GUEST_SSH_PORT:-$BUILDER_SSH_PORT}"
export GUEST_SSH_USER=root
export GUEST_SSH_KEY="${GUEST_SSH_KEY:-ssh-test-keys/hurd_test_key}"
export GUEST_KNOWN_HOSTS="${GUEST_KNOWN_HOSTS:-${run_dir}/known_hosts}"
# shellcheck source=scripts/lib/guest-ssh.sh
source "${script_root}/lib/guest-ssh.sh"

ready_timeout="${BUILDER_SSH_READY_TIMEOUT:-600}"
ssh_waited=0
while ! guest_ssh_alive; do
    if [ "$ssh_waited" -ge "$ready_timeout" ]; then
        status="guest-unreachable"
        fail "the guest never answered SSH within ${ready_timeout}s"
    fi
    sleep 10
    ssh_waited=$((ssh_waited + 10))
done
log "guest answered SSH after ${ssh_waited}s"

# The install test never held a build dependency, so a runtime dependency the
# build overlay concealed shows up as a refusal here rather than nowhere.
if scripts/install-test-hurd-packages.sh --package "$package_dir" \
        --run-dir "$run_dir" --probe-package "$probe_package"; then
    install_test_status="passed"
else
    install_test_status="$(jq -r '.status // "failed"' "$run_dir/install-test.json" 2>/dev/null || echo failed)"
    status="install-test-failed"
    guest_ssh_exec "$run_dir/artifacts/final-halt.stdout" "$run_dir/artifacts/final-halt.stderr" \
        "sync; halt" || true
    exit 1
fi

guest_ssh_exec "$run_dir/artifacts/final-halt.stdout" "$run_dir/artifacts/final-halt.stderr" \
    "sync; halt" || true

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

read_container_exit_status
if [ "$container_exit_status" != "0" ]; then
    status="container-exit-nonzero"
    fail "builder container ${container_id} exited ${container_exit_status}"
fi

if ! check_overlay_offline; then
    status="offline-check-failed"
    exit 1
fi

status="success"
log "install test finished"
