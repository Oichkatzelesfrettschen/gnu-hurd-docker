#!/bin/bash
# Prove the manifest writer and the evidence checker as a producer-checker
# pair: every case here runs write-package-build-manifest.py against real
# files on disk, then runs check-package-build-evidence.py against the
# manifest it wrote, rather than hand-assembling an accepted manifest that
# would test the checker while bypassing the writer.
#
# dpkg-deb is not installed on this host, so it is stubbed to answer the
# control fields each case controls; every other file the writer reads --
# the .changes Checksums-Sha256/Files stanzas, build-result.json,
# build-run.json -- is a real file this fixture writes.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRITER="$ROOT/scripts/write-package-build-manifest.py"
CHECKER="$ROOT/scripts/check-package-build-evidence.py"
WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/package-build-manifest-XXXXXX")"
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
cat > "$bin/dpkg-deb" <<'EOF'
#!/bin/bash
# DPKG_DEB_ARCH selects what control-field Architecture this stub reports, so
# one case can name a Linux architecture without a second binary and a second
# stub.
[ "$1" = "-f" ] || exit 1
cat <<CTRL
Package: libfixture-dev
Version: 1.0-1
Architecture: ${DPKG_DEB_ARCH:-hurd-amd64}
CTRL
EOF
chmod +x "$bin/dpkg-deb"
export PATH="$bin:$PATH"

# Every case gets its own package directory and its own evidence root, so one
# case's mutation cannot leak into another's verdict.
build_fixture() {
    local case_name="$1" mode="$2"
    local package_dir="$WORKSPACE/${case_name}/package"
    local evidence_root="$WORKSPACE/${case_name}/evidence/package-builds/fixture"
    mkdir -p "$package_dir" "$evidence_root"

    local request_path="$package_dir/build-request.json"
    cat > "$request_path" <<EOF
{
  "schema_version": 1,
  "source": "fixture",
  "version": "1.0-1",
  "architecture": "hurd-amd64",
  "build_user": "builder",
  "required_binary_packages": ["libfixture-dev"],
  "local_patches": []
}
EOF
    local request_sha
    request_sha="$(sha256sum "$request_path" | cut -d' ' -f1)"

    printf 'a fixture binary package\n' > "$package_dir/fixture_1.0-1_hurd-amd64.deb"
    local deb_sha deb_size
    deb_sha="$(sha256sum "$package_dir/fixture_1.0-1_hurd-amd64.deb" | cut -d' ' -f1)"
    deb_size="$(stat -c%s "$package_dir/fixture_1.0-1_hurd-amd64.deb")"

    cat > "$package_dir/fixture_1.0-1_hurd-amd64.changes" <<EOF
Format: 1.8
Source: fixture
Architecture: hurd-amd64
Version: 1.0-1
Files:
 ${deb_sha:0:32} ${deb_size} devel optional fixture_1.0-1_hurd-amd64.deb
Checksums-Sha256:
 ${deb_sha} ${deb_size} fixture_1.0-1_hurd-amd64.deb
EOF
    printf 'Format: 1.0\nSource: fixture\n' > "$package_dir/fixture_1.0-1_hurd-amd64.buildinfo"

    cat > "$package_dir/build-result.json" <<EOF
{
  "schema_version": 1,
  "outcome": "completed",
  "build_exit_status": 0,
  "architecture": "hurd-amd64",
  "build_user": "builder"
}
EOF

    cat > "$package_dir/build-run.json" <<EOF
{
  "schema_version": 1,
  "outcome": "completed",
  "request_sha256": "${request_sha}",
  "guest_console": {
    "kernel_output_observed": true,
    "mach_ipc_allocation_error": false
  }
}
EOF

    case "$mode" in
        duplicate-changes)
            cp "$package_dir/fixture_1.0-1_hurd-amd64.changes" \
               "$package_dir/fixture_1.0-1_hurd-amd64.extra.changes" ;;
        missing-declared)
            rm -f "$package_dir/fixture_1.0-1_hurd-amd64.deb" ;;
        digest-mismatch)
            printf 'a corrupted binary!!!!!!\n' > "$package_dir/fixture_1.0-1_hurd-amd64.deb" ;;
        undeclared-binary)
            printf 'an undeclared binary\n' > "$package_dir/fixture_1.0-1-extra_hurd-amd64.deb" ;;
        missing-required)
            python3 -c "
import json
p = '$request_path'
d = json.load(open(p))
d['required_binary_packages'] = ['libneverbuilt-dev']
json.dump(d, open(p, 'w'))
" ;;
        console-not-observed)
            python3 -c "
import json
p = '$package_dir/build-run.json'
d = json.load(open(p))
d['guest_console']['kernel_output_observed'] = False
json.dump(d, open(p, 'w'))
" ;;
        accept|linux-arch) : ;;
    esac

    printf '%s\n%s\n%s\n' "$package_dir" "$evidence_root" "$request_path"
}

drive() {
    local case_name="$1" mode="$2" arch="${3:-hurd-amd64}"
    local lines package_dir evidence_root request_path
    mapfile -t lines < <(build_fixture "$case_name" "$mode")
    package_dir="${lines[0]}"; evidence_root="${lines[1]}"; request_path="${lines[2]}"

    DPKG_DEB_ARCH="$arch" python3 "$WRITER" \
        --package "$package_dir" --request "$request_path" \
        --output "$evidence_root/artifact-manifest.json" \
        --run "$package_dir/build-run.json" \
        >"$WORKSPACE/${case_name}.writer.log" 2>&1

    python3 "$CHECKER" "$WORKSPACE/${case_name}/evidence/package-builds" \
        >"$WORKSPACE/${case_name}.checker.log" 2>&1
    echo "$?"
}

exit_code="$(drive accept accept)"
check "a real completed package build is accepted" "$exit_code" "0"

exit_code="$(drive duplicate-changes duplicate-changes)"
check "two .changes files in one build directory is refused" "$exit_code" "1"

exit_code="$(drive missing-declared missing-declared)"
check "a .changes-declared artifact that is absent is refused" "$exit_code" "1"

exit_code="$(drive digest-mismatch digest-mismatch)"
check "a present artifact hashing to the wrong digest is refused" "$exit_code" "1"

exit_code="$(drive undeclared-binary undeclared-binary)"
check "a .deb the .changes never declared is refused" "$exit_code" "1"

exit_code="$(drive missing-required missing-required)"
check "a build missing a required binary package is refused" "$exit_code" "1"

exit_code="$(drive linux-arch accept amd64)"
check "a binary package carrying a Linux architecture is refused" "$exit_code" "1"

exit_code="$(drive console-not-observed console-not-observed)"
check "a build run whose console never observed kernel output is refused" "$exit_code" "1"

echo ""
echo "${failures} failure(s)"
[ "$failures" -eq 0 ]
