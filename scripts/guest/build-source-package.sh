#!/bin/bash
# Build one Debian source package inside the guest as the unprivileged account.
#
# This file is copied into the guest from a recorded commit and run there, which
# keeps the build out of nested SSH heredoc quoting: a root heredoc that changes
# user midway reparses its own body in two shells, and the command that actually
# ran stops being the command the evidence records.
#
# The source is built exactly as the archive publishes it. No patch is applied,
# no build option is relaxed, and no failed stage is retried with different
# arguments, because a build that succeeds only after an unrecorded change
# describes a source tree that does not exist. A nonzero result is a classified
# outcome and the caller keeps it.

set -uo pipefail

source_name=""
source_version=""
parallelism="1"
output_dir=""

while [ $# -gt 0 ]; do
    case "$1" in
        --source) source_name="$2"; shift 2 ;;
        --version) source_version="$2"; shift 2 ;;
        --parallelism) parallelism="$2"; shift 2 ;;
        --output) output_dir="$2"; shift 2 ;;
        *) printf 'guest build: unknown argument %s\n' "$1" >&2; exit 2 ;;
    esac
done
[ -n "$source_name" ] && [ -n "$source_version" ] && [ -n "$output_dir" ] || {
    printf 'guest build: --source, --version and --output are required\n' >&2
    exit 2
}

work="${HOME}/build/${source_name}-${source_version}"
outcome="unknown"
build_status=127

# A build directory that already holds a previous attempt makes the outputs
# ambiguous, so each build starts from a directory that did not exist.
rm -rf "$work"
mkdir -p "$work" "$output_dir"
cd "$work" || exit 2

record() { printf '%s\n' "$*" >>"${output_dir}/build-stages.log"; }
: >"${output_dir}/build-stages.log"

record "host architecture: $(dpkg-architecture -qDEB_HOST_ARCH 2>/dev/null)"
record "gcc: $(gcc --version 2>/dev/null | head -1)"
record "dpkg-buildpackage: $(dpkg-buildpackage --version 2>/dev/null | head -1)"
record "started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

emit_result() {
    cat > "${output_dir}/build-result.json" <<EOF
{
  "schema_version": 1,
  "kind": "hurd-native-source-build-result",
  "source": "${source_name}",
  "version": "${source_version}",
  "architecture": "$(dpkg-architecture -qDEB_HOST_ARCH 2>/dev/null)",
  "build_user": "$(id -un)",
  "outcome": "${outcome}",
  "build_exit_status": ${build_status},
  "build_command": "DEB_BUILD_OPTIONS=parallel=${parallelism} dpkg-buildpackage -us -uc -b -j${parallelism}",
  "completed_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    printf '%s\n' "$outcome"
}

# apt-get source reads the deb-src lines the base binds to the pinned snapshot,
# so the exact published version is what arrives.
if ! apt-get source --only-source "${source_name}=${source_version}" \
        >"${output_dir}/source-fetch.stdout" 2>"${output_dir}/source-fetch.stderr"; then
    outcome="source-fetch-failed"; emit_result; exit 1
fi
record "fetched: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# The .dsc and every file it names are the source identity, recorded before the
# build touches them.
for candidate in *.dsc; do
    [ -f "$candidate" ] || continue
    cp "$candidate" "${output_dir}/"
done
sha256sum ./*.dsc ./*.tar.* ./*.diff.gz 2>/dev/null \
    >"${output_dir}/source-checksums.txt" || true
if [ ! -s "${output_dir}/source-checksums.txt" ]; then
    outcome="source-verification-failed"; emit_result; exit 1
fi

tree="$(find . -maxdepth 1 -mindepth 1 -type d | head -1)"
if [ -z "$tree" ] || [ ! -d "$tree/debian" ]; then
    outcome="source-extraction-failed"; emit_result; exit 1
fi
record "source tree: ${tree}"

cd "$tree" || { outcome="source-extraction-failed"; emit_result; exit 1; }
env > "${output_dir}/build-environment.txt"

DEB_BUILD_OPTIONS="parallel=${parallelism}" dpkg-buildpackage -us -uc -b \
    "-j${parallelism}" >"${output_dir}/build.stdout" 2>"${output_dir}/build.stderr"
build_status=$?
record "build exit: ${build_status}"
record "finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [ "$build_status" -ne 0 ]; then
    outcome="build-failed"
    emit_result
    exit 1
fi

# dpkg-buildpackage writes its outputs beside the source tree.
cd "$work" || exit 2
found=0
for artifact in *.deb *.ddeb *.changes *.buildinfo; do
    [ -f "$artifact" ] || continue
    cp "$artifact" "${output_dir}/"
    found=$((found + 1))
done
if [ "$found" -eq 0 ]; then
    outcome="artifact-contract-failed"; emit_result; exit 1
fi
record "artifacts copied: ${found}"

outcome="completed"
emit_result
exit 0
