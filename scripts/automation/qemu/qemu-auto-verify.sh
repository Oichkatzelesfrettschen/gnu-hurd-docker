#!/bin/bash
set -euo pipefail

# Repeated unattended QEMU verification harness.
# Runs install-hurd-unattended.sh multiple times and aggregates outcomes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "$REPO_ROOT"

ATTEMPTS="${ATTEMPTS:-3}"
PROFILE="${PROFILE:-x11}"
SKIP_SETUP="${SKIP_SETUP:-1}"
QEMU_CPUS="${QEMU_CPUS:-1}"
QEMU_DISK_BUS="${QEMU_DISK_BUS:-ide}"
INSTALL_TIMEOUT_SEC="${INSTALL_TIMEOUT_SEC:-3600}"
BOOT_TIMEOUT_SEC="${BOOT_TIMEOUT_SEC:-900}"
QEMU_INSTALL_DISK_SIZE="${QEMU_INSTALL_DISK_SIZE:-20G}"
FSM_BACKEND="${FSM_BACKEND:-serial}"
STALL_TIMEOUT_SEC="${STALL_TIMEOUT_SEC:-420}"
STALL_PROBE_MODE="${STALL_PROBE_MODE:-deep_retry}"
STALL_PROBE_RETRY_COUNT="${STALL_PROBE_RETRY_COUNT:-3}"
STALL_PROBE_RETRY_TIMEOUT_SEC="${STALL_PROBE_RETRY_TIMEOUT_SEC:-90}"
STALL_CAPTURE_MAX_PAGES="${STALL_CAPTURE_MAX_PAGES:-12}"

INSTALL_SCRIPT="${REPO_ROOT}/scripts/install-hurd-unattended.sh"

if ! [[ "$ATTEMPTS" =~ ^[0-9]+$ ]] || [ "$ATTEMPTS" -lt 1 ]; then
    echo "[ERROR] ATTEMPTS must be a positive integer (got: $ATTEMPTS)" >&2
    exit 2
fi

VERIFY_RUN_ID="verify-$(date -u +%Y%m%d-%H%M%S)"
VERIFY_DIR="logs/runs/${VERIFY_RUN_ID}"
mkdir -p "$VERIFY_DIR"

echo "[INFO] Verification Run: $VERIFY_RUN_ID"
echo "[INFO] Attempts: $ATTEMPTS"
echo "[INFO] Output Directory: $VERIFY_DIR"

pass_count=0
fail_count=0

for idx in $(seq 1 "$ATTEMPTS"); do
    attempt_label="$(printf 'attempt-%02d' "$idx")"
    run_id="${VERIFY_RUN_ID}-${attempt_label}"
    run_dir="${VERIFY_DIR}/${attempt_label}"
    mkdir -p "$run_dir"

    echo
    echo "============================================================"
    echo "[INFO] Starting ${attempt_label} (run_id=${run_id})"
    echo "============================================================"

    if env \
        RUN_ID="$run_id" \
        RUN_DIR="$run_dir" \
        QEMU_CPUS="$QEMU_CPUS" \
        QEMU_DISK_BUS="$QEMU_DISK_BUS" \
        QEMU_INSTALL_DISK_SIZE="$QEMU_INSTALL_DISK_SIZE" \
        INSTALL_TIMEOUT_SEC="$INSTALL_TIMEOUT_SEC" \
        BOOT_TIMEOUT_SEC="$BOOT_TIMEOUT_SEC" \
        FSM_BACKEND="$FSM_BACKEND" \
        STALL_TIMEOUT_SEC="$STALL_TIMEOUT_SEC" \
        STALL_PROBE_MODE="$STALL_PROBE_MODE" \
        STALL_PROBE_RETRY_COUNT="$STALL_PROBE_RETRY_COUNT" \
        STALL_PROBE_RETRY_TIMEOUT_SEC="$STALL_PROBE_RETRY_TIMEOUT_SEC" \
        STALL_CAPTURE_MAX_PAGES="$STALL_CAPTURE_MAX_PAGES" \
        SKIP_SETUP="$SKIP_SETUP" \
        "$INSTALL_SCRIPT" \
            --backend qemu \
            --profile "$PROFILE"; then
        pass_count=$((pass_count + 1))
        echo "[INFO] ${attempt_label}: PASS"
    else
        fail_count=$((fail_count + 1))
        echo "[WARN] ${attempt_label}: FAIL"
    fi
done

echo
echo "==================== Verification Summary ===================="
for idx in $(seq 1 "$ATTEMPTS"); do
    attempt_label="$(printf 'attempt-%02d' "$idx")"
    summary_file="${VERIFY_DIR}/${attempt_label}/summary.log"
    if [ -f "$summary_file" ]; then
        status="$(awk -F= '/^status=/{print $2}' "$summary_file" | tail -n1)"
        failure_tag="$(awk -F= '/^failure_tag=/{print $2}' "$summary_file" | tail -n1)"
        stage="$(awk -F= '/^stage=/{print $2}' "$summary_file" | tail -n1)"
        printf "%s status=%s stage=%s failure_tag=%s\n" "$attempt_label" "${status:-unknown}" "${stage:-unknown}" "${failure_tag:-unknown}"
    else
        printf "%s status=missing_summary stage=unknown failure_tag=unknown\n" "$attempt_label"
    fi
done
echo "PASS=${pass_count} FAIL=${fail_count}"
echo "Artifacts: ${VERIFY_DIR}"

if [ "$fail_count" -gt 0 ]; then
    exit 1
fi
