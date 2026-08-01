#!/bin/bash
# Install a build's outputs into a guest that never held its build dependencies.
#
# A build overlay carries every build dependency the campaign installed, so a
# package that forgot to declare a runtime dependency installs there and works
# there. The environment supplies what the package failed to. Only a guest that
# never held those packages can tell the two apart, which is why this runs
# against a second fresh overlay over the same locked base rather than against
# the overlay that produced the artifacts.
#
# APT performs the installation rather than `dpkg -i`, because dpkg installs a
# package whose dependencies are missing and leaves it unconfigured, which reads
# as a success followed by an unrelated audit failure. APT resolves first, and a
# transaction that would remove an installed package is the finding.
#
# The development surface is exercised as commands. A .deb that unpacks proves
# the packaging; pkg-config answering, a translation unit compiling against the
# installed headers, a link resolving, and the resulting binary running are what
# say the package can carry the dependency the next build needs.

set -euo pipefail

package_dir=""
run_dir=""
probe_package=""
while [ $# -gt 0 ]; do
    case "$1" in
        --package) package_dir="$2"; shift 2 ;;
        --run-dir) run_dir="$2"; shift 2 ;;
        --probe-package) probe_package="$2"; shift 2 ;;
        *) printf 'install test: unknown argument %s\n' "$1" >&2; exit 2 ;;
    esac
done
[ -n "$package_dir" ] && [ -d "$package_dir" ] || {
    printf 'install test: --package naming an existing directory is required\n' >&2; exit 2; }
[ -n "$run_dir" ] && [ -d "$run_dir" ] || {
    printf 'install test: --run-dir naming an existing directory is required\n' >&2; exit 2; }

script_dir="$(cd "$(dirname "$0")" && pwd)"
export GUEST_SSH_HOST="${GUEST_SSH_HOST:-127.0.0.1}"
export GUEST_SSH_PORT="${GUEST_SSH_PORT:-${BUILDER_SSH_PORT:-2223}}"
export GUEST_SSH_USER="${GUEST_SSH_USER:-root}"
export GUEST_SSH_KEY="${GUEST_SSH_KEY:-ssh-test-keys/hurd_test_key}"
export GUEST_KNOWN_HOSTS="${GUEST_KNOWN_HOSTS:-${run_dir}/known_hosts}"
# shellcheck source=scripts/lib/guest-ssh.sh
source "${script_dir}/lib/guest-ssh.sh"

log() { printf 'install test: %s\n' "$*" >&2; }
evidence="${run_dir}/artifacts"
mkdir -p "$evidence"

status="unknown"
simulated_removals="not run"
audit="not run"
pkg_config_version=""
probe_compiled=false
probe_linked=false
probe_ran=false

finish() {
    cat > "${run_dir}/install-test.json" <<EOF
{
  "schema_version": 1,
  "kind": "hurd-native-package-install-test",
  "status": "${status}",
  "probe_package": "${probe_package}",
  "simulated_removals": "${simulated_removals}",
  "dpkg_audit": "${audit}",
  "pkg_config_version": "${pkg_config_version}",
  "development_probe": {
    "compiled": ${probe_compiled},
    "linked": ${probe_linked},
    "ran": ${probe_ran}
  }
}
EOF
    log "status ${status}"
}
trap finish EXIT

mapfile -t transfer < <(guest_ssh_options | sed 's/^-p$/-P/')

debs=()
while IFS= read -r candidate; do debs+=("$candidate"); done < <(
    find "$package_dir" -maxdepth 1 -name '*.deb' -type f | sort)
[ "${#debs[@]}" -gt 0 ] || { status="no-packages"; log "no .deb outputs to install"; exit 1; }
log "installing ${#debs[@]} package(s) into a guest that never built them"

guest_ssh_exec "${evidence}/install-prepare.stdout" "${evidence}/install-prepare.stderr" \
    "rm -rf /root/incoming && mkdir -p /root/incoming"
scp "${transfer[@]}" "${debs[@]}" "root@${GUEST_SSH_HOST}:/root/incoming/" >/dev/null

# The simulation runs first, and a transaction that would remove an installed
# package is refused before anything is written.
if ! guest_ssh_exec "${evidence}/install-simulate.stdout" \
        "${evidence}/install-simulate.stderr" \
        "cd /root/incoming && DEBIAN_FRONTEND=noninteractive apt-get -s install -y ./*.deb"; then
    status="simulation-failed"; exit 1
fi
removals="$(grep -cE '^Remv ' "${evidence}/install-simulate.stdout" || true)"
simulated_removals="$removals"
if [ "$removals" != "0" ]; then
    status="simulation-removes-packages"
    log "the simulated install would remove ${removals} package(s)"
    exit 1
fi

if ! guest_ssh_exec "${evidence}/install.stdout" "${evidence}/install.stderr" \
        "cd /root/incoming && DEBIAN_FRONTEND=noninteractive apt-get install -y ./*.deb"; then
    status="install-failed"; exit 1
fi

if ! guest_ssh_exec "${evidence}/install-audit.stdout" "${evidence}/install-audit.stderr" \
        "dpkg -C"; then
    status="audit-failed"; exit 1
fi
if [ -s "${evidence}/install-audit.stdout" ]; then
    audit="reported problems"; status="audit-reported-problems"; exit 1
fi
audit="clean"

guest_ssh_exec "${evidence}/installed-versions.txt" "${evidence}/installed-versions.stderr" \
    "dpkg-query -W -f='\${binary:Package} \${Version} \${Architecture}\n' \$(ls /root/incoming/*.deb | sed 's#.*/##; s/_.*//') 2>/dev/null || true"

if [ -z "$probe_package" ]; then
    status="installed"; exit 0
fi

# The pkg-config name and the umbrella header come from the installed package
# rather than from a guess made before it existed.
if ! guest_ssh_exec "${evidence}/pkg-config-name.txt" "${evidence}/pkg-config.stderr" \
        "dpkg -L ${probe_package} 2>/dev/null | grep '\.pc\$' | head -1"; then
    status="development-surface-absent"; exit 1
fi
pc_path="$(tr -d '\r\n' < "${evidence}/pkg-config-name.txt")"
if [ -z "$pc_path" ]; then
    status="development-surface-absent"
    log "${probe_package} installs no pkg-config metadata"
    exit 1
fi
pc_name="$(basename "$pc_path" .pc)"
log "pkg-config module ${pc_name}"

if ! guest_ssh_exec "${evidence}/pkg-config-version.txt" "${evidence}/pkg-config.stderr" \
        "pkg-config --modversion ${pc_name}"; then
    status="pkg-config-failed"; exit 1
fi
pkg_config_version="$(tr -d '\r\n' < "${evidence}/pkg-config-version.txt")"

guest_ssh_exec "${evidence}/development-headers.txt" "${evidence}/headers.stderr" \
    "dpkg -L ${probe_package} | grep '\.h\$' | head -20" || true
header="$(head -1 "${evidence}/development-headers.txt" | tr -d '\r\n')"
if [ -z "$header" ]; then
    status="development-headers-absent"; exit 1
fi

# The probe includes the installed header, links through pkg-config's own flags,
# and runs. --no-as-needed keeps the library in the binary's dependency list even
# when the probe calls nothing from it, so the link is proved rather than elided.
probe_source="#include <$(printf '%s' "$header" | sed 's#^/usr/include/##')>
int main(void) { return 0; }"
if ! guest_ssh_exec "${evidence}/probe-compile.stdout" "${evidence}/probe-compile.stderr" \
        "cd /tmp && printf '%s\n' '${probe_source}' > probe.c && cc -c probe.c \$(pkg-config --cflags ${pc_name}) -o probe.o"; then
    status="development-probe-compile-failed"; exit 1
fi
probe_compiled=true

if ! guest_ssh_exec "${evidence}/probe-link.stdout" "${evidence}/probe-link.stderr" \
        "cd /tmp && cc probe.c \$(pkg-config --cflags --libs ${pc_name}) -Wl,--no-as-needed -o probe"; then
    status="development-probe-link-failed"; exit 1
fi
probe_linked=true

guest_ssh_exec "${evidence}/probe-ldd.txt" "${evidence}/probe-ldd.stderr" \
    "ldd /tmp/probe || true" || true
if ! guest_ssh_exec "${evidence}/probe-run.stdout" "${evidence}/probe-run.stderr" \
        "/tmp/probe && echo probe-exited-zero"; then
    status="development-probe-run-failed"; exit 1
fi
probe_ran=true

status="passed"
exit 0
