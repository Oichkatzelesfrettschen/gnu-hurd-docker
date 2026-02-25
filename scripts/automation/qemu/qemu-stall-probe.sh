#!/bin/bash
set -euo pipefail

# Active stall forensics for unattended QEMU installer:
# - Enters log/shell consoles via sendkey
# - Captures serial evidence snapshots
# - Optionally retries installer progress before final abort

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "$REPO_ROOT"

MONITOR_HOST="${MONITOR_HOST:-127.0.0.1}"
MONITOR_PORT="${MONITOR_PORT:-9998}"
SERIAL_LOG="${SERIAL_LOG:-}"
PROBE_DIR="${PROBE_DIR:-logs/stall-probe}"
PROBE_MODE="${PROBE_MODE:-deep_retry}" # safe_capture|shell_logs|deep_retry
RETRY_COUNT="${RETRY_COUNT:-3}"
RETRY_TIMEOUT_SEC="${RETRY_TIMEOUT_SEC:-90}"
CAPTURE_MAX_PAGES="${CAPTURE_MAX_PAGES:-12}"
FSM_STATE_LOG="${FSM_STATE_LOG:-}"

if [ -z "$SERIAL_LOG" ]; then
    echo "[ERROR] SERIAL_LOG is required" >&2
    exit 2
fi

if ! [[ "$RETRY_COUNT" =~ ^[0-9]+$ ]] || [ "$RETRY_COUNT" -lt 1 ]; then
    echo "[ERROR] RETRY_COUNT must be a positive integer (got: $RETRY_COUNT)" >&2
    exit 2
fi
if ! [[ "$CAPTURE_MAX_PAGES" =~ ^[0-9]+$ ]] || [ "$CAPTURE_MAX_PAGES" -lt 1 ]; then
    echo "[ERROR] CAPTURE_MAX_PAGES must be a positive integer (got: $CAPTURE_MAX_PAGES)" >&2
    exit 2
fi

mkdir -p "$PROBE_DIR"

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

send_key() {
    local seq="$1"
    MONITOR_HOST="$MONITOR_HOST" MONITOR_PORT="$MONITOR_PORT" \
        "${REPO_ROOT}/scripts/qemu-sendkey.sh" "$seq" >/dev/null
}

capture_snapshot() {
    local label="$1"
    local stamp
    stamp="$(date -u +%Y%m%d-%H%M%S)"
    local out_clean="${PROBE_DIR}/${stamp}-${label}.txt"
    local out_partman="${PROBE_DIR}/${stamp}-${label}-partman.txt"
    sanitize_serial_tail "$SERIAL_LOG" 786432 >"$out_clean"
    extract_partman_error_lines "$out_clean" >"$out_partman"
    echo "$out_clean"
}

progress_advanced() {
    local clean_log="$1"
    rg -qi \
        "installing the base system|select and install software|finishing the installation|installing grub boot loader|rebooting into your new system" \
        "$clean_log"
}

retry_cycle() {
    local cycle_id="$1"
    log_state "STALL_PROBE cycle=${cycle_id} action=begin mode=${PROBE_MODE}"

    # Move to installer log console and capture current error context.
    send_key "alt-f4"
    sleep 2
    capture_snapshot "cycle-${cycle_id}-tty4-initial" >/dev/null

    local _
    for _ in $(seq 1 "$CAPTURE_MAX_PAGES"); do
        send_key "pgdn"
        sleep 0.2
    done
    capture_snapshot "cycle-${cycle_id}-tty4-paged" >/dev/null

    if [ "$PROBE_MODE" != "safe_capture" ]; then
        # Switch to shell console and attempt command-driven diagnostics.
        send_key "alt-f2"
        sleep 2
        capture_snapshot "cycle-${cycle_id}-tty2-before-cmd" >/dev/null
        MONITOR_HOST="$MONITOR_HOST" MONITOR_PORT="$MONITOR_PORT" \
            "${REPO_ROOT}/scripts/qemu-type.sh" --enter "set -x; tail -n 200 /var/log/syslog 2>/dev/null || true; tail -n 200 /var/log/partman 2>/dev/null || true"
        sleep 3
        capture_snapshot "cycle-${cycle_id}-tty2-after-cmd" >/dev/null
    fi

    # Return to installer TTY and allow it to continue.
    send_key "alt-f1"
    sleep 2
    capture_snapshot "cycle-${cycle_id}-tty1-return" >/dev/null

    local wait_start
    wait_start="$(date +%s)"
    while :; do
        local now elapsed out_clean
        now="$(date +%s)"
        elapsed=$((now - wait_start))
        out_clean="$(capture_snapshot "cycle-${cycle_id}-progress-check")"
        if progress_advanced "$out_clean"; then
            log_state "STALL_PROBE cycle=${cycle_id} action=progress_advanced elapsed=${elapsed}s"
            echo "advanced"
            return 0
        fi
        if [ "$elapsed" -ge "$RETRY_TIMEOUT_SEC" ]; then
            log_state "STALL_PROBE cycle=${cycle_id} action=still_stalled elapsed=${elapsed}s"
            echo "stalled"
            return 0
        fi
        sleep 3
    done
}

summary_file="${PROBE_DIR}/summary.log"
: >"$summary_file"

result="stalled"
attempt=1
while [ "$attempt" -le "$RETRY_COUNT" ]; do
    state="$(retry_cycle "$attempt")"
    echo "attempt=${attempt} result=${state}" >>"$summary_file"
    if [ "$state" = "advanced" ]; then
        result="advanced"
        break
    fi
    attempt=$((attempt + 1))
done

echo "final_result=${result}" >>"$summary_file"
echo "probe_mode=${PROBE_MODE}" >>"$summary_file"
echo "monitor=${MONITOR_HOST}:${MONITOR_PORT}" >>"$summary_file"
echo "serial_log=${SERIAL_LOG}" >>"$summary_file"

if [ "$result" = "advanced" ]; then
    exit 0
fi
exit 1
