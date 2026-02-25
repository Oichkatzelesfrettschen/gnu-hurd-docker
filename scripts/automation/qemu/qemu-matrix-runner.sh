#!/bin/bash
set -euo pipefail

# Extended unattended QEMU matrix runner with per-run evidence.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "$REPO_ROOT"

PROFILE="${PROFILE:-x11}"
SKIP_SETUP="${SKIP_SETUP:-1}"
MATRIX_ATTEMPTS="${MATRIX_ATTEMPTS:-2}"
MATRIX_BUSES="${MATRIX_BUSES:-ide,ahci,virtio-blk}"
MATRIX_DISK_SIZES="${MATRIX_DISK_SIZES:-4G,20G}"
MATRIX_CPUS="${MATRIX_CPUS:-1,2}"
INSTALL_TIMEOUT_SEC="${INSTALL_TIMEOUT_SEC:-2400}"
BOOT_TIMEOUT_SEC="${BOOT_TIMEOUT_SEC:-600}"
FSM_BACKEND="${FSM_BACKEND:-serial}"
STALL_TIMEOUT_SEC="${STALL_TIMEOUT_SEC:-420}"
STALL_PROBE_MODE="${STALL_PROBE_MODE:-deep_retry}"
STALL_PROBE_RETRY_COUNT="${STALL_PROBE_RETRY_COUNT:-3}"
STALL_PROBE_RETRY_TIMEOUT_SEC="${STALL_PROBE_RETRY_TIMEOUT_SEC:-90}"
STALL_CAPTURE_MAX_PAGES="${STALL_CAPTURE_MAX_PAGES:-12}"

if ! [[ "$MATRIX_ATTEMPTS" =~ ^[0-9]+$ ]] || [ "$MATRIX_ATTEMPTS" -lt 1 ]; then
    echo "[ERROR] MATRIX_ATTEMPTS must be a positive integer (got: $MATRIX_ATTEMPTS)" >&2
    exit 2
fi

MATRIX_ID="matrix-$(date -u +%Y%m%d-%H%M%S)"
MATRIX_DIR="logs/runs/${MATRIX_ID}"
mkdir -p "$MATRIX_DIR"

IFS=',' read -r -a BUS_LIST <<<"$MATRIX_BUSES"
IFS=',' read -r -a DISK_LIST <<<"$MATRIX_DISK_SIZES"
IFS=',' read -r -a CPU_LIST <<<"$MATRIX_CPUS"

install_script="${REPO_ROOT}/scripts/install-hurd-unattended.sh"
summary_tsv="${MATRIX_DIR}/matrix-summary.tsv"
insights_md="${MATRIX_DIR}/matrix-insights.md"

echo -e "case_id\tattempt\tbus\tdisk_size\tcpus\tstatus\tstage\tfailure_tag\trun_dir" >"$summary_tsv"

total=0
pass=0
fail=0

for bus in "${BUS_LIST[@]}"; do
    for disk_size in "${DISK_LIST[@]}"; do
        for cpus in "${CPU_LIST[@]}"; do
            for attempt in $(seq 1 "$MATRIX_ATTEMPTS"); do
                total=$((total + 1))
                case_id="$(printf "b-%s_d-%s_c-%s" "$bus" "$disk_size" "$cpus" | tr '[:upper:]' '[:lower:]')"
                attempt_label="$(printf "attempt-%02d" "$attempt")"
                run_id="${MATRIX_ID}-${case_id}-${attempt_label}"
                run_dir="${MATRIX_DIR}/${case_id}/${attempt_label}"
                mkdir -p "$run_dir"

                cat >"${run_dir}/matrix-case.env" <<EOF
run_id=${run_id}
bus=${bus}
disk_size=${disk_size}
cpus=${cpus}
attempt=${attempt}
profile=${PROFILE}
EOF

                echo "[INFO] matrix case=${case_id} attempt=${attempt_label} bus=${bus} disk=${disk_size} cpus=${cpus}"

                if env \
                    RUN_ID="$run_id" \
                    RUN_DIR="$run_dir" \
                    QEMU_DISK_BUS="$bus" \
                    QEMU_INSTALL_DISK_SIZE="$disk_size" \
                    QEMU_CPUS="$cpus" \
                    PROFILE="$PROFILE" \
                    SKIP_SETUP="$SKIP_SETUP" \
                    INSTALL_TIMEOUT_SEC="$INSTALL_TIMEOUT_SEC" \
                    BOOT_TIMEOUT_SEC="$BOOT_TIMEOUT_SEC" \
                    FSM_BACKEND="$FSM_BACKEND" \
                    STALL_TIMEOUT_SEC="$STALL_TIMEOUT_SEC" \
                    STALL_PROBE_MODE="$STALL_PROBE_MODE" \
                    STALL_PROBE_RETRY_COUNT="$STALL_PROBE_RETRY_COUNT" \
                    STALL_PROBE_RETRY_TIMEOUT_SEC="$STALL_PROBE_RETRY_TIMEOUT_SEC" \
                    STALL_CAPTURE_MAX_PAGES="$STALL_CAPTURE_MAX_PAGES" \
                    "$install_script" \
                        --backend qemu \
                        --profile "$PROFILE"; then
                    pass=$((pass + 1))
                else
                    fail=$((fail + 1))
                fi

                status="missing_summary"
                stage="unknown"
                failure_tag="unknown"
                if [ -f "${run_dir}/summary.log" ]; then
                    status="$(awk -F= '/^status=/{print $2}' "${run_dir}/summary.log" | tail -n1)"
                    stage="$(awk -F= '/^stage=/{print $2}' "${run_dir}/summary.log" | tail -n1)"
                    failure_tag="$(awk -F= '/^failure_tag=/{print $2}' "${run_dir}/summary.log" | tail -n1)"
                fi
                echo -e "${case_id}\t${attempt_label}\t${bus}\t${disk_size}\t${cpus}\t${status}\t${stage}\t${failure_tag}\t${run_dir}" >>"$summary_tsv"
            done
        done
    done
done

{
    echo "# QEMU Matrix Insights"
    echo ""
    echo "- matrix_id: ${MATRIX_ID}"
    echo "- total_runs: ${total}"
    echo "- pass: ${pass}"
    echo "- fail: ${fail}"
    echo ""
    echo "## Failure Tags by Bus"
    echo ""
    awk -F'\t' 'NR>1 { key=$3 "|" $8; c[key]++ } END { for (k in c) print c[k] "\t" k }' "$summary_tsv" \
        | sort -nr \
        | awk -F'[\t|]' '{ printf("- bus=%s failure_tag=%s count=%s\n", $2, $3, $1) }'
    echo ""
    echo "## Cases"
    echo ""
    awk -F'\t' 'NR>1 { printf("- %s %s bus=%s disk=%s cpus=%s status=%s failure_tag=%s\n", $1, $2, $3, $4, $5, $6, $8) }' "$summary_tsv"
} >"$insights_md"

echo "[INFO] Matrix Summary: ${summary_tsv}"
echo "[INFO] Matrix Insights: ${insights_md}"
echo "[INFO] Artifacts Root: ${MATRIX_DIR}"

if [ "$fail" -gt 0 ]; then
    exit 1
fi
