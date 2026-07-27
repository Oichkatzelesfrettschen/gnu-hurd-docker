# shellcheck shell=bash
# GUEST_SSH_REMOTE_STATUS and GUEST_SSH_TRANSPORT_STATUS are the result of the
# last guest_ssh_exec and are read by the sourcing script, which ShellCheck
# cannot see from inside this file.
# shellcheck disable=SC2034
# One SSH transport for every mechanism that reads the guest.
#
# The baseline collector and the package-state exporter each grew their own
# connection: different default hosts, different variable names for the same
# port, and host-key verification present in one and conditional in the other.
# Two transports mean a run can be reachable for one artifact and refused for
# another, and the evidence then reports a guest fact that is really a
# configuration difference between two scripts.
#
# ssh reports its own failures as 255 and passes the remote command's status
# through otherwise, so a bare 255 does not say whether the guest answered. A
# probe that fails with 255 is followed by a liveness connection: an answer
# proves the transport survived and the 255 came from the remote command, and a
# refusal proves the transport is gone. The two are recorded as separate fields
# because "the guest did not answer" is a claim about the guest and a nonzero
# command status is a claim about the query.

GUEST_SSH_HOST="${GUEST_SSH_HOST:-127.0.0.1}"
GUEST_SSH_PORT="${GUEST_SSH_PORT:-${MINTY_SSH_PORT:-${SSH_PORT:-2222}}}"
GUEST_SSH_USER="${GUEST_SSH_USER:-root}"
GUEST_SSH_KEY="${GUEST_SSH_KEY:-${MINTY_SSH_KEY:-ssh-test-keys/hurd_test_key}}"
GUEST_SSH_TIMEOUT="${GUEST_SSH_TIMEOUT:-20}"

# A disposable guest presents a key nobody has seen before, so strict checking
# refuses it and disabling the check accepts any host for every later
# connection. accept-new against a per-run file records the key on first contact
# and verifies it on every connection afterwards, which is the property that
# makes two artifacts from one run comparable.
GUEST_KNOWN_HOSTS="${GUEST_KNOWN_HOSTS:-}"

GUEST_SSH_REMOTE_STATUS=""
GUEST_SSH_TRANSPORT_STATUS=0

guest_ssh_options() {
    local options=(
        -i "$GUEST_SSH_KEY"
        -p "$GUEST_SSH_PORT"
        -o BatchMode=yes
        -o "ConnectTimeout=${GUEST_SSH_TIMEOUT}"
    )
    if [ -n "$GUEST_KNOWN_HOSTS" ]; then
        options+=(-o StrictHostKeyChecking=accept-new
                  -o "UserKnownHostsFile=${GUEST_KNOWN_HOSTS}")
    fi
    printf '%s\n' "${options[@]}"
}

guest_ssh_alive() {
    local options
    mapfile -t options < <(guest_ssh_options)
    ssh "${options[@]}" "${GUEST_SSH_USER}@${GUEST_SSH_HOST}" 'exit 0' \
        >/dev/null 2>&1
}

# Run one command and keep both streams. The remote side writes to the named
# files directly rather than through a variable, because a command substitution
# strips trailing newlines and an artifact that lost them no longer matches the
# digest a later run computes over the same guest output.
guest_ssh_exec() {
    local stdout_path="$1" stderr_path="$2" command="$3"
    local status=0 options
    mapfile -t options < <(guest_ssh_options)

    ssh "${options[@]}" "${GUEST_SSH_USER}@${GUEST_SSH_HOST}" "$command" \
        >"$stdout_path" 2>"$stderr_path" || status=$?

    GUEST_SSH_REMOTE_STATUS="$status"
    GUEST_SSH_TRANSPORT_STATUS=0
    if [ "$status" -eq 255 ]; then
        if guest_ssh_alive; then
            GUEST_SSH_TRANSPORT_STATUS=0
        else
            GUEST_SSH_TRANSPORT_STATUS=255
            GUEST_SSH_REMOTE_STATUS=""
        fi
    fi
    return "$status"
}

# The fingerprint identifies the host the artifacts came from. Reading it from
# the run's own known_hosts is what binds every artifact in the run to one
# guest, where a host and port alone name a socket that anything can hold.
guest_ssh_host_fingerprint() {
    [ -n "$GUEST_KNOWN_HOSTS" ] && [ -f "$GUEST_KNOWN_HOSTS" ] || return 0
    ssh-keygen -lf "$GUEST_KNOWN_HOSTS" 2>/dev/null \
        | awk '{ print $2 }' | head -1
}
