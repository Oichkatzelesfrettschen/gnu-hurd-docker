#!/bin/bash
# Exercise the disposable-overlay mechanism against a synthetic backing image.
#
# The archive fixture suite covers the resolver and says nothing about the
# entrypoint, so a green shell gate proves the overlay code parses rather than
# that it behaves. These cases drive the real entrypoint in a real container and
# read the filesystem afterwards.
#
# A tiny qcow2 stands in for the guest. QEMU will fail to boot it, which is the
# point: every assertion here is about what exists on disk before and after, and
# a bootable guest would only make the run slower.

set -uo pipefail

RUNTIME="${CONTAINER_RUNTIME:-docker}"
IMAGE="${OVERLAY_TEST_IMAGE:-gnu-hurd-docker:overlay-lifecycle}"
WORK="$(mktemp -d)"
PASS=0
FAIL=0

# QEMU runs as root inside the container, so the overlay it wrote is root-owned
# on the host and an ordinary rm cannot remove it. The same container runtime
# that created it removes it.
cleanup() {
    $RUNTIME run --rm -v "$WORK:/w" --entrypoint sh "$IMAGE" \
        -c 'rm -rf /w/base /w/run' >/dev/null 2>&1 || true
    rm -rf "$WORK"
}
trap cleanup EXIT

check() {
    local name="$1" condition="$2" detail="${3:-}"
    if [ "$condition" = "0" ]; then
        PASS=$((PASS + 1))
        printf 'ok    %s\n' "$name"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL  %s: %s\n' "$name" "$detail"
    fi
}

if ! $RUNTIME image inspect "$IMAGE" >/dev/null 2>&1; then
    printf 'not run: %s is absent, so the overlay mechanism was never exercised\n' \
        "$IMAGE" >&2
    exit 2
fi

mkdir -p "$WORK/base" "$WORK/run"
$RUNTIME run --rm -v "$WORK/base:/w" --entrypoint qemu-img "$IMAGE" \
    create -f qcow2 /w/base.qcow2 64M >/dev/null 2>&1
BASE_SHA="$(sha256sum "$WORK/base/base.qcow2" | cut -d' ' -f1)"

boot() {
    # Each case gets its own run directory, the way the host runner gives each
    # build one, so a leftover from one case cannot decide another.
    #
    # A run that reaches QEMU does not end on its own, because the synthetic
    # disk is unbootable and QEMU waits rather than exiting. The container is
    # therefore started detached and bounded: a run still alive at the deadline
    # got past every refusal, which is what the accepting cases assert, and a
    # run that exited reports the entrypoint's own status.
    local name="$1"; shift
    $RUNTIME run -d --name "overlay-lc-$name" \
        -v "$WORK/base:/opt/hurd-image/base:ro" \
        -v "$WORK/run:/opt/hurd-run:rw" \
        -e QEMU_BACKING_DRIVE=/opt/hurd-image/base/base.qcow2 \
        -e QEMU_SMP=1 -e QEMU_RAM=512 \
        "$@" "$IMAGE" >/dev/null 2>&1
    local waited=0 state="running"
    while [ "$waited" -lt 20 ]; do
        state="$($RUNTIME inspect -f '{{.State.Status}}' "overlay-lc-$name" 2>/dev/null)"
        [ "$state" != "running" ] && break
        sleep 2
        waited=$((waited + 2))
    done
    $RUNTIME logs "overlay-lc-$name" >"$WORK/$name.log" 2>&1
    local code=0
    if [ "$state" != "running" ]; then
        code="$($RUNTIME inspect -f '{{.State.ExitCode}}' "overlay-lc-$name" 2>/dev/null || echo 1)"
    fi
    $RUNTIME rm -f "overlay-lc-$name" >/dev/null 2>&1
    printf '%s' "$code"
}

# A correct digest creates a fresh overlay whose chain names the declared base.
rc="$(boot create -e QEMU_DRIVE=/opt/hurd-run/a/overlay.qcow2 \
        -e QEMU_BACKING_SHA256="$BASE_SHA")"
[ -f "$WORK/run/a/overlay.qcow2" ] && found=0 || found=1
check "a correct backing digest creates a fresh overlay" "$found" \
    "rc=$rc $(tail -2 "$WORK/create.log" 2>/dev/null | tr '\n' ' ')"
grep -q "backing chain resolves to /opt/hurd-image/base/base.qcow2" \
    "$WORK/create.log" 2>/dev/null && chain=0 || chain=1
check "the overlay backing chain names the declared base" "$chain" \
    "$(grep -i backing "$WORK/create.log" 2>/dev/null | tail -1)"

# A declared digest that disagrees is refused, and nothing is created.
rc="$(boot wrongsha -e QEMU_DRIVE=/opt/hurd-run/b/overlay.qcow2 \
        -e QEMU_BACKING_SHA256=0000000000000000000000000000000000000000000000000000000000000000)"
[ "$rc" != "0" ] && refused=0 || refused=1
check "a backing digest that disagrees is refused" "$refused" "rc=$rc"
[ -e "$WORK/run/b" ] && created=1 || created=0
check "the refused run creates no overlay" "$created" \
    "run/b exists: $(ls "$WORK/run/b" 2>/dev/null | tr '\n' ' ')"

# An existing overlay is refused rather than reused, because the previous run's
# writes would carry forward into a build that reports itself clean.
rc="$(boot reuse -e QEMU_DRIVE=/opt/hurd-run/a/overlay.qcow2 \
        -e QEMU_BACKING_SHA256="$BASE_SHA")"
[ "$rc" != "0" ] && refused=0 || refused=1
check "an existing overlay is refused rather than reused" "$refused" "rc=$rc"

# A rejected configuration must not leave an overlay for the next start to meet.
rc="$(boot badbus -e QEMU_DRIVE=/opt/hurd-run/c/overlay.qcow2 \
        -e QEMU_BACKING_SHA256="$BASE_SHA" -e QEMU_DISK_BUS=floppy)"
[ "$rc" != "0" ] && refused=0 || refused=1
check "an unsupported disk bus is refused" "$refused" "rc=$rc"
[ -e "$WORK/run/c/overlay.qcow2" ] && created=1 || created=0
check "a configuration rejected before the run leaves no overlay" "$created" \
    "run/c: $(ls "$WORK/run/c" 2>/dev/null | tr '\n' ' ')"

# The whole claim: the backing image is never written.
AFTER_SHA="$(sha256sum "$WORK/base/base.qcow2" | cut -d' ' -f1)"
[ "$BASE_SHA" = "$AFTER_SHA" ] && same=0 || same=1
check "the backing image is byte-identical after every case" "$same" \
    "$BASE_SHA -> $AFTER_SHA"

printf '\n%d checks passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
