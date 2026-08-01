#!/bin/bash
# Drive the build runner's lifecycle against stubbed container and image tools.
#
# scripts/run-hurd-build.sh owns disposal, the postconditions, and the process
# status a caller reads, and none of that is reachable from a shell gate: the
# real path needs a container, a multi-gigabyte base, and a guest that boots for
# minutes. The container runtime, qemu-img, and guestfish are therefore stubs
# whose answers each case chooses, which makes the questions this file asks --
# what is deleted, in what order, and what status the process carries out --
# answerable in seconds.
#
# The stubs stand in for tools whose behavior is not under test. The overlay,
# the run directory, the manifest, and the exit status are real files and a real
# process status, and every assertion reads one of those.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/build-run-postconditions-XXXXXX")"
failures=0

cleanup() { rm -rf "$WORKSPACE"; }
trap cleanup EXIT

check() {
    local description="$1" observed="$2" expected="$3"
    if [ "$observed" = "$expected" ]; then
        printf 'ok    %s\n' "$description"
    else
        failures=$((failures + 1))
        printf 'FAIL  %s (observed %s, expected %s)\n' \
            "$description" "$observed" "$expected"
    fi
}

# One tree per case, so a case that leaves a file behind cannot answer for the
# next one.
make_tree() {
    local tree="$1"
    mkdir -p "$tree/scripts/lib" "$tree/config/minty" "$tree/images" "$tree/bin"
    cp "$ROOT/scripts/run-hurd-build.sh" "$tree/scripts/"
    # The runner sources this unconditionally to settle image identity before it
    # decides whether the preflight itself runs, so the fixture tree needs it
    # even when BUILDER_SKIP_IMAGE_PREFLIGHT skips the check the file performs.
    cp "$ROOT/scripts/lib/builder-image-preflight.sh" "$tree/scripts/lib/"
    cp "$ROOT/compose.builder.yaml" "$tree/"
    printf 'a synthetic backing image\n' > "$tree/images/fake-base.qcow2"
    local base_sha
    base_sha="$(sha256sum "$tree/images/fake-base.qcow2" | cut -d' ' -f1)"
    cat > "$tree/config/minty/builder.lock.json" <<EOF
{
  "archive_snapshot": "20260726T003219Z",
  "builder_base": {
    "path": "images/fake-base.qcow2",
    "sha256": "${base_sha}"
  }
}
EOF

    # The planner, the journal writer, and the executor are exercised by their
    # own fixtures. Here they stand in as the smallest documents the runner
    # accepts, so a failure in this file is a failure of the lifecycle.
    cat > "$tree/scripts/plan-builder-batches.py" <<'EOF'
import json, sys
out = sys.argv[sys.argv.index("--output") + 1]
json.dump({"plan_sha256": "b" * 64,
           "batches": [{"batch_id": "batch-01", "members": ["fixture"]}]},
          open(out, "w"))
EOF
    cat > "$tree/scripts/write-builder-batch-journal.py" <<'EOF'
import json, sys
out = sys.argv[sys.argv.index("--journal") + 1]
json.dump({"plan_sha256": "b" * 64, "records": []}, open(out, "w"))
EOF
    cat > "$tree/scripts/execute-builder-batches.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
journal=""
while [ $# -gt 0 ]; do
    case "$1" in
        --journal) journal="$2"; shift 2 ;;
        *) shift ;;
    esac
done
printf '{"plan_sha256":"%s","records":[{"batch_id":"batch-01","outcome":"completed"}]}\n' \
    "$(printf 'b%.0s' $(seq 64))" > "$journal"
# The base moving mid-run is a postcondition under test, and the guest stage is
# where a run would write to it, so the injection lands between the digest the
# runner read before starting and the one it reads after stopping.
if [ "${FAKE_MUTATE_BASE:-0}" = "1" ]; then
    printf 'a different image\n' > images/fake-base.qcow2
fi
# The guest halting is what stops the container, and the stub records that.
printf 'stopped\n' > "${FAKE_CONTAINER_STATE:?}"
EOF
    chmod +x "$tree/scripts/execute-builder-batches.sh"

    write_stubs "$tree/bin"
}

write_stubs() {
    local bin="$1"

    cat > "$bin/docker" <<'EOF'
#!/bin/bash
# Answer only what the runner asks, and answer it from files the case controls.
state="$(cat "${FAKE_CONTAINER_STATE:-/dev/null}" 2>/dev/null || echo running)"
if [ "$1" = "compose" ]; then
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            up)   printf 'running\n' > "$FAKE_CONTAINER_STATE"
                  # The entrypoint creates the overlay inside the container.
                  printf 'overlay\n' > "${BUILDER_RUN_DIR}/overlay.qcow2"
                  exit 0 ;;
            ps)   printf '%s\n' "${FAKE_CONTAINER_ID}"; exit 0 ;;
            down|logs) exit 0 ;;
        esac
        shift
    done
    exit 0
fi
case "$1" in
    inspect)
        case "$*" in
            *State.Running*) [ "$state" = "running" ] && echo true || echo false ;;
            *State.ExitCode*) cat "${FAKE_CONTAINER_EXIT:-/dev/null}" 2>/dev/null || echo 0 ;;
            *.Image*) echo "sha256:feedface" ;;
            *) echo "" ;;
        esac
        exit 0 ;;
    image) echo "example.invalid/gnu-hurd-docker@sha256:deadbeef"; exit 0 ;;
    exec)
        case "$*" in
            *qemu-system-x86_64*) echo "QEMU emulator version 9.0.0 (stub)" ;;
            *sha256sum*) echo "c0ffee  /entrypoint.sh" ;;
        esac
        exit 0 ;;
esac
exit 0
EOF

    cat > "$bin/qemu-img" <<'EOF'
#!/bin/bash
case "$1" in
    info)  printf '{"backing-filename":"/opt/hurd-image/base/fake-base.qcow2"}\n' ;;
    check) printf '{"check-errors":0}\n' ;;
    rebase) : ;;
esac
exit 0
EOF

    # The offline filesystem passes have their own evidence and controls. Here
    # they succeed, so every case's verdict comes from the postconditions.
    printf '#!/bin/bash\nexit 0\n' > "$bin/guestfish"
    chmod +x "$bin/docker" "$bin/qemu-img" "$bin/guestfish"
}

# Run one case and report the runner's process status.
drive() {
    local tree="$1" exit_code_file="$2" mutate="$3"
    (
        cd "$tree" || exit 99
        export PATH="$tree/bin:$PATH"
        export FAKE_CONTAINER_ID="containerfixture01"
        export FAKE_CONTAINER_STATE="$tree/container-state"
        export FAKE_CONTAINER_EXIT="$exit_code_file"
        export BUILD_ROOT="$tree/builds"
        export BUILD_RUN_ID="fixture"
        export BUILDER_TIMEOUT=30
        export BUILDER_SSH_PORT=2223
        # This fixture asserts disposal order and postconditions with a stubbed
        # container runtime; the image-identity preflight is a separate
        # mechanism with its own fixture, so it is skipped here rather than
        # faked.
        export BUILDER_SKIP_IMAGE_PREFLIGHT=1
        [ "$mutate" = "mutate" ] && export FAKE_MUTATE_BASE=1
        bash scripts/run-hurd-build.sh >"$tree/runner.log" 2>&1
        printf '%s' "$?" > "$tree/exit-status"
    )
    cat "$tree/exit-status"
}

field() { jq -r "$2" "$1/builds/fixture/run.json" 2>/dev/null || echo "no-manifest"; }

# A run whose postconditions all hold reports success, discards the overlay, and
# records the identity of the container that ran.
tree="$WORKSPACE/accepted"
make_tree "$tree"
printf '0\n' > "$tree/exit-code"
status="$(drive "$tree" "$tree/exit-code" "keep")"
check "an accepted run exits zero" "$status" "0"
check "an accepted run reports success" "$(field "$tree" .status)" "success"
check "an accepted run discards its overlay" \
    "$([ -f "$tree/builds/fixture/overlay.qcow2" ] && echo present || echo absent)" "absent"
check "an accepted run records the container it started" \
    "$(field "$tree" .builder_container.container_id)" "containerfixture01"
check "an accepted run records the image the container came from" \
    "$(field "$tree" .builder_container.image_id)" "sha256:feedface"
check "an accepted run records the container exit status" \
    "$(field "$tree" .builder_container.exit_status)" "0"

# A base that moved during the run is the case whose overlay someone needs, so
# the run fails, keeps the overlay, and carries the verdict out in its status.
tree="$WORKSPACE/mutated"
make_tree "$tree"
printf '0\n' > "$tree/exit-code"
status="$(drive "$tree" "$tree/exit-code" "mutate")"
check "a mutated base fails the run" "$status" "1"
check "a mutated base is named in the manifest" "$(field "$tree" .status)" "base-mutated"
check "a mutated base retains the overlay" \
    "$([ -f "$tree/builds/fixture/overlay.qcow2" ] && echo present || echo absent)" "present"
check "a mutated base is recorded as a digest change" \
    "$([ "$(field "$tree" .builder_base.sha256_before)" \
        != "$(field "$tree" .builder_base.sha256_after)" ] && echo changed || echo same)" \
    "changed"

# A guest that journaled every planned round still fails the run when the
# container that carried it exited nonzero.
tree="$WORKSPACE/container-failed"
make_tree "$tree"
printf '3\n' > "$tree/exit-code"
status="$(drive "$tree" "$tree/exit-code" "keep")"
check "a nonzero container exit fails the run" "$status" "1"
check "a nonzero container exit is named in the manifest" \
    "$(field "$tree" .status)" "container-exit-nonzero"
check "a nonzero container exit retains the overlay" \
    "$([ -f "$tree/builds/fixture/overlay.qcow2" ] && echo present || echo absent)" "present"

printf '\n%d failure(s)\n' "$failures"
[ "$failures" -eq 0 ]
