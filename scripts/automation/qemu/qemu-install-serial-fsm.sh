#!/bin/bash
set -euo pipefail

# Serial-log-driven unattended installer monitor for QEMU.
# Avoids HMP screendump/OCR coupling by using SSH readiness + installer serial evidence.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "$REPO_ROOT"

SSH_HOST="${SSH_HOST:-127.0.0.1}"
SSH_PORT="${SSH_PORT:-2226}"
SERIAL_LOG="${SERIAL_LOG:-}"
FSM_TIMEOUT_SEC="${FSM_TIMEOUT_SEC:-3600}"
FSM_POLL_MS="${FSM_POLL_MS:-2500}"
FSM_STATE_LOG="${FSM_STATE_LOG:-}"
STALL_TIMEOUT_SEC="${STALL_TIMEOUT_SEC:-420}"
MONITOR_HOST="${MONITOR_HOST:-127.0.0.1}"
MONITOR_PORT="${MONITOR_PORT:-9998}"
STALL_PROBE_MODE="${STALL_PROBE_MODE:-deep_retry}"
STALL_PROBE_RETRY_COUNT="${STALL_PROBE_RETRY_COUNT:-3}"
STALL_PROBE_RETRY_TIMEOUT_SEC="${STALL_PROBE_RETRY_TIMEOUT_SEC:-90}"
STALL_CAPTURE_MAX_PAGES="${STALL_CAPTURE_MAX_PAGES:-12}"
STALL_PROBE_DIR="${STALL_PROBE_DIR:-}"

if [ -z "$SERIAL_LOG" ]; then
    echo "[ERROR] SERIAL_LOG is required" >&2
    exit 2
fi

mkdir -p "$(dirname "$SERIAL_LOG")"
[ -n "$FSM_STATE_LOG" ] && mkdir -p "$(dirname "$FSM_STATE_LOG")"

# shellcheck source=scripts/lib/installer/serial-log-utils.sh
source "${REPO_ROOT}/scripts/lib/installer/serial-log-utils.sh"

log_state() {
    local msg="$1"
    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "$ts $msg"
    if [ -n "$FSM_STATE_LOG" ]; then
        echo "$ts $msg" >>"$FSM_STATE_LOG"
    fi
}

ssh_port_open() {
    local banner
    if ! banner="$(sh -c "printf '' | nc -w 2 \"$SSH_HOST\" \"$SSH_PORT\" 2>/dev/null | head -n 1" 2>/dev/null)"; then
        return 1
    fi
    [[ "$banner" == SSH-* ]]
}

sanitize_tail() {
    local bytes="${1:-262144}"
    sanitize_serial_tail "$SERIAL_LOG" "$bytes"
}

run_stall_probe() {
    local probe_dir
    if [ -n "$STALL_PROBE_DIR" ]; then
        probe_dir="$STALL_PROBE_DIR"
    elif [ -n "$FSM_STATE_LOG" ]; then
        probe_dir="$(dirname "$FSM_STATE_LOG")/stall-probe"
    else
        probe_dir="logs/stall-probe"
    fi
    mkdir -p "$probe_dir"
    if MONITOR_HOST="$MONITOR_HOST" \
        MONITOR_PORT="$MONITOR_PORT" \
        SERIAL_LOG="$SERIAL_LOG" \
        PROBE_DIR="$probe_dir" \
        PROBE_MODE="$STALL_PROBE_MODE" \
        RETRY_COUNT="$STALL_PROBE_RETRY_COUNT" \
        RETRY_TIMEOUT_SEC="$STALL_PROBE_RETRY_TIMEOUT_SEC" \
        CAPTURE_MAX_PAGES="$STALL_CAPTURE_MAX_PAGES" \
        FSM_STATE_LOG="$FSM_STATE_LOG" \
        "${REPO_ROOT}/scripts/qemu-stall-probe.sh"; then
        log_state "STATE=STALL_PROBE_RESULT result=advanced probe_dir=${probe_dir}"
        return 0
    fi
    log_state "STATE=STALL_PROBE_RESULT result=stalled probe_dir=${probe_dir}"
    return 1
}

start_ts="$(date +%s)"
last_hash=""
stall_start_ts=0
swap_fail_seen=0
swap_fail_active=0
heartbeat=0

log_state "STATE=FSM_START mode=serial ssh=${SSH_HOST}:${SSH_PORT} serial_log=${SERIAL_LOG}"

while :; do
    now_ts="$(date +%s)"
    elapsed=$((now_ts - start_ts))
    if [ "$elapsed" -gt "$FSM_TIMEOUT_SEC" ]; then
        log_state "STATE=TIMEOUT elapsed=${elapsed}s"
        exit 1
    fi

    if ssh_port_open; then
        log_state "STATE=SSH_PORT_OPEN elapsed=${elapsed}s"
        exit 0
    fi

    serial_text="$(sanitize_tail 262144 || true)"
    serial_lc="$(printf "%s" "$serial_text" | tr '[:upper:]' '[:lower:]')"

    if grep -q "failed to retrieve the preconfiguration file" <<<"$serial_lc"; then
        log_state "STATE=ERROR message=preseed_dialog_persistent"
        exit 2
    fi
    if grep -Eq "(choose language|select a language|configure the keyboard)" <<<"$serial_lc"; then
        log_state "STATE=ERROR message=interactive_installer_screen_detected"
        exit 3
    fi
    if grep -q "failed to create a file system" <<<"$serial_lc"; then
        log_state "STATE=ERROR message=filesystem_creation_failed_interactive"
        exit 5
    fi

    if grep -q "failed to create a swap space" <<<"$serial_lc"; then
        if [ "$swap_fail_active" -eq 0 ]; then
            swap_fail_seen=$((swap_fail_seen + 1))
            log_state "STATE=SWAP_CREATION_FAILED seen=${swap_fail_seen}"
            swap_fail_active=1
        fi
    else
        swap_fail_active=0
    fi

    if grep -q "computing the new partitions" <<<"$serial_lc"; then
        if [ "$stall_start_ts" -eq 0 ]; then
            stall_start_ts="$now_ts"
            log_state "STATE=PARTITION_COMPUTE_DETECTED elapsed=${elapsed}s"
        fi
    fi

    if grep -Eq "(installing the base system|select and install software|finishing the installation|installing grub boot loader)" <<<"$serial_lc"; then
        if [ "$stall_start_ts" -ne 0 ]; then
            log_state "STATE=PARTITION_COMPUTE_CLEARED elapsed=${elapsed}s"
        fi
        stall_start_ts=0
    fi

    if [ "$stall_start_ts" -ne 0 ]; then
        sig="$(printf "%s" "$serial_lc" | tail -n 200 | sha256sum | awk '{print $1}')"
        if [ "$sig" = "$last_hash" ] && [ $((now_ts - stall_start_ts)) -ge "$STALL_TIMEOUT_SEC" ]; then
            log_state "STATE=STALL_DETECTED elapsed=${elapsed}s stall_for=$((now_ts - stall_start_ts))s"
            if run_stall_probe; then
                stall_start_ts=0
                last_hash=""
            else
                log_state "STATE=ERROR message=partman_compute_partitions_stall elapsed=${elapsed}s stall_for=$((now_ts - stall_start_ts))s"
                exit 7
            fi
        fi
        last_hash="$sig"
    fi

    heartbeat=$((heartbeat + 1))
    if [ $((heartbeat % 6)) -eq 0 ]; then
        phase="installer_boot"
        if grep -q "partition disks" <<<"$serial_lc"; then
            phase="partition_disks"
        elif grep -q "installing the base system" <<<"$serial_lc"; then
            phase="base_install"
        elif grep -q "select and install software" <<<"$serial_lc"; then
            phase="pkg_install"
        elif grep -q "finishing the installation" <<<"$serial_lc"; then
            phase="finish_install"
        fi
        log_state "STATE=WAITING elapsed=${elapsed}s phase=${phase}"
    fi

    sleep "$(awk "BEGIN { printf \"%.3f\", ${FSM_POLL_MS}/1000 }")"
done
