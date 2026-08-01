#!/bin/bash
# Drive scripts/run-hurd-install-test.sh's lifecycle against stubbed
# container, image, guest-filesystem, and SSH tools.
#
# The script owns a second overlay's disposal and postconditions the same way
# run-hurd-build.sh owns the first one's, and none of that is reachable from a
# shell gate without a real container, a multi-gigabyte base, and a guest that
# boots for minutes. Every tool that would require one is stubbed; the run
# directory, the manifest, and the process exit status are real.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/install-test-run-lifecycle-XXXXXX")"
failures=0

cleanup() { [ "${KEEP_WORKSPACE:-0}" = "1" ] || rm -rf "$WORKSPACE"; }
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

make_tree() {
    local tree="$1"
    mkdir -p "$tree/scripts/lib" "$tree/scripts/guest" "$tree/config/minty" \
        "$tree/images" "$tree/bin" "$tree/package"
    cp "$ROOT/scripts/run-hurd-install-test.sh" "$tree/scripts/"
    cp "$ROOT/scripts/install-test-hurd-packages.sh" "$tree/scripts/"
    cp "$ROOT/scripts/lib/builder-image-preflight.sh" "$tree/scripts/lib/"
    cp "$ROOT/scripts/lib/guest-ssh.sh" "$tree/scripts/lib/"
    chmod +x "$tree/scripts/run-hurd-install-test.sh" "$tree/scripts/install-test-hurd-packages.sh"
    printf 'a fixture binary package\n' > "$tree/package/fixture-dev_1.0-1_hurd-amd64.deb"

    local base_sha
    printf 'a synthetic backing image\n' > "$tree/images/fake-base.qcow2"
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
    printf '{"schema_version":1,"kind":"fixture-manifest"}\n' > "$tree/artifact-manifest.json"

    write_stubs "$tree/bin"
}

write_stubs() {
    local bin="$1"

    cat > "$bin/docker" <<'EOF'
#!/bin/bash
state="$(cat "${FAKE_CONTAINER_STATE:-/dev/null}" 2>/dev/null || echo running)"
if [ "$1" = "compose" ]; then
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            up)   printf 'running\n' > "$FAKE_CONTAINER_STATE"
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

    printf '#!/bin/bash\nexit 0\n' > "$bin/guestfish"

    # guest_ssh_alive runs `ssh ... 'exit 0'`; install-test-hurd-packages.sh's
    # own guest_ssh_exec calls carry the distinctive remote-command substrings
    # this fixture's package-install-test suite already established.
    cat > "$bin/ssh" <<'EOF'
#!/bin/bash
cmd="${@: -1}"
case "$cmd" in
    "exit 0") exit 0 ;;
    *"sync; halt"*)
        # A halted guest is what stops the container; the stub records that
        # the way execute-builder-batches.sh's own stub does in the sibling
        # build-run-postconditions fixture.
        printf 'stopped\n' > "${FAKE_CONTAINER_STATE:?}"
        exit 0 ;;
    *"rm -rf /root/incoming"*) exit 0 ;;
    *"apt-get -s install"*)
        [ "${MODE_SIMULATE:-ok}" = "fail" ] && exit 1
        printf 'Inst fixture-dev\n'; exit 0 ;;
    *"apt-get install -y"*)
        [ "${MODE_INSTALL:-ok}" = "fail" ] && exit 1 || exit 0 ;;
    *"dpkg -C"*) exit 0 ;;
    *"dpkg-query -W"*) printf 'fixture-dev 1.0-1 hurd-amd64\n'; exit 0 ;;
    *'\.pc$'*) printf '/usr/lib/pkgconfig/fixture.pc\n'; exit 0 ;;
    *"pkg-config --modversion"*) printf '1.0.0\n'; exit 0 ;;
    *'\.h$'*) printf '/usr/include/fixture.h\n'; exit 0 ;;
    *"cc -c probe.c"*) exit 0 ;;
    *"-Wl,--no-as-needed"*) exit 0 ;;
    *"pkg-config --libs"*) printf -- '-lfixture\n'; exit 0 ;;
    *"readelf -d"*) printf 'NEEDED  libfixture.so.0\n'; exit 0 ;;
    *"/tmp/probe &&"*) printf 'probe-exited-zero\n'; exit 0 ;;
    *) exit 0 ;;
esac
EOF
    printf '#!/bin/bash\nexit 0\n' > "$bin/scp"
    chmod +x "$bin/docker" "$bin/qemu-img" "$bin/guestfish" "$bin/ssh" "$bin/scp"
}

drive() {
    local tree="$1" exit_code_file="$2"
    shift 2
    (
        cd "$tree" || exit 99
        export PATH="$tree/bin:$PATH"
        export FAKE_CONTAINER_ID="containerfixture01"
        export FAKE_CONTAINER_STATE="$tree/container-state"
        export FAKE_CONTAINER_EXIT="$exit_code_file"
        export BUILD_ROOT="$tree/builds"
        export BUILD_RUN_ID="fixture"
        export BUILDER_TIMEOUT=30
        export BUILDER_SSH_PORT=2224
        export BUILDER_SSH_READY_TIMEOUT=10
        export BUILDER_SKIP_IMAGE_PREFLIGHT=1
        export GUEST_SSH_KEY="$tree/fake-key"
        touch "$GUEST_SSH_KEY"
        for assignment in "$@"; do export "${assignment?}"; done
        bash scripts/run-hurd-install-test.sh --package package \
            --artifact-manifest artifact-manifest.json --probe-package fixture-dev \
            >"$tree/runner.log" 2>&1
        printf '%s' "$?" > "$tree/exit-status"
    )
    cat "$tree/exit-status"
}

field() { jq -r "$2" "$1/builds/fixture/run.json" 2>/dev/null || echo "no-manifest"; }

# 1. A clean lifecycle: guest answers SSH, the install test passes, the guest
# halts, and the offline checks pass.
tree1="$WORKSPACE/pass"; mkdir -p "$tree1"; echo 0 > "$tree1/exit-code"
make_tree "$tree1"
exit_code="$(drive "$tree1" "$tree1/exit-code")"
check "a clean install-test run exits zero" "$exit_code" "0"
check "a clean install-test run reports success" "$(field "$tree1" .status)" "success"
check "a clean install-test run discards its overlay" \
    "$([ -f "$tree1/builds/fixture/overlay.qcow2" ] && echo present || echo absent)" "absent"
check "a clean install-test run records install_test passed" \
    "$(field "$tree1" .install_test)" "passed"
check "a clean install-test run binds the artifact manifest under test" \
    "$(field "$tree1" '.artifact_manifest_under_test.sha256')" \
    "$(sha256sum "$tree1/artifact-manifest.json" | cut -d' ' -f1)"

# 2. The install test itself fails (a simulated removal): the run fails and
# retains its overlay for diagnosis rather than discarding the evidence a
# failed install test exists to produce.
tree2="$WORKSPACE/install-test-fails"; mkdir -p "$tree2"; echo 0 > "$tree2/exit-code"
make_tree "$tree2"
exit_code="$(drive "$tree2" "$tree2/exit-code" "MODE_SIMULATE=fail")"
check "a failing install test fails the run" "$exit_code" "1"
check "a failing install test is named in the manifest" \
    "$(field "$tree2" .status)" "install-test-failed"
check "a failing install test retains its overlay" \
    "$([ -f "$tree2/builds/fixture/overlay.qcow2" ] && echo present || echo absent)" "present"

echo ""
echo "${failures} failure(s)"
[ "$failures" -eq 0 ]
