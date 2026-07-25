#!/usr/bin/env bash
# Capture the runtime as a machine-readable evidence document.
#
# The accelerator QEMU selects is not predictable from the declared configuration:
# detect_acceleration() in entrypoint.sh reports kvm whenever /dev/kvm is usable,
# and the AUTO_DISABLE_KVM_FOR_IDE branch then demotes that to tcg for the pc
# machine on the ide bus unless FORCE_KVM=1.  So the QEMU argv and the monitor
# carry the outcome, and the compose variables carry only the request.  This
# script records both and labels which is which.
#
# Every field carries an evidence class:
#   observed      read from the live QEMU process, its monitor, or the guest
#   derived       computed from an observed value
#   declared      read from repository configuration, which states intent
#   not-captured  unavailable, with the reason recorded rather than omitted
#
# Raw command output lands beside the JSON so a later reader re-parses the
# capture instead of trusting this script's parse.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SCHEMA_VERSION=1
CONTAINER=""
IMAGE_DIGEST=0
REDACT=0
OUTPUT_ROOT="${RUNTIME_EVIDENCE_ROOT:-$REPO_ROOT/evidence/runtime}"
SSH_KEY="${RUNTIME_EVIDENCE_SSH_KEY:-$REPO_ROOT/ssh-test-keys/hurd_test_key}"
SSH_PORT="${RUNTIME_EVIDENCE_SSH_PORT:-2222}"
SSH_USER="${RUNTIME_EVIDENCE_SSH_USER:-root}"

usage() {
    cat <<'USAGE'
Usage: capture-runtime-evidence.sh [options]

  --container NAME   Inspect this container rather than autodetecting one.
  --image-digest     Hash the guest image.  A 16 GiB qcow2 takes minutes, so
                     the digest is opt-in and is otherwise recorded as
                     not-captured with that reason.
  --output-dir DIR   Write the capture directory under DIR.
  --redact           Replace the repository root, the home directory, and the
                     host name with placeholders, so the capture is publishable
                     and satisfies the no-absolute-paths commit rule.
  -h, --help         Show this message.

The capture directory holds capture.json and a raw/ subdirectory.
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --container) CONTAINER="${2:-}"; shift 2 ;;
        --image-digest) IMAGE_DIGEST=1; shift ;;
        --output-dir) OUTPUT_ROOT="${2:-}"; shift 2 ;;
        --redact) REDACT=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "${0##*/}: unknown option $1" >&2; usage >&2; exit 2 ;;
    esac
done

command -v python3 >/dev/null 2>&1 || {
    echo "${0##*/}: python3 assembles the JSON document and is required" >&2
    exit 1
}

commit="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
short_commit="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
captured_at="$(date -u +%Y%m%dT%H%M%SZ)"
capture_dir="$OUTPUT_ROOT/${short_commit}-${captured_at}"
raw="$capture_dir/raw"
mkdir -p "$raw"

# Record a raw capture and echo its path, or echo nothing when the probe found
# no data.  A caller distinguishes the two by testing the returned string.
save_raw() {
    local name="$1"
    local path="$raw/$name"
    if [ -s "$path" ]; then
        printf 'raw/%s' "$name"
    fi
}

# ---- repository ----------------------------------------------------------
git status --porcelain > "$raw/git-status.txt" 2>/dev/null || true
dirty=false
[ -s "$raw/git-status.txt" ] && dirty=true
./scripts/list-maintained-shell.sh > "$raw/maintained-shell.txt" 2>/dev/null || true
shell_surface="$(grep -c '' < "$raw/maintained-shell.txt" 2>/dev/null || echo 0)"

# ---- host ----------------------------------------------------------------
uname -a > "$raw/host-uname.txt" 2>/dev/null || true
host_uname="$(head -1 "$raw/host-uname.txt" 2>/dev/null || true)"
host_cpu="$(grep -m1 '^model name' /proc/cpuinfo 2>/dev/null | sed 's/^model name[[:space:]]*:[[:space:]]*//' || true)"
host_cpus="$(nproc 2>/dev/null || echo 0)"
kvm_present=false
[ -e /dev/kvm ] && kvm_present=true
qemu_version=""
if command -v qemu-system-x86_64 >/dev/null 2>&1; then
    qemu-system-x86_64 --version > "$raw/host-qemu-version.txt" 2>&1 || true
    qemu_version="$(head -1 "$raw/host-qemu-version.txt" 2>/dev/null || true)"
fi
runtime_bin="${CONTAINER_RUNTIME:-docker}"
runtime_version=""
if command -v "$runtime_bin" >/dev/null 2>&1; then
    "$runtime_bin" version --format '{{.Server.Version}}' > "$raw/host-runtime-version.txt" 2>/dev/null || true
    runtime_version="$(head -1 "$raw/host-runtime-version.txt" 2>/dev/null || true)"
fi

# ---- declared configuration ---------------------------------------------
# docker compose config resolves the overlay stack, so the values below are the
# ones the stack actually presents rather than the ones any single file names.
compose_files="${COMPOSE_FILE:-compose.yaml}"
COMPOSE_FILE="$compose_files" "$runtime_bin" compose config \
    > "$raw/compose-config.yaml" 2>"$raw/compose-config.err" || true

declared_value() {
    local key="$1"
    grep -m1 -E "^[[:space:]]*${key}:" "$raw/compose-config.yaml" 2>/dev/null \
        | sed 's/^[^:]*:[[:space:]]*//; s/^"//; s/"$//' || true
}

# ---- observed container and QEMU ----------------------------------------
if [ -z "$CONTAINER" ] && command -v "$runtime_bin" >/dev/null 2>&1; then
    CONTAINER="$("$runtime_bin" ps --filter status=running --format '{{.Names}}' 2>/dev/null \
        | grep -m1 -E 'hurd' || true)"
fi

container_state="not-captured"
container_reason="no running container matched"
if [ -n "$CONTAINER" ] && "$runtime_bin" inspect "$CONTAINER" >/dev/null 2>&1; then
    container_state="$("$runtime_bin" inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo unknown)"
    container_reason=""
    "$runtime_bin" exec "$CONTAINER" sh -c 'ps -eo args' > "$raw/container-ps.txt" 2>/dev/null || true
    grep -m1 'qemu-system' "$raw/container-ps.txt" > "$raw/qemu-argv.txt" 2>/dev/null || true

    # The monitor command stream deliberately omits "quit": in the QEMU monitor
    # that terminates QEMU rather than closing the session, and the container's
    # reboot-loop mode then restarts the guest, which reads as a guest reboot.
    "$runtime_bin" exec "$CONTAINER" sh -c \
        "printf 'info status\ninfo kvm\ninfo cpus\n' | timeout 10 nc 127.0.0.1 9999" \
        > "$raw/monitor-info.txt" 2>/dev/null || true
fi

accel_observed=""
machine_observed=""
smp_observed=""
if [ -s "$raw/qemu-argv.txt" ]; then
    accel_observed="$(tr ' ' '\n' < "$raw/qemu-argv.txt" | grep -A1 -x -- '-accel' | tail -1 || true)"
    machine_observed="$(tr ' ' '\n' < "$raw/qemu-argv.txt" | grep -A1 -x -- '-machine' | tail -1 || true)"
    smp_observed="$(tr ' ' '\n' < "$raw/qemu-argv.txt" | grep -A1 -x -- '-smp' | tail -1 || true)"
fi
kvm_enabled=""
if [ -s "$raw/monitor-info.txt" ]; then
    if grep -q 'kvm support: enabled' "$raw/monitor-info.txt" 2>/dev/null; then
        kvm_enabled=true
    elif grep -q 'kvm support:' "$raw/monitor-info.txt" 2>/dev/null; then
        kvm_enabled=false
    fi
fi
# A count reads as observed, so it is only set when the monitor answered.  An
# unqueried monitor yielding 0 would assert that QEMU presents no vCPU.
vcpu_threads=""
if [ -s "$raw/monitor-info.txt" ]; then
    vcpu_threads="$(grep -c 'CPU #' "$raw/monitor-info.txt" 2>/dev/null || echo 0)"
fi

# ---- observed guest ------------------------------------------------------
guest_reason="guest probe not attempted"
guest_uname=""
guest_nproc=""
guest_packages=""
guest_dpkg_sha=""
if [ -r "$SSH_KEY" ] && [ "$container_state" = "running" ]; then
    guest_reason="ssh probe failed; the OOBE password-change gate refuses non-interactive sessions until it is lifted"
    if ssh -i "$SSH_KEY" -p "$SSH_PORT" \
            -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=15 -o BatchMode=yes "${SSH_USER}@127.0.0.1" \
            'uname -a; nproc; dpkg-query -f "${Status}\n" -W 2>/dev/null | grep -c "install ok installed"; sha256sum /var/lib/dpkg/status | cut -d" " -f1' \
            > "$raw/guest-probe.txt" 2>"$raw/guest-probe.err"; then
        guest_reason=""
        guest_uname="$(sed -n '1p' "$raw/guest-probe.txt")"
        guest_nproc="$(sed -n '2p' "$raw/guest-probe.txt")"
        guest_packages="$(sed -n '3p' "$raw/guest-probe.txt")"
        guest_dpkg_sha="$(sed -n '4p' "$raw/guest-probe.txt")"
    fi
elif [ ! -r "$SSH_KEY" ]; then
    guest_reason="no readable ssh key at $SSH_KEY"
elif [ "$container_state" != "running" ]; then
    guest_reason="container is not running"
fi

# ---- image ---------------------------------------------------------------
image_path="$(declared_value 'QEMU_DRIVE')"
host_image=""
case "$image_path" in
    /opt/hurd-image/*) host_image="$REPO_ROOT/images/${image_path##*/}" ;;
    ?*) host_image="$image_path" ;;
esac
image_virtual_size=""
image_snapshots=""
image_digest_value=""
image_digest_reason="hashing a multi-gigabyte qcow2 is expensive; rerun with --image-digest"
if [ -n "$host_image" ] && [ -r "$host_image" ] && command -v qemu-img >/dev/null 2>&1; then
    qemu-img info "$host_image" > "$raw/image-info.txt" 2>/dev/null || true
    qemu-img snapshot -l "$host_image" > "$raw/image-snapshots.txt" 2>/dev/null || true
    image_virtual_size="$(grep -m1 'virtual size' "$raw/image-info.txt" 2>/dev/null || true)"
    image_snapshots="$(awk 'NR>2 && NF {print $2}' "$raw/image-snapshots.txt" 2>/dev/null | paste -sd, - || true)"
    if [ "$IMAGE_DIGEST" = 1 ]; then
        image_digest_value="$(sha256sum "$host_image" | cut -d' ' -f1)"
        image_digest_reason=""
    fi
else
    image_digest_reason="no readable image at ${host_image:-<unresolved>}"
fi

# ---- assemble ------------------------------------------------------------
# python3 builds the document so field values are escaped by a JSON encoder
# rather than by shell quoting.
SCHEMA_VERSION="$SCHEMA_VERSION" CAPTURED_AT="$captured_at" COMMIT="$commit" \
DIRTY="$dirty" SHELL_SURFACE="$shell_surface" HOST_UNAME="$host_uname" \
HOST_CPU="$host_cpu" \
HOST_CPUS="$host_cpus" KVM_PRESENT="$kvm_present" QEMU_VERSION="$qemu_version" \
RUNTIME_BIN="$runtime_bin" RUNTIME_VERSION="$runtime_version" \
COMPOSE_FILES="$compose_files" CONTAINER="$CONTAINER" \
CONTAINER_STATE="$container_state" CONTAINER_REASON="$container_reason" \
ACCEL_OBSERVED="$accel_observed" MACHINE_OBSERVED="$machine_observed" \
SMP_OBSERVED="$smp_observed" KVM_ENABLED="$kvm_enabled" \
VCPU_THREADS="$vcpu_threads" GUEST_REASON="$guest_reason" \
GUEST_UNAME="$guest_uname" GUEST_NPROC="$guest_nproc" \
GUEST_PACKAGES="$guest_packages" GUEST_DPKG_SHA="$guest_dpkg_sha" \
IMAGE_PATH="$image_path" HOST_IMAGE="$host_image" \
IMAGE_VIRTUAL_SIZE="$image_virtual_size" IMAGE_SNAPSHOTS="$image_snapshots" \
IMAGE_DIGEST_VALUE="$image_digest_value" IMAGE_DIGEST_REASON="$image_digest_reason" \
DECL_MACHINE="$(declared_value 'QEMU_MACHINE')" \
DECL_DISK_BUS="$(declared_value 'QEMU_DISK_BUS')" \
DECL_SMP="$(declared_value 'QEMU_SMP')" \
DECL_FORCE_KVM="$(declared_value 'FORCE_KVM')" \
DECL_AUTO_DISABLE="$(declared_value 'AUTO_DISABLE_KVM_FOR_IDE')" \
RAW_DIR="$raw" \
python3 "$REPO_ROOT/scripts/emit-runtime-evidence.py" > "$capture_dir/capture.json"

# A committed capture carries no absolute path and no host name, so redaction
# rewrites the document and every raw file in place.  It runs after assembly so
# the probes read the real system and only the record is rewritten.
if [ "$REDACT" = 1 ]; then
    host_name="$(uname -n)"
    find "$capture_dir" -type f -print0 | while IFS= read -r -d '' target; do
        sed -i \
            -e "s|${REPO_ROOT}|<repo>|g" \
            -e "s|${HOME}|<home>|g" \
            -e "s|${host_name}|<host>|g" \
            "$target"
    done
fi

echo "$capture_dir/capture.json"
