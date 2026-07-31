#!/bin/bash
# Execute one checked builder plan through the guest SSH boundary.
#
# The host-side resolver supplies a bounded package schedule, but only the
# guest's APT can say what its installed state permits.  Each round therefore
# simulates its exact planned request before it installs, writes both command
# streams to the run directory, flushes the guest filesystem, and restarts the
# guest.  A failed simulation, an APT failure, or a Mach IPC allocation error
# stops later rounds and leaves the disposable overlay for inspection.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/execute-builder-batches.sh --plan PATH --journal PATH --run-dir PATH [--final-halt]
EOF
    exit 2
}

plan=""
journal=""
run_dir=""
final_halt=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --plan) plan="$2"; shift 2 ;;
        --journal) journal="$2"; shift 2 ;;
        --run-dir) run_dir="$2"; shift 2 ;;
        --final-halt) final_halt=1; shift ;;
        *) usage ;;
    esac
done

[ -n "$plan" ] && [ -n "$journal" ] && [ -n "$run_dir" ] || usage
[ -f "$plan" ] || { printf 'builder batch executor: no plan at %s\n' "$plan" >&2; exit 1; }
[ -f "$journal" ] || { printf 'builder batch executor: no journal at %s\n' "$journal" >&2; exit 1; }
[ -d "$run_dir" ] || { printf 'builder batch executor: no run directory at %s\n' "$run_dir" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || { printf 'builder batch executor: jq is required\n' >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { printf 'builder batch executor: sha256sum is required\n' >&2; exit 1; }

script_dir="$(cd "$(dirname "$0")" && pwd)"
# The executor runs root package commands.  The base has the same test key for
# root and builder, but builder has no passwordless privilege and cannot make a
# package transaction or restart the guest.
export GUEST_SSH_HOST="${GUEST_SSH_HOST:-127.0.0.1}"
export GUEST_SSH_PORT="${GUEST_SSH_PORT:-${BUILDER_SSH_PORT:-2223}}"
export GUEST_SSH_USER="${GUEST_SSH_USER:-root}"
export GUEST_SSH_KEY="${GUEST_SSH_KEY:-ssh-test-keys/hurd_test_key}"
export GUEST_SSH_TIMEOUT="${GUEST_SSH_TIMEOUT:-20}"
export GUEST_KNOWN_HOSTS="${GUEST_KNOWN_HOSTS:-${run_dir}/known_hosts}"
source "${script_dir}/lib/guest-ssh.sh"

artifact_dir="${run_dir}/artifacts"
mkdir -p "$artifact_dir"

timestamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }
digest() { sha256sum "$1" | awk '{ print $1 }'; }

wait_for_guest() {
    local limit="$1" deadline remaining sleep_seconds
    deadline=$((SECONDS + limit))
    while [ "$SECONDS" -lt "$deadline" ]; do
        if guest_ssh_alive; then
            return 0
        fi
        remaining=$((deadline - SECONDS))
        [ "$remaining" -gt 0 ] || break
        sleep_seconds=5
        if [ "$remaining" -lt "$sleep_seconds" ]; then
            sleep_seconds="$remaining"
        fi
        sleep "$sleep_seconds"
    done
    return 1
}

wait_for_guest_down() {
    local limit="$1" deadline remaining sleep_seconds
    deadline=$((SECONDS + limit))
    while [ "$SECONDS" -lt "$deadline" ]; do
        if ! guest_ssh_alive; then
            return 0
        fi
        remaining=$((deadline - SECONDS))
        [ "$remaining" -gt 0 ] || break
        sleep_seconds=5
        if [ "$remaining" -lt "$sleep_seconds" ]; then
            sleep_seconds="$remaining"
        fi
        sleep "$sleep_seconds"
    done
    return 1
}

run_guest_command() {
    local stdout_path="$1" stderr_path="$2" command="$3" status
    if guest_ssh_exec "$stdout_path" "$stderr_path" "$command"; then
        status=0
    else
        status=$?
    fi
    printf '%s' "$status"
}

mach_error_artifact() {
    local prefix="$1" output_path="$2" error_path="$3" matches
    matches="${artifact_dir}/${prefix}-mach-ipc-matches.txt"
    grep -Ein 'mach.*(ipc|vm).*allocat|allocat.*mach.*(ipc|vm)|ipc.*allocat' \
        "$output_path" "$error_path" >"$matches" || true
    printf '%s' "$(basename "$matches")"
}

append_record() {
    local record_path="$1"
    python3 "${script_dir}/write-builder-batch-journal.py" --plan "$plan" \
        --journal "$journal" --append-record "$record_path"
}

if ! wait_for_guest "${BUILDER_SSH_READY_TIMEOUT:-600}"; then
    printf 'builder batch executor: root SSH did not become ready within %ss\n' \
        "${BUILDER_SSH_READY_TIMEOUT:-600}" >&2
    exit 1
fi

batch_count="$(jq '.batches | length' "$plan")"
for batch_index in $(seq 0 "$((batch_count - 1))"); do
    batch="$(jq -c ".batches[${batch_index}]" "$plan")"
    batch_id="$(jq -r '.batch_id' <<<"$batch")"
    record_prefix="$(printf '%03d' "$(jq -r '.batch_index' <<<"$batch")")"
    simulation_command="$(jq -r '.guest_pre_batch_simulation.command | join(" ")' <<<"$batch")"
    install_command="$(jq -r '.guest_pre_batch_simulation.command | map(select(. != "-s")) | join(" ")' <<<"$batch")"
    simulation_execution_command="DEBIAN_FRONTEND=noninteractive ${simulation_command}"
    install_execution_command="DEBIAN_FRONTEND=noninteractive ${install_command}"
    simulation_stdout="${artifact_dir}/${record_prefix}-simulation.stdout"
    simulation_stderr="${artifact_dir}/${record_prefix}-simulation.stderr"
    install_stdout="${artifact_dir}/${record_prefix}-install.stdout"
    install_stderr="${artifact_dir}/${record_prefix}-install.stderr"
    sync_stdout="${artifact_dir}/${record_prefix}-sync.stdout"
    sync_stderr="${artifact_dir}/${record_prefix}-sync.stderr"
    reboot_stdout="${artifact_dir}/${record_prefix}-reboot.stdout"
    reboot_stderr="${artifact_dir}/${record_prefix}-reboot.stderr"
    record_path="${artifact_dir}/${record_prefix}-record.json"
    started_at="$(timestamp)"
    for stream_path in "$simulation_stdout" "$simulation_stderr" \
        "$install_stdout" "$install_stderr" "$sync_stdout" "$sync_stderr" \
        "$reboot_stdout" "$reboot_stderr"; do
        : >"$stream_path"
    done

    simulation_status="$(run_guest_command "$simulation_stdout" "$simulation_stderr" "$simulation_execution_command")"
    simulation_done="$(timestamp)"
    simulation_matches="$(mach_error_artifact "${record_prefix}-simulation" "$simulation_stdout" "$simulation_stderr")"
    simulation_match_count="$(wc -l <"${artifact_dir}/${simulation_matches}")"
    simulation_count="$(grep -c '^Inst ' "$simulation_stdout" || true)"

    if [ "$simulation_status" -ne 0 ] || [ "$simulation_match_count" -ne 0 ]; then
        jq -n --argjson batch "$batch" --arg started "$started_at" --arg completed "$simulation_done" \
            --arg command "$simulation_command" --arg stdout "$(digest "$simulation_stdout")" \
            --arg stderr "$(digest "$simulation_stderr")" --arg matches "$simulation_matches" \
            --argjson status "$simulation_status" --argjson count "$simulation_count" \
            --argjson match_count "$simulation_match_count" '
            ($batch | {
                batch_id, batch_index, members,
                started_at_utc: $started,
                outcome: "simulation-failed",
                pre_batch_simulation: {
                    command: ($command | split(" ")),
                    completed_at_utc: $completed,
                    exit_status: $status,
                    stdout_sha256: $stdout,
                    stderr_sha256: $stderr,
                    simulated_package_count: $count,
                    mach_ipc_allocation_error: {observed: ($match_count > 0), artifact: $matches}
                },
                install: {not_run_reason: "simulation-failed"},
                sync: {not_run_reason: "simulation-failed"},
                reboot: {not_run_reason: "simulation-failed"}
            })' >"$record_path"
        append_record "$record_path"
        printf 'builder batch executor: %s simulation failed or reported a Mach IPC allocation error\n' "$batch_id" >&2
        exit 1
    fi

    install_status="$(run_guest_command "$install_stdout" "$install_stderr" "$install_execution_command")"
    install_done="$(timestamp)"
    install_matches="$(mach_error_artifact "${record_prefix}-install" "$install_stdout" "$install_stderr")"
    install_match_count="$(wc -l <"${artifact_dir}/${install_matches}")"
    if [ "$install_status" -ne 0 ] || [ "$install_match_count" -ne 0 ]; then
        sync_status=-1
        sync_done="$install_done"
        reboot_status=-1
        reboot_done="$install_done"
        outcome="install-failed"
    else
        sync_status="$(run_guest_command "$sync_stdout" "$sync_stderr" 'sync')"
        sync_done="$(timestamp)"
        if [ "$sync_status" -ne 0 ]; then
            reboot_status=-1
            reboot_done="$sync_done"
            outcome="sync-failed"
        else
            reboot_status="$(run_guest_command "$reboot_stdout" "$reboot_stderr" 'sync; /sbin/reboot')"
            reboot_done="$(timestamp)"
            if wait_for_guest_down "${BUILDER_SSH_REBOOT_DOWN_TIMEOUT:-120}" && \
                    wait_for_guest "${BUILDER_SSH_READY_TIMEOUT:-600}"; then
                outcome="completed"
            else
                outcome="reboot-failed"
            fi
        fi
    fi

    jq -n --argjson batch "$batch" --arg started "$started_at" --arg simulation_done "$simulation_done" \
        --arg simulation_command "$simulation_command" --arg simulation_stdout "$(digest "$simulation_stdout")" \
        --arg simulation_stderr "$(digest "$simulation_stderr")" --arg simulation_matches "$simulation_matches" \
        --arg install_done "$install_done" --arg install_command "$install_command" \
        --arg install_stdout "$(digest "$install_stdout")" --arg install_stderr "$(digest "$install_stderr")" \
        --arg install_matches "$install_matches" --arg sync_done "$sync_done" \
        --arg sync_stdout "$(digest "$sync_stdout")" --arg sync_stderr "$(digest "$sync_stderr")" \
        --arg reboot_done "$reboot_done" --arg reboot_stdout "$(digest "$reboot_stdout")" \
        --arg reboot_stderr "$(digest "$reboot_stderr")" --arg outcome "$outcome" \
        --argjson simulation_status "$simulation_status" --argjson simulation_count "$simulation_count" \
        --argjson simulation_match_count "$simulation_match_count" --argjson install_status "$install_status" \
        --argjson install_match_count "$install_match_count" --argjson sync_status "$sync_status" \
        --argjson reboot_status "$reboot_status" '
        ($batch | {
            batch_id, batch_index, members,
            started_at_utc: $started,
            outcome: $outcome,
            pre_batch_simulation: {
                command: ($simulation_command | split(" ")),
                completed_at_utc: $simulation_done,
                exit_status: $simulation_status,
                stdout_sha256: $simulation_stdout,
                stderr_sha256: $simulation_stderr,
                simulated_package_count: $simulation_count,
                mach_ipc_allocation_error: {observed: ($simulation_match_count > 0), artifact: $simulation_matches}
            },
            install: {
                command: ($install_command | split(" ")),
                completed_at_utc: $install_done,
                exit_status: $install_status,
                stdout_sha256: $install_stdout,
                stderr_sha256: $install_stderr,
                mach_ipc_allocation_error: {observed: ($install_match_count > 0), artifact: $install_matches}
            },
            sync: {
                command: ["sync"], completed_at_utc: $sync_done, exit_status: $sync_status,
                stdout_sha256: $sync_stdout, stderr_sha256: $sync_stderr
            },
            reboot: {
                command: ["/sbin/reboot"], completed_at_utc: $reboot_done,
                request_exit_status: $reboot_status
            }
        })' >"$record_path"
    append_record "$record_path"
    if [ "$outcome" != "completed" ]; then
        printf 'builder batch executor: %s %s\n' "$batch_id" "$outcome" >&2
        exit 1
    fi
done

# Every round exiting zero says APT reported no failure. It does not say the
# dpkg database is consistent, nor that the rounds together satisfied the whole
# planned transaction, because each round only ever simulated its own members.
# One simulation over every planned member answers both: a consistent database
# and a transaction with nothing left to install.
verify_stdout="${artifact_dir}/final-verification.stdout"
verify_stderr="${artifact_dir}/final-verification.stderr"
audit_stdout="${artifact_dir}/final-dpkg-audit.stdout"
audit_stderr="${artifact_dir}/final-dpkg-audit.stderr"
count_stdout="${artifact_dir}/final-package-count.stdout"
count_stderr="${artifact_dir}/final-package-count.stderr"

all_members="$(jq -r '[.batches[].members[].package] | join(" ")' "$plan")"
verify_status="$(run_guest_command "$verify_stdout" "$verify_stderr" \
    "DEBIAN_FRONTEND=noninteractive apt-get -s install -y --no-install-recommends ${all_members}")"
audit_status="$(run_guest_command "$audit_stdout" "$audit_stderr" 'dpkg -C')"
count_status="$(run_guest_command "$count_stdout" "$count_stderr" \
    "dpkg-query -f '\${binary:Package}\\n' -W | wc -l")"

remaining="$(grep -c '^Inst ' "$verify_stdout" || true)"
installed_total="$(tr -dc '0-9' <"$count_stdout")"

jq -n --arg command "apt-get -s install -y --no-install-recommends" \
    --argjson verify_status "$verify_status" --argjson audit_status "$audit_status" \
    --argjson count_status "$count_status" --argjson remaining "$remaining" \
    --arg installed_total "${installed_total:-}" \
    --arg verify_stdout "$(digest "$verify_stdout")" \
    --arg audit_stdout "$(digest "$audit_stdout")" '{
        kind: "builder-batch-final-verification",
        transaction_simulation: {
            command: $command, exit_status: $verify_status,
            remaining_to_install: $remaining, stdout_sha256: $verify_stdout
        },
        dpkg_audit: {command: "dpkg -C", exit_status: $audit_status,
                     stdout_sha256: $audit_stdout},
        installed_packages: {command: "dpkg-query -W", exit_status: $count_status,
                             total: $installed_total}
    }' >"${artifact_dir}/final-verification.json"

# `dpkg -C` exits zero and prints nothing when every package is fully installed,
# so a non-empty stdout is a finding even where the exit status is not.
verification_failed=0
[ "$verify_status" -eq 0 ] || verification_failed=1
[ "$audit_status" -eq 0 ] || verification_failed=1
[ "$remaining" -eq 0 ] || verification_failed=1
[ ! -s "$audit_stdout" ] || verification_failed=1

if [ "$final_halt" -eq 1 ]; then
    final_stdout="${artifact_dir}/final-halt.stdout"
    final_stderr="${artifact_dir}/final-halt.stderr"
    run_guest_command "$final_stdout" "$final_stderr" 'sync; halt' >/dev/null || true
fi

if [ "$verification_failed" -ne 0 ]; then
    printf 'builder batch executor: the completed rounds leave %s packages to install, dpkg audit exit %s, simulation exit %s\n' \
        "$remaining" "$audit_status" "$verify_status" >&2
    exit 1
fi
