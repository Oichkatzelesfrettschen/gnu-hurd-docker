#!/bin/bash
# Prove scripts/install-test-hurd-packages.sh against a stubbed guest
# transport, covering every named outcome: the simulate-then-install gate,
# the audit, the pkg-config/header discovery, and the compile/link/run probe
# that proves the runtime dependency the build overlay could have concealed.
#
# ssh and scp are stubbed rather than the guest itself: guest_ssh_exec passes
# one command string per call, so a fake ssh that pattern-matches the
# distinctive substring of each remote command answers exactly what the case
# under test controls, with every other stage left at its default success.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/install-test-hurd-packages.sh"
WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/package-install-test-XXXXXX")"
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

bin="$WORKSPACE/bin"
mkdir -p "$bin"

cat > "$bin/scp" <<'EOF'
#!/bin/bash
exit 0
EOF

# Every mode variable defaults to the value that lets the fixture reach the
# next stage, so one case sets exactly the variable its defect belongs to.
cat > "$bin/ssh" <<'EOF'
#!/bin/bash
cmd="${@: -1}"
case "$cmd" in
    *"rm -rf /root/incoming"*) exit 0 ;;
    *"apt-get -s install"*)
        case "${MODE_SIMULATE:-ok}" in
            fail) exit 1 ;;
            removes) printf 'Remv somepkg\n' ;;
            *) printf 'Inst fixture-dev\n' ;;
        esac
        exit 0 ;;
    *"apt-get install -y"*)
        [ "${MODE_INSTALL:-ok}" = "fail" ] && exit 1 || exit 0 ;;
    *"dpkg -C"*)
        [ "${MODE_AUDIT:-clean}" = "dirty" ] && printf 'some problem reported\n'
        exit 0 ;;
    *"dpkg-query -W"*) printf 'fixture-dev 1.0-1 hurd-amd64\n'; exit 0 ;;
    *'\.pc$'*)
        case "${MODE_PC_PATH:-present}" in
            absent) : ;;
            *) printf '/usr/lib/pkgconfig/fixture.pc\n' ;;
        esac
        exit 0 ;;
    *"pkg-config --modversion"*)
        [ "${MODE_PKG_CONFIG:-ok}" = "fail" ] && exit 1
        printf '1.0.0\n'; exit 0 ;;
    *'\.h$'*)
        case "${MODE_HEADER:-present}" in
            absent) : ;;
            *) printf '/usr/include/fixture.h\n' ;;
        esac
        exit 0 ;;
    *"cc -c probe.c"*)
        [ "${MODE_COMPILE:-ok}" = "fail" ] && exit 1 || exit 0 ;;
    *"-Wl,--no-as-needed"*)
        [ "${MODE_LINK:-ok}" = "fail" ] && exit 1 || exit 0 ;;
    *"pkg-config --libs"*)
        printf -- '-lfixture\n'; exit 0 ;;
    *"readelf -d"*)
        case "${MODE_NEEDED:-present}" in
            absent) printf 'NEEDED  libc.so.0.3\n' ;;
            *) printf 'NEEDED  libfixture.so.0\nNEEDED  libc.so.0.3\n' ;;
        esac
        exit 0 ;;
    *"/tmp/probe &&"*)
        [ "${MODE_RUN:-ok}" = "fail" ] && exit 1
        printf 'probe-exited-zero\n'; exit 0 ;;
    *) exit 0 ;;
esac
EOF
chmod +x "$bin/ssh" "$bin/scp"

deb_dir="$WORKSPACE/debs"
mkdir -p "$deb_dir"
printf 'a fixture binary package\n' > "$deb_dir/fixture-dev_1.0-1_hurd-amd64.deb"

drive() {
    local label="$1"; shift
    local run_dir="$WORKSPACE/run-${label}"
    mkdir -p "$run_dir"
    (
        export PATH="$bin:$PATH"
        export GUEST_SSH_HOST=127.0.0.1 GUEST_SSH_PORT=2223 GUEST_SSH_USER=root
        export GUEST_SSH_KEY="$WORKSPACE/fake-key"
        touch "$GUEST_SSH_KEY"
        for assignment in "$@"; do export "${assignment?}"; done
        bash "$SCRIPT" --package "$deb_dir" --run-dir "$run_dir" \
            --probe-package fixture-dev \
            >"$run_dir/stdout" 2>"$run_dir/stderr"
    )
    jq -r '.status' "$run_dir/install-test.json" 2>/dev/null || echo "no-report"
}

check "a clean simulate-install-audit-probe pass reports passed" \
    "$(drive full-pass)" "passed"

check "a simulation that would remove a package is refused" \
    "$(drive simulated-removal MODE_SIMULATE=removes)" "simulation-removes-packages"

check "a failed simulation is refused before any real install" \
    "$(drive simulation-failed MODE_SIMULATE=fail)" "simulation-failed"

check "a failed real install is refused" \
    "$(drive install-failed MODE_INSTALL=fail)" "install-failed"

check "a dpkg audit reporting a problem is refused" \
    "$(drive audit-reported MODE_AUDIT=dirty)" "audit-reported-problems"

check "an absent pkg-config metadata file is refused" \
    "$(drive pc-absent MODE_PC_PATH=absent)" "development-surface-absent"

check "a failing pkg-config query is refused" \
    "$(drive pkg-config-failed MODE_PKG_CONFIG=fail)" "pkg-config-failed"

check "an absent installed header is refused" \
    "$(drive header-absent MODE_HEADER=absent)" "development-headers-absent"

check "a failing probe compile is refused" \
    "$(drive compile-failed MODE_COMPILE=fail)" "development-probe-compile-failed"

check "a failing probe link is refused" \
    "$(drive link-failed MODE_LINK=fail)" "development-probe-link-failed"

check "a link that drops the library from NEEDED is refused" \
    "$(drive needed-absent MODE_NEEDED=absent)" "development-probe-library-not-needed"

check "a failing probe run is refused" \
    "$(drive run-failed MODE_RUN=fail)" "development-probe-run-failed"

echo ""
echo "${failures} failure(s)"
[ "$failures" -eq 0 ]
