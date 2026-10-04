#!/bin/bash
# Drive one unmodified source-package build in a prepared guest and bring its
# artifacts back to the host.
#
# The build itself runs inside the guest as the unprivileged `builder` account
# from a script copied out of the recorded commit, because a root heredoc that
# changes user midway is reparsed by two shells and the command the evidence
# records stops being the command that ran. This file owns the transport, the
# request identity, and the artifact retrieval; the guest script owns the build.
#
# The request permits no local patch. A build that succeeds only after an
# unrecorded change describes a source tree that does not exist, so a nonzero
# result is a classified outcome the caller keeps rather than a reason to retry
# with different arguments.

set -euo pipefail

request=""
run_dir=""
while [ $# -gt 0 ]; do
    case "$1" in
        --request) request="$2"; shift 2 ;;
        --run-dir) run_dir="$2"; shift 2 ;;
        *) printf 'source build: unknown argument %s\n' "$1" >&2; exit 2 ;;
    esac
done
[ -n "$request" ] && [ -f "$request" ] || {
    printf 'source build: --request naming an existing file is required\n' >&2; exit 2; }
[ -n "$run_dir" ] && [ -d "$run_dir" ] || {
    printf 'source build: --run-dir naming an existing directory is required\n' >&2; exit 2; }

command -v jq >/dev/null 2>&1 || { printf 'source build: jq is required\n' >&2; exit 2; }

script_dir="$(cd "$(dirname "$0")" && pwd)"
export GUEST_SSH_HOST="${GUEST_SSH_HOST:-127.0.0.1}"
export GUEST_SSH_PORT="${GUEST_SSH_PORT:-${BUILDER_SSH_PORT:-2223}}"
export GUEST_SSH_KEY="${GUEST_SSH_KEY:-ssh-test-keys/hurd_test_key}"
export GUEST_KNOWN_HOSTS="${GUEST_KNOWN_HOSTS:-${run_dir}/known_hosts}"
export GUEST_SSH_USER="root"
# shellcheck source=scripts/lib/guest-ssh.sh
source "${script_dir}/lib/guest-ssh.sh"

log() { printf 'source build: %s\n' "$*" >&2; }

source_name="$(jq -r '.source' "$request")"
source_version="$(jq -r '.version' "$request")"
build_user="$(jq -r '.build_user // "builder"' "$request")"
parallelism="$(jq -r '.build_parallelism // 1' "$request")"
request_sha="$(sha256sum "$request" | cut -d' ' -f1)"

[ -n "$source_name" ] && [ "$source_name" != "null" ] || { log "the request names no source"; exit 2; }
[ -n "$source_version" ] && [ "$source_version" != "null" ] || { log "the request names no version"; exit 2; }

# Every one of these fields reaches a guest root or build-user shell command as
# an interpolated string rather than an argv element, because the transport is
# ssh's single command-string argument. A value outside the grammar its field
# describes is refused here, before any command is assembled, rather than
# trusted to survive quoting inside one.
if ! printf '%s' "$source_name" | grep -Eq '^[a-z0-9][a-z0-9+.-]*$'; then
    log "source name '${source_name}' is not a Debian source-package name"; exit 2
fi
if ! printf '%s' "$source_version" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9.+~:-]*$'; then
    log "version '${source_version}' is not a Debian version"; exit 2
fi
if ! printf '%s' "$build_user" | grep -Eq '^[a-z_][a-z0-9_-]{0,31}$'; then
    log "build user '${build_user}' is not a conservative account name"; exit 2
fi
if ! printf '%s' "$parallelism" | grep -Eq '^[1-9][0-9]?$'; then
    log "parallelism '${parallelism}' is not an integer from 1 to 99"; exit 2
fi

# A request that carries a patch list is refused rather than silently ignored,
# because the artifact manifest would otherwise describe an unmodified build of
# a modified tree.
patches="$(jq -r '(.local_patches // []) | length' "$request")"
if [ "$patches" != "0" ]; then
    log "the request names ${patches} local patch(es); the first build of a source is unmodified"
    exit 2
fi

evidence="${run_dir}/artifacts"
mkdir -p "$evidence"
serial="${run_dir}/serial.log"
guest_script="${script_dir}/guest/build-source-package.sh"
[ -f "$guest_script" ] || { log "no guest build script at ${guest_script}"; exit 2; }

serial_offset() {
    if [ -f "$serial" ]; then wc -c <"$serial" | tr -d ' '; else printf '0'; fi
}

scp_options() {
    local options
    mapfile -t options < <(guest_ssh_options)
    # scp names the port with -P where ssh uses -p.
    printf '%s\n' "${options[@]}" | sed 's/^-p$/-P/'
}

mapfile -t transfer < <(scp_options)

log "copying the guest build stage from the recorded commit"
scp "${transfer[@]}" "$guest_script" \
    "root@${GUEST_SSH_HOST}:/usr/local/sbin/build-source-package.sh" >/dev/null

# The build account owns its own work, so the transport prepares ownership and
# then stops acting as root.
guest_ssh_exec "${evidence}/build-prepare.stdout" "${evidence}/build-prepare.stderr" \
    "chmod 0755 /usr/local/sbin/build-source-package.sh && install -d -o ${build_user} -g ${build_user} /home/${build_user}/build /home/${build_user}/out"

start_offset="$(serial_offset)"
started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

GUEST_SSH_USER="$build_user"
export GUEST_SSH_USER
log "building ${source_name} ${source_version} as ${build_user}"
build_status=0
guest_ssh_exec "${evidence}/guest-build.stdout" "${evidence}/guest-build.stderr" \
    "/usr/local/sbin/build-source-package.sh --source '${source_name}' --version '${source_version}' --parallelism '${parallelism}' --output /home/${build_user}/out" \
    || build_status=$?

end_offset="$(serial_offset)"
finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

log "retrieving whatever the build produced"
mkdir -p "${evidence}/package"
scp "${transfer[@]}" -r "${build_user}@${GUEST_SSH_HOST}:/home/${build_user}/out/." \
    "${evidence}/package/" >/dev/null 2>&1 || log "no build output directory to retrieve"

# The console interval belongs to this build rather than to the run, so the
# falsifier is attributed to the workload that provoked it.
MACH_IPC_PATTERN='mach.*(ipc|vm).*allocat|allocat.*mach.*(ipc|vm)|ipc.*allocat'
MACH_KERNEL_OUTPUT='^[[:space:]]*(module [0-9]+:|timer calibration|IOAPIC .* configured with GSI|APIC entry=|IRQ override:|RTC time is)'
console_matches=0
console_observable=false
if [ -f "$serial" ]; then
    grep -qE "$MACH_KERNEL_OUTPUT" "$serial" && console_observable=true
    console_matches="$(tail -c "+$((start_offset + 1))" "$serial" \
        | grep -cEi "$MACH_IPC_PATTERN" || true)"
    tail -c "+$((start_offset + 1))" "$serial" >"${evidence}/build-console.log" || true
fi

outcome="completed"
if [ "$build_status" -ne 0 ]; then
    outcome="$(jq -r '.outcome // "build-failed"' \
        "${evidence}/package/build-result.json" 2>/dev/null || echo build-failed)"
fi
if [ "$console_matches" != "0" ]; then
    outcome="mach-ipc-allocation-error"
fi

cat > "${run_dir}/build-run.json" <<EOF
{
  "schema_version": 1,
  "kind": "hurd-native-source-build-run",
  "request": "$(basename "$request")",
  "request_sha256": "${request_sha}",
  "source": "${source_name}",
  "version": "${source_version}",
  "build_user": "${build_user}",
  "outcome": "${outcome}",
  "guest_exit_status": ${build_status},
  "started_at_utc": "${started}",
  "finished_at_utc": "${finished}",
  "guest_console": {
    "transcript": "serial.log",
    "kernel_output_observed": ${console_observable},
    "build_start_offset": ${start_offset},
    "build_end_offset": ${end_offset},
    "mach_ipc_allocation_error": $( [ "$console_observable" = true ] && { [ "$console_matches" = "0" ] && echo false || echo true; } || echo null )
  },
  "artifact_directory": "artifacts/package"
}
EOF

log "outcome ${outcome}"
[ "$outcome" = "completed" ] || exit 1
exit 0
