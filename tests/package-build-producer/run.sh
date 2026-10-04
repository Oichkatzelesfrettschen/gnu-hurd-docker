#!/bin/bash
# Drive scripts/guest/build-source-package.sh against stubbed Debian tooling.
#
# This script runs inside the guest as the unprivileged builder account and
# is copied there from a recorded commit, so nothing about its own transport
# is under test here -- only what it does with apt-get's and
# dpkg-buildpackage's exit statuses and outputs, which real Debian tooling is
# not required on the host to stand in for.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PRODUCER="$ROOT/scripts/guest/build-source-package.sh"
WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/package-build-producer-XXXXXX")"
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

# Stands in for dpkg-architecture -qDEB_HOST_ARCH, which this host does not
# carry; the producer only ever reads this one query field from it.
cat > "$bin/dpkg-architecture" <<'EOF'
#!/bin/bash
[ "$1" = "-qDEB_HOST_ARCH" ] && printf 'hurd-amd64\n'
exit 0
EOF

# APT_SOURCE_MODE selects what the fetch leaves in the guest build directory.
cat > "$bin/apt-get" <<'EOF'
#!/bin/bash
[ "$1" = "source" ] || exit 0
case "${APT_SOURCE_MODE:-normal}" in
    fail) exit 1 ;;
    empty) exit 0 ;;
    no-tree)
        printf 'Format: 3.0\n' > fixture_1.0.dsc
        printf 'payload\n' > fixture_1.0.orig.tar.gz
        exit 0 ;;
    two-trees)
        printf 'Format: 3.0\n' > fixture_1.0.dsc
        printf 'payload\n' > fixture_1.0.orig.tar.gz
        mkdir -p fixture-1.0/debian fixture-1.0-stray/debian
        exit 0 ;;
    no-debian)
        printf 'Format: 3.0\n' > fixture_1.0.dsc
        printf 'payload\n' > fixture_1.0.orig.tar.gz
        mkdir -p fixture-1.0
        exit 0 ;;
    normal|*)
        printf 'Format: 3.0\n' > fixture_1.0.dsc
        printf 'payload\n' > fixture_1.0.orig.tar.gz
        mkdir -p fixture-1.0/debian
        printf 'stub debian/control\n' > fixture-1.0/debian/control
        exit 0 ;;
esac
EOF

# DPKG_BUILD_MODE selects what the build leaves beside the source tree, one
# level up from the cwd dpkg-buildpackage runs in.
cat > "$bin/dpkg-buildpackage" <<'EOF'
#!/bin/bash
[ "$1" = "--version" ] && { printf 'dpkg-buildpackage stub 1.0\n'; exit 0; }
case "${DPKG_BUILD_MODE:-normal}" in
    fail) exit 2 ;;
    no-artifacts) exit 0 ;;
    normal|*)
        printf 'binary\n' > ../fixture_1.0_hurd-amd64.deb
        printf 'changes\n' > ../fixture_1.0_hurd-amd64.changes
        printf 'buildinfo\n' > ../fixture_1.0_hurd-amd64.buildinfo
        exit 0 ;;
esac
EOF
chmod +x "$bin"/*

drive() {
    local mode_apt="$1" mode_build="$2" out="$WORKSPACE/out-$3"
    mkdir -p "$out"
    (
        export PATH="$bin:$PATH"
        export HOME="$WORKSPACE/home"
        mkdir -p "$HOME"
        export APT_SOURCE_MODE="$mode_apt"
        export DPKG_BUILD_MODE="$mode_build"
        bash "$PRODUCER" --source fixture --version 1.0 --parallelism 1 --output "$out" \
            >"$out/producer.stdout" 2>"$out/producer.stderr"
        printf '%s' "$?" > "$out/exit-status"
    )
    cat "$out/exit-status"
}

outcome_of() { jq -r '.outcome' "$1/build-result.json" 2>/dev/null || echo "no-result"; }

# 1. The unmodified path: fetch, one tree, a build that produces artifacts.
exit_code="$(drive normal normal completed)"
check "a completed build exits nonzero from the producer's own contract" "$exit_code" "0"
check "a completed build records outcome completed" \
    "$(outcome_of "$WORKSPACE/out-completed")" "completed"
check "a completed build retains the .dsc" \
    "$([ -f "$WORKSPACE/out-completed/fixture_1.0.dsc" ] && echo present || echo absent)" "present"
check "a completed build retains the orig tarball, not only its checksum" \
    "$([ -f "$WORKSPACE/out-completed/fixture_1.0.orig.tar.gz" ] && echo present || echo absent)" "present"
check "a completed build retains the produced .deb" \
    "$([ -f "$WORKSPACE/out-completed/fixture_1.0_hurd-amd64.deb" ] && echo present || echo absent)" "present"

# 2. apt-get source itself fails.
exit_code="$(drive fail normal source-fetch-failed)"
check "a failed source fetch exits nonzero" "$exit_code" "1"
check "a failed source fetch is classified source-fetch-failed" \
    "$(outcome_of "$WORKSPACE/out-source-fetch-failed")" "source-fetch-failed"

# 3. apt-get source reports success but leaves nothing behind.
exit_code="$(drive empty normal source-verification-failed)"
check "no fetched payload is classified source-verification-failed" \
    "$(outcome_of "$WORKSPACE/out-source-verification-failed")" "source-verification-failed"

# 4. No extracted directory at all.
exit_code="$(drive no-tree normal source-extraction-no-tree)"
check "no extracted directory is classified source-extraction-failed" \
    "$(outcome_of "$WORKSPACE/out-source-extraction-no-tree")" "source-extraction-failed"

# 5. Two candidate directories: picking "the first" would silently build the
# wrong tree, so this is refused rather than resolved by fiat.
exit_code="$(drive two-trees normal source-extraction-two-trees)"
check "two candidate source directories is classified source-extraction-failed" \
    "$(outcome_of "$WORKSPACE/out-source-extraction-two-trees")" "source-extraction-failed"

# 6. One directory but it carries no debian/ subdirectory.
exit_code="$(drive no-debian normal source-extraction-no-debian)"
check "a tree with no debian/ is classified source-extraction-failed" \
    "$(outcome_of "$WORKSPACE/out-source-extraction-no-debian")" "source-extraction-failed"

# 7. The build itself fails.
exit_code="$(drive normal fail build-failed)"
check "a failed dpkg-buildpackage is classified build-failed" \
    "$(outcome_of "$WORKSPACE/out-build-failed")" "build-failed"

# 8. The build exits zero but produces nothing.
exit_code="$(drive normal no-artifacts artifact-contract-failed)"
check "a build with no artifacts is classified artifact-contract-failed" \
    "$(outcome_of "$WORKSPACE/out-artifact-contract-failed")" "artifact-contract-failed"

echo ""
echo "${failures} failure(s)"
[ "$failures" -eq 0 ]
