#!/bin/bash
# Collect one guest's baseline in a single boot, one probe at a time.
#
# Every closure verdict this repository holds was resolved against an empty dpkg
# status file, so a report says what the archive permits on an empty system
# rather than what this image would accept. The status file is what closes that,
# and a boot is expensive enough that collecting one artifact from it wastes the
# other dozen.
#
# A probe is a command, its exit status, both of its streams, and the digests of
# each. Reducing that to a single output file conflates three different
# outcomes: the guest was unreachable, the query was refused, and the query
# answered that a file is absent. A composite command makes it worse -- `cat a b`
# exits nonzero when either operand is missing after emitting the other, so a
# valid answer is overwritten by a failure marker. Each probe therefore reads one
# thing, and the record says which of the outcomes occurred.
#
# The command reaches the guest through one more shell than it was written in:
# ssh concatenates its arguments and the remote shell reparses the result. A
# dpkg-query format string written for the local shell arrives at the remote one
# as a parameter expansion -- bash silently expands `${binary:Package}` to the
# empty string and dash refuses it outright -- so every probe body is a quoted
# heredoc that neither shell rewrites.
#
# Nothing here mutates the canonical image: the caller boots a disposable
# overlay, and this script only reads. The one write it makes is to the host's
# output directory.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/guest-ssh.sh
. "${REPO_ROOT}/scripts/lib/guest-ssh.sh"

OUT="${OUTPUT_DIR:-evidence/guest-state}"
GUEST_KNOWN_HOSTS="${GUEST_KNOWN_HOSTS:-${OUT}/.known_hosts}"
export GUEST_KNOWN_HOSTS

log() { printf '%s\n' "$*" >&2; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
digest() { sha256sum "$1" | cut -d' ' -f1; }

# Values reach the manifest as JSON through a serializer rather than through
# string concatenation, because a probe body carries quotes and newlines and a
# hand-built object would either lose them or produce something no parser reads.
json_string() {
    python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.stdin.read()))'
}

mkdir -p "$OUT"
records="$(mktemp)"
scratch="$(mktemp -d)"
trap 'rm -rf "$records" "$scratch"' EXIT

REQUIRED_FAILED=0
OPTIONAL_FAILED=0

# A probe body that exits 66 states that the thing it reads is absent. dpkg
# reserves no status in that range and no probe here can produce it by accident,
# so the guest reporting an absence and the guest refusing a query stay
# distinguishable in the record.
ABSENT=66

emit_record() {
    local name="$1" requirement="$2" command="$3" class="$4"
    local remote_status="$5" transport_status="$6"
    local stdout_name="$7" stdout_digest="$8"
    local stderr_name="$9" stderr_digest="${10}"
    local started="${11}" ended="${12}"

    {
        printf '{"name":'
        printf '%s' "$name" | json_string
        printf ',"requirement":'
        printf '%s' "$requirement" | json_string
        printf ',"command":'
        printf '%s' "$command" | json_string
        printf ',"class":'
        printf '%s' "$class" | json_string
        printf ',"remote_status":%s' \
            "${remote_status:-null}"
        printf ',"transport_status":%s' "$transport_status"
        printf ',"started_at":'
        printf '%s' "$started" | json_string
        printf ',"ended_at":'
        printf '%s' "$ended" | json_string
        printf ',"stdout":'
        printf '%s' "$stdout_name" | json_string
        printf ',"stdout_sha256":'
        printf '%s' "$stdout_digest" | json_string
        if [ -n "$stderr_name" ]; then
            printf ',"stderr":'
            printf '%s' "$stderr_name" | json_string
            printf ',"stderr_sha256":'
            printf '%s' "$stderr_digest" | json_string
        else
            printf ',"stderr":null,"stderr_sha256":null'
        fi
        printf '}\n'
    } >>"$records"
}

count_failure() {
    local requirement="$1"
    if [ "$requirement" = required ]; then
        REQUIRED_FAILED=$((REQUIRED_FAILED + 1))
    else
        OPTIONAL_FAILED=$((OPTIONAL_FAILED + 1))
    fi
}

# probe <name> <required|optional>, body on stdin.
probe() {
    local name="$1" requirement="$2"
    local command started ended status class
    local stdout_path="${OUT}/${name}.txt"
    local stderr_path="${scratch}/${name}.err"
    local stderr_name="" stderr_digest=""

    command="$(cat)"
    started="$(now)"
    status=0
    guest_ssh_exec "$stdout_path" "$stderr_path" "$command" || status=$?
    ended="$(now)"

    if [ "$GUEST_SSH_TRANSPORT_STATUS" -ne 0 ]; then
        class=unreachable
        count_failure "$requirement"
    elif [ "$status" -eq 0 ]; then
        class=observed
    elif [ "$status" -eq "$ABSENT" ]; then
        class=observed-absent
    elif [ -s "$stdout_path" ]; then
        class=partial
        count_failure "$requirement"
    else
        class=failed
        count_failure "$requirement"
    fi

    # An empty stderr file carries nothing a reader can act on, so it is not
    # advertised and not committed. A nonempty one is the only place a refusal
    # explains itself, so it is kept beside the stdout it belongs to.
    if [ -s "$stderr_path" ]; then
        stderr_name="${name}.err"
        cp "$stderr_path" "${OUT}/${stderr_name}"
        stderr_digest="$(digest "${OUT}/${stderr_name}")"
    else
        rm -f "${OUT}/${name}.err"
    fi

    emit_record "$name" "$requirement" "$command" "$class" \
        "$GUEST_SSH_REMOTE_STATUS" "$GUEST_SSH_TRANSPORT_STATUS" \
        "${name}.txt" "$(digest "$stdout_path")" \
        "$stderr_name" "$stderr_digest" "$started" "$ended"

    log "${class}: ${name}"
}

started_at="$(now)"

# The status export and the image it was read from are one fact. A collection
# that starts with no image identity produces a package list from somewhere,
# so the digest is refused before the guest is ever contacted rather than
# caught by the checker after the boot was spent.
if ! printf '%s' "${GUEST_IMAGE_SHA256:-}" | grep -Eq '^[0-9a-f]{64}$'; then
    log "not run: GUEST_IMAGE_SHA256 is ${GUEST_IMAGE_SHA256:-empty}, not a sha256 digest of the booted image"
    exit 2
fi

if ! guest_ssh_alive; then
    log "not run: the guest did not answer on ${GUEST_SSH_HOST}:${GUEST_SSH_PORT}"
    exit 2
fi

# apt reads installed state as RFC822 paragraphs, so the status export is a
# separate mechanism with its own validation. It is also the artifact this
# collection exists to produce: an inventory probe may be partial and the run
# still answers its question, and a missing status file leaves nothing to seed a
# resolver with. Its failure is therefore a failure of the collection.
export_started="$(now)"
export_status=0
#
# GUEST_IMAGE_SHA256 is the digest of the image the caller booted. It reaches
# the export unchanged, because the status file and the image it was read from
# are one fact and a manifest that names neither cannot be matched to a run.
GUEST_SSH_KEY="$GUEST_SSH_KEY" GUEST_SSH_PORT="$GUEST_SSH_PORT" \
    GUEST_SSH_USER="$GUEST_SSH_USER" GUEST_SSH_HOST="$GUEST_SSH_HOST" \
    GUEST_KNOWN_HOSTS="$GUEST_KNOWN_HOSTS" OUTPUT_DIR="$OUT" \
    GUEST_IMAGE_SHA256="${GUEST_IMAGE_SHA256:-}" \
    "${REPO_ROOT}/scripts/export-guest-package-state.sh" \
    >"${scratch}/export.out" 2>"${scratch}/export.err" || export_status=$?
export_ended="$(now)"
if [ "$export_status" -ne 0 ]; then
    REQUIRED_FAILED=$((REQUIRED_FAILED + 1))
    log "failed: package-state export exited ${export_status}"
    cat "${scratch}/export.err" >&2
else
    log "observed: package-state export"
fi

probe uname required <<'PROBE'
uname -a
PROBE

probe nproc required <<'PROBE'
nproc
PROBE

probe debian_version required <<'PROBE'
cat /etc/debian_version
PROBE

probe dpkg-architecture required <<'PROBE'
dpkg --print-architecture
PROBE

probe apt-version optional <<'PROBE'
apt-get --version
PROBE

probe dpkg-version optional <<'PROBE'
dpkg --version
PROBE

probe apt-sources optional <<'PROBE'
[ -e /etc/apt/sources.list ] || exit 66
cat /etc/apt/sources.list
PROBE

# A directory walk reports an empty directory as an observation with status 0,
# where a glob that matches nothing is passed through literally and turns into a
# refusal that reads as a guest failure.
probe apt-sources-d optional <<'PROBE'
[ -d /etc/apt/sources.list.d ] || exit 66
for entry in /etc/apt/sources.list.d/*; do
    [ -e "$entry" ] || continue
    printf '### %s\n' "$entry"
    cat "$entry"
done
PROBE

probe apt-preferences optional <<'PROBE'
[ -e /etc/apt/preferences ] || exit 66
cat /etc/apt/preferences
PROBE

probe apt-preferences-d optional <<'PROBE'
[ -d /etc/apt/preferences.d ] || exit 66
for entry in /etc/apt/preferences.d/*; do
    [ -e "$entry" ] || continue
    printf '### %s\n' "$entry"
    cat "$entry"
done
PROBE

# A key in /etc/apt/trusted.gpg.d authenticates any source that names no
# Signed-By, so which keys sit there and which sources scope themselves is one
# fact about what the guest will accept as archive metadata.
probe apt-trusted-keys optional <<'PROBE'
[ -d /etc/apt/trusted.gpg.d ] || exit 66
ls -1 /etc/apt/trusted.gpg.d
PROBE

# dpkg-query renders its format string through the remote shell, so the body is
# a quoted heredoc and the package patterns are quoted against globbing in the
# guest's working directory.
probe kernel-packages optional <<'PROBE'
dpkg-query -W -f='${binary:Package}\t${Version}\n' 'gnumach-image-*' 'hurd'
PROBE

# dpkg-query exits nonzero when a pattern matches nothing, which turns "this
# package is not installed" into a refusal. Asking each name separately and
# printing the answer makes an absence an observation, which is what a build
# plan needs: mig missing is a fact about what this image can compile, not a
# failure of the query.
probe toolchain-packages optional <<'PROBE'
for name in mig gcc g++ make dpkg-dev build-essential binutils python3 \
        libc0.3-dev pkg-config; do
    version="$(dpkg-query -W -f='${Version}' "$name" 2>/dev/null || true)"
    printf '%s\t%s\n' "$name" "${version:-absent}"
done
PROBE

# A package inventory and an executable on PATH are different facts: a
# pkg-config command can be supplied by pkgconf, an alternative, or a manual
# install with no pkg-config package behind it. command -v settles capability
# where dpkg-query settles packaging, and both levels are recorded because a
# build plan needs the command and the archive repair needs the package name.
probe toolchain-commands optional <<'PROBE'
for name in mig pkg-config; do
    path="$(command -v "$name" 2>/dev/null || true)"
    printf '%s\t%s\n' "$name" "${path:-absent}"
done
PROBE

probe desktop-mode optional <<'PROBE'
[ -e /etc/hurd-desktop.mode ] || exit 66
cat /etc/hurd-desktop.mode
PROBE

probe desktop-session optional <<'PROBE'
[ -e /etc/hurd-desktop.session ] || exit 66
cat /etc/hurd-desktop.session
PROBE

probe df optional <<'PROBE'
df -h
PROBE

probe free optional <<'PROBE'
free -m
PROBE

ended_at="$(now)"

fingerprint="$(guest_ssh_host_fingerprint)"
collector_digest="$(digest "${BASH_SOURCE[0]}")"
transport_digest="$(digest "${REPO_ROOT}/scripts/lib/guest-ssh.sh")"
exporter_digest="$(digest "${REPO_ROOT}/scripts/export-guest-package-state.sh")"
commit="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo "")"

# The manifest names artifacts by their basename inside this directory. An
# absolute path would bind committed evidence to one machine's filesystem and
# put a local path in the tree, which the repository rules keep out.
{
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "kind": "guest-baseline-probes",\n'
    printf '  "started_at": %s,\n' "$(printf '%s' "$started_at" | json_string)"
    printf '  "ended_at": %s,\n' "$(printf '%s' "$ended_at" | json_string)"
    printf '  "repository_commit": %s,\n' "$(printf '%s' "$commit" | json_string)"
    printf '  "collector_sha256": %s,\n' \
        "$(printf '%s' "$collector_digest" | json_string)"
    printf '  "transport_sha256": %s,\n' \
        "$(printf '%s' "$transport_digest" | json_string)"
    printf '  "exporter_sha256": %s,\n' \
        "$(printf '%s' "$exporter_digest" | json_string)"
    printf '  "transport": {\n'
    printf '    "host": %s,\n' "$(printf '%s' "$GUEST_SSH_HOST" | json_string)"
    printf '    "port": %s,\n' "$GUEST_SSH_PORT"
    printf '    "user": %s,\n' "$(printf '%s' "$GUEST_SSH_USER" | json_string)"
    printf '    "host_key_fingerprint": %s\n' \
        "$(printf '%s' "$fingerprint" | json_string)"
    printf '  },\n'
    printf '  "package_state_export": {\n'
    printf '    "requirement": "required",\n'
    printf '    "status": %s,\n' "$export_status"
    printf '    "class": %s,\n' \
        "$([ "$export_status" -eq 0 ] && printf '"observed"' || printf '"failed"')"
    printf '    "started_at": %s,\n' \
        "$(printf '%s' "$export_started" | json_string)"
    printf '    "ended_at": %s\n' "$(printf '%s' "$export_ended" | json_string)"
    printf '  },\n'
    printf '  "probes": [\n'
    awk 'NR > 1 { printf ",\n" } { printf "    %s", $0 } END { printf "\n" }' \
        "$records"
    printf '  ]\n'
    printf '}\n'
} > "${OUT}/probes.json"

python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "${OUT}/probes.json" \
    || { log "the probe manifest is not parseable JSON"; exit 1; }

log "collection finished: ${REQUIRED_FAILED} required and ${OPTIONAL_FAILED} optional probe(s) short of observed, manifest at ${OUT}/probes.json"
[ "$REQUIRED_FAILED" -eq 0 ]
