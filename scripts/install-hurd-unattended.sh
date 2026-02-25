#!/bin/bash
set -Eeuo pipefail

# Fully unattended installer-to-SSH orchestration across backends.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

BACKEND="${BACKEND:-auto}" # auto|qemu|virtualbox|podman
PROFILE="${PROFILE:-x11}"   # dev|x11
SKIP_SETUP="${SKIP_SETUP:-0}"
SKIP_PROVISION="${SKIP_PROVISION:-0}"
ROOT_PASS="${ROOT_PASS:-root}"
AGENTS_PASS="${AGENTS_PASS:-agents}"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%d-%H%M%S)}"
RUN_DIR_DEFAULT="logs/runs/${RUN_ID}"
RUN_DIR="${RUN_DIR:-$RUN_DIR_DEFAULT}"

QEMU_RAM_MB="${QEMU_RAM_MB:-4096}"
QEMU_CPUS="${QEMU_CPUS:-2}"
QEMU_HOST_SSH_PORT="${QEMU_HOST_SSH_PORT:-2226}"
QEMU_SERIAL_PORT="${QEMU_SERIAL_PORT:-5566}"
QEMU_MONITOR_PORT="${QEMU_MONITOR_PORT:-9998}"
QEMU_PID_FILE="${QEMU_PID_FILE:-infrastructure/cache/images/qemu/hurd-unattended.pid}"
QEMU_STDOUT_LOG="${QEMU_STDOUT_LOG:-${RUN_DIR}/qemu.log}"
QEMU_SERIAL_CAPTURE_LOG="${QEMU_SERIAL_CAPTURE_LOG:-${RUN_DIR}/serial.log}"
QEMU_INSTALL_DISK="${QEMU_INSTALL_DISK:-infrastructure/cache/images/qemu/hurd-unattended-target.qcow2}"
QEMU_INSTALL_DISK_SIZE="${QEMU_INSTALL_DISK_SIZE:-20G}"
QEMU_DISK_BUS="${QEMU_DISK_BUS:-ide}" # ide|ahci|virtio-blk

INSTALL_TIMEOUT_SEC="${INSTALL_TIMEOUT_SEC:-3600}"
BOOT_TIMEOUT_SEC="${BOOT_TIMEOUT_SEC:-900}"
FSM_POLL_MS="${FSM_POLL_MS:-2500}"
FSM_BACKEND="${FSM_BACKEND:-serial}" # serial|ocr
STALL_TIMEOUT_SEC="${STALL_TIMEOUT_SEC:-420}"
STALL_PROBE_MODE="${STALL_PROBE_MODE:-deep_retry}"
STALL_PROBE_RETRY_COUNT="${STALL_PROBE_RETRY_COUNT:-3}"
STALL_PROBE_RETRY_TIMEOUT_SEC="${STALL_PROBE_RETRY_TIMEOUT_SEC:-90}"
STALL_CAPTURE_MAX_PAGES="${STALL_CAPTURE_MAX_PAGES:-12}"

PODMAN_COMPOSE_PROVIDER="${PODMAN_COMPOSE_PROVIDER:-podman-compose}"
HURD_IMAGE_BASENAME="${HURD_IMAGE_BASENAME:-debian-hurd-amd64.fresh.qcow2}"
QEMU_CDROM_AUTO="/opt/hurd-installer/debian-hurd-amd64-installer.latest-mini-auto.iso"

TRACE="${TRACE:-0}"
TRANSCRIPT_FILE="${TRANSCRIPT_FILE:-${RUN_DIR}/transcript.log}"
RUN_SUMMARY_FILE="${RUN_SUMMARY_FILE:-${RUN_DIR}/summary.log}"
KEEP_FAILED_VM="${KEEP_FAILED_VM:-0}"

usage() {
    cat <<'EOF'
Usage: scripts/install-hurd-unattended.sh [options]

Options:
  --backend auto|qemu|virtualbox|podman
  --profile dev|x11
  --root-pass PASS
  --agents-pass PASS
  --skip-setup
  --skip-provision
  --trace                 enable shell tracing (set -x)
  --transcript PATH       write transcript to PATH (default logs/unattended-transcript-*.log)
  -h, --help

Examples:
  scripts/install-hurd-unattended.sh --backend auto --profile x11
  scripts/install-hurd-unattended.sh --backend virtualbox --profile dev   # conceptual stub
  scripts/install-hurd-unattended.sh --backend podman --skip-provision
EOF
}

run_cmd() {
    echo "+ $*"
    "$@"
}

CURRENT_STAGE="init"
RUN_STATUS="unknown"
RUN_FAILURE_TAG="unknown_failure"
SUMMARY_WRITTEN=0

set_stage() {
    CURRENT_STAGE="$1"
    echo "[STAGE] ${CURRENT_STAGE}"
}

classify_failure_tag() {
    local summary="unknown_failure"
    local transcript="$1"
    local state_log="${2:-}"
    local serial_log="${3:-}"

    if [ -f "$state_log" ] && grep -qi "message=partman_write_changes_persistent" "$state_log"; then
        summary="partman_write_changes_persistent"
    elif [ -f "$state_log" ] && grep -qi "message=filesystem_creation_failed_interactive" "$state_log"; then
        summary="filesystem_creation_failed_interactive"
    elif [ -f "$state_log" ] && grep -qi "message=swap_creation_failed_interactive_persistent" "$state_log"; then
        summary="swap_creation_failed_interactive_persistent"
    elif [ -f "$state_log" ] && grep -qi "STALL_PROBE_RESULT result=stalled" "$state_log"; then
        summary="partman_compute_partitions_stall_after_probe"
    elif [ -f "$state_log" ] && grep -qi "message=partman_compute_partitions_stall" "$state_log"; then
        summary="partman_compute_partitions_stall"
    elif [ -f "$state_log" ] && grep -qi "message=com_console_stall" "$state_log"; then
        summary="partman_compute_partitions_stall"
    elif [ -f "$serial_log" ] && grep -qi "Computing the new partitions" "$serial_log"; then
        summary="partman_compute_partitions_stall"
    elif [ -f "$state_log" ] && grep -qi "message=monitor_" "$state_log"; then
        summary="monitor_channel_failure"
    elif [ -f "$transcript" ] && grep -qi "Timeout waiting for SSH" "$transcript"; then
        summary="ssh_timeout"
    elif [ -f "$transcript" ] && grep -qi "spawn id exp3 not open" "$transcript"; then
        summary="fsm_monitor_disconnect"
    fi

    echo "$summary"
}

write_run_summary() {
    local status="$1"
    local failure_tag="$2"
    local state_log="${3:-}"
    local serial_log="${4:-}"
    local summary_file
    summary_file="$(realpath_repo "$RUN_SUMMARY_FILE")"
    mkdir -p "$(dirname "$summary_file")"
    {
        echo "run_id=${RUN_ID}"
        echo "status=${status}"
        echo "stage=${CURRENT_STAGE}"
        echo "failure_tag=${failure_tag}"
        echo "backend=${BACKEND}"
        echo "profile=${PROFILE}"
        echo "qemu_disk_bus=${QEMU_DISK_BUS}"
        echo "transcript=$(realpath_repo "$TRANSCRIPT_FILE")"
        if [ -n "$state_log" ]; then
            echo "fsm_state_log=${state_log}"
        fi
        if [ -n "$serial_log" ]; then
            echo "serial_log=${serial_log}"
        fi
    } >"$summary_file"
    SUMMARY_WRITTEN=1
    echo "[INFO] Run summary: $summary_file"
}

finalize_run_summary_on_error() {
    if [ "$SUMMARY_WRITTEN" = "1" ]; then
        return 0
    fi
    RUN_STATUS="failed"
    local fsm_state_log
    local serial_log
    fsm_state_log="$(realpath_repo "${RUN_DIR}/fsm/state.log")"
    serial_log="$(realpath_repo "$QEMU_SERIAL_CAPTURE_LOG")"
    RUN_FAILURE_TAG="$(
        classify_failure_tag \
            "$(realpath_repo "$TRANSCRIPT_FILE")" \
            "$fsm_state_log" \
            "$serial_log"
    )"
    write_run_summary "$RUN_STATUS" "$RUN_FAILURE_TAG" "$fsm_state_log" "$serial_log"
    if [ "$BACKEND" = "qemu" ] && [ "$KEEP_FAILED_VM" != "1" ]; then
        echo "[INFO] Stopping failed QEMU instance (set KEEP_FAILED_VM=1 to keep it running)"
        qemu_stop || true
    fi
}

finalize_run_summary_on_interrupt() {
    if [ "$SUMMARY_WRITTEN" = "1" ]; then
        return 0
    fi
    RUN_STATUS="interrupted"
    RUN_FAILURE_TAG="interrupted_by_signal"
    write_run_summary \
        "$RUN_STATUS" \
        "$RUN_FAILURE_TAG" \
        "$(realpath_repo "${RUN_DIR}/fsm/state.log")" \
        "$(realpath_repo "$QEMU_SERIAL_CAPTURE_LOG")"
}

cleanup_on_interrupt() {
    echo "[WARN] Received interrupt; stopping active QEMU process if present..."
    qemu_stop || true
    finalize_run_summary_on_interrupt || true
    exit 130
}

realpath_repo() {
    local value="$1"
    if [[ "$value" = /* ]]; then
        echo "$value"
    else
        echo "${REPO_ROOT}/${value}"
    fi
}

qemu_pid_file_path() {
    realpath_repo "$QEMU_PID_FILE"
}

qemu_log_path() {
    realpath_repo "$QEMU_STDOUT_LOG"
}

qemu_disk_path() {
    realpath_repo "images/${HURD_IMAGE_BASENAME}"
}

qemu_install_disk_path() {
    realpath_repo "$QEMU_INSTALL_DISK"
}

qemu_iso_path() {
    realpath_repo "infrastructure/cache/images/installers/debian-hurd-amd64-installer.latest-mini-auto.iso"
}

qemu_base_iso_path() {
    realpath_repo "infrastructure/cache/images/installers/debian-hurd-amd64-installer.latest-mini.iso"
}

qemu_prepare_install_disk() {
    local disk
    disk="$(qemu_install_disk_path)"
    mkdir -p "$(dirname "$disk")"
    rm -f "$disk"
    qemu-img create -f qcow2 "$disk" "$QEMU_INSTALL_DISK_SIZE" >/dev/null
    echo "$disk"
}

rebuild_unattended_iso_local() {
    local base_iso auto_iso preseed_src
    base_iso="$(qemu_base_iso_path)"
    auto_iso="$(qemu_iso_path)"
    preseed_src="$(realpath_repo "infrastructure/unattended/preseed.cfg")"

    if [ ! -f "$base_iso" ]; then
        echo "[ERROR] Missing base installer ISO required for unattended remaster: $base_iso" >&2
        echo "[HINT] Run: make setup-daily-installer" >&2
        exit 1
    fi
    if [ ! -f "$preseed_src" ]; then
        echo "[ERROR] Missing preseed source: $preseed_src" >&2
        exit 1
    fi

    echo "[STEP] Rebuilding unattended ISO from local base installer..."
    run_cmd env \
        BASE_ISO="$base_iso" \
        OUTPUT_ISO="$auto_iso" \
        PRESEED_FILE="$preseed_src" \
        "${SCRIPT_DIR}/build-hurd-unattended-iso.sh"
}

extract_preseed_from_auto_iso() {
    local auto_iso="$1"
    local out_file="$2"
    local tmpdir initrd_gz initrd_raw
    tmpdir="$(mktemp -d -t hurd-auto-iso-check.XXXXXX)"
    initrd_gz="${tmpdir}/initrd.gz"
    initrd_raw="${tmpdir}/initrd.raw"

    if ! xorriso -osirrox on -indev "$auto_iso" -extract /boot/initrd.gz "$initrd_gz" >/dev/null 2>&1; then
        rm -rf "$tmpdir"
        return 1
    fi
    if ! gzip -dc "$initrd_gz" > "$initrd_raw"; then
        rm -rf "$tmpdir"
        return 1
    fi
    if ! debugfs -R "dump -p /preseed.cfg $out_file" "$initrd_raw" >/dev/null 2>&1; then
        rm -rf "$tmpdir"
        return 1
    fi
    rm -rf "$tmpdir"
    return 0
}

ensure_unattended_iso_current() {
    local auto_iso preseed_src extracted_preseed
    auto_iso="$(qemu_iso_path)"
    preseed_src="$(realpath_repo "infrastructure/unattended/preseed.cfg")"

    if [ ! -f "$auto_iso" ]; then
        echo "[WARN] Unattended ISO not found; rebuilding from local base..."
        rebuild_unattended_iso_local
        return 0
    fi

    extracted_preseed="$(mktemp -t hurd-auto-preseed.XXXXXX)"
    if ! extract_preseed_from_auto_iso "$auto_iso" "$extracted_preseed"; then
        rm -f "$extracted_preseed"
        echo "[WARN] Could not extract /preseed.cfg from unattended ISO; rebuilding..."
        rebuild_unattended_iso_local
        return 0
    fi

    if ! cmp -s "$preseed_src" "$extracted_preseed"; then
        rm -f "$extracted_preseed"
        echo "[WARN] Unattended ISO preseed is stale vs repository preseed; rebuilding..."
        rebuild_unattended_iso_local
        return 0
    fi

    rm -f "$extracted_preseed"
}

backend_auto_pick() {
    if command -v qemu-system-x86_64 >/dev/null 2>&1; then
        echo "qemu"
        return
    fi
    if command -v podman >/dev/null 2>&1; then
        echo "podman"
        return
    fi
    echo "[ERROR] Could not auto-pick backend (need qemu-system-x86_64 or podman)" >&2
    exit 1
}

ensure_assets() {
    if [ "$SKIP_SETUP" = "1" ]; then
        echo "[INFO] Skipping installer asset setup (--skip-setup)"
        return
    fi
    run_cmd "${SCRIPT_DIR}/setup-hurd-amd64-daily-installer.sh"
}

wait_tcp_port() {
    local host="$1"
    local port="$2"
    local timeout="$3"
    local waited=0
    while [ "$waited" -lt "$timeout" ]; do
        if nc -z "$host" "$port" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}

wait_ssh() {
    local host="$1"
    local port="$2"
    local timeout="$3"
    run_cmd env \
        HOST="$host" \
        PORT="$port" \
        USER_NAME="root" \
        PASSWORD="$ROOT_PASS" \
        TIMEOUT_SEC="$timeout" \
        "${SCRIPT_DIR}/wait-for-guest-ssh.sh"
}

provision_guest() {
    local host="$1"
    local port="$2"
    if [ "$SKIP_PROVISION" = "1" ]; then
        echo "[INFO] Skipping provisioning (--skip-provision)"
        return
    fi
    run_cmd env \
        HOST="$host" \
        PORT="$port" \
        ROOT_PASS="$ROOT_PASS" \
        AGENTS_PASS="$AGENTS_PASS" \
        PROFILE="$PROFILE" \
        TIMEOUT_SEC="$BOOT_TIMEOUT_SEC" \
        "${SCRIPT_DIR}/provision-hurd-x11.sh"
}

qemu_start_with_media() {
    local disk="$1"
    local iso="$2"
    local boot_order="$3"
    local pid_file
    local log_file
    pid_file="$(qemu_pid_file_path)"
    log_file="$(qemu_log_path)"

    mkdir -p "$(dirname "$pid_file")" "$(dirname "$log_file")"

    local accel cpu
    if [ "$(uname -m)" = "x86_64" ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        accel="kvm"
        cpu="host"
    else
        accel="tcg"
        cpu="max"
    fi

    local machine="pc"
    local -a disk_args=()
    local -a iso_args=()
    case "$QEMU_DISK_BUS" in
        ide)
            disk_args=(-drive "file=${disk},if=ide,cache=writeback,aio=threads,format=qcow2")
            ;;
        ahci)
            machine="q35"
            disk_args=(
                -drive "file=${disk},if=none,id=hd0,cache=writeback,aio=threads,format=qcow2"
                -device "ich9-ahci,id=ahci0"
                -device "ide-hd,drive=hd0,bus=ahci0.0"
            )
            if [ -n "$iso" ]; then
                iso_args=(
                    -drive "file=${iso},if=none,id=cd0,media=cdrom,readonly=on"
                    -device "ide-cd,drive=cd0,bus=ahci0.1"
                )
            fi
            ;;
        virtio-blk)
            disk_args=(
                -drive "file=${disk},if=none,id=hd0,cache=writeback,aio=threads,format=qcow2"
                -device "virtio-blk-pci,drive=hd0"
            )
            ;;
        *)
            echo "[ERROR] Unsupported QEMU_DISK_BUS: ${QEMU_DISK_BUS} (expected ide|ahci|virtio-blk)" >&2
            exit 2
            ;;
    esac

    local -a cmd=(
        qemu-system-x86_64
        -name hurd-unattended
        -machine "$machine"
        -accel "$accel"
        -cpu "$cpu"
        -m "$QEMU_RAM_MB"
        -smp "$QEMU_CPUS"
        "${disk_args[@]}"
        -boot "order=${boot_order}"
        -nic "user,model=e1000,hostfwd=tcp:127.0.0.1:${QEMU_HOST_SSH_PORT}-:22"
        -serial "tcp:127.0.0.1:${QEMU_SERIAL_PORT},server,nowait"
        -monitor "tcp:127.0.0.1:${QEMU_MONITOR_PORT},server,nowait"
        -display none
        -daemonize
        -pidfile "$pid_file"
    )

    if [ "${#iso_args[@]}" -gt 0 ]; then
        cmd+=("${iso_args[@]}")
    elif [ -n "$iso" ]; then
        cmd+=(-cdrom "$iso")
    fi

    echo "+ ${cmd[*]}"
    "${cmd[@]}"
    echo "[INFO] QEMU launched (bus=${QEMU_DISK_BUS}, SSH localhost:${QEMU_HOST_SSH_PORT}, serial ${QEMU_SERIAL_PORT}, monitor ${QEMU_MONITOR_PORT})"
}

qemu_stop() {
    local pid_file
    pid_file="$(qemu_pid_file_path)"
    if [ ! -f "$pid_file" ]; then
        return 0
    fi
    local pid
    pid="$(cat "$pid_file")"
    if [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1; then
        kill "$pid" >/dev/null 2>&1 || true
        for _ in $(seq 1 30); do
            if kill -0 "$pid" >/dev/null 2>&1; then
                sleep 1
            else
                break
            fi
        done
        if kill -0 "$pid" >/dev/null 2>&1; then
            kill -9 "$pid" >/dev/null 2>&1 || true
        fi
    fi
    rm -f "$pid_file"
}

run_backend_qemu() {
    command -v qemu-system-x86_64 >/dev/null 2>&1 || {
        echo "[ERROR] qemu-system-x86_64 not found" >&2
        exit 1
    }
    command -v qemu-img >/dev/null 2>&1 || {
        echo "[ERROR] qemu-img is required" >&2
        exit 1
    }
    command -v sshpass >/dev/null 2>&1 || {
        echo "[ERROR] sshpass is required" >&2
        exit 1
    }
    command -v nc >/dev/null 2>&1 || {
        echo "[ERROR] nc is required" >&2
        exit 1
    }
    if [ "$FSM_BACKEND" = "serial" ]; then
        command -v perl >/dev/null 2>&1 || {
            echo "[ERROR] perl is required for serial FSM log parsing" >&2
            exit 1
        }
        command -v expect >/dev/null 2>&1 || {
            echo "[ERROR] expect is required for serial stall probe interactions" >&2
            exit 1
        }
        command -v telnet >/dev/null 2>&1 || {
            echo "[ERROR] telnet is required for serial stall probe interactions" >&2
            exit 1
        }
        command -v python3 >/dev/null 2>&1 || {
            echo "[ERROR] python3 is required for qemu-type helper" >&2
            exit 1
        }
    else
        command -v expect >/dev/null 2>&1 || {
            echo "[ERROR] expect is required for OCR FSM backend" >&2
            exit 1
        }
        command -v tesseract >/dev/null 2>&1 || {
            echo "[ERROR] tesseract is required for OCR FSM backend" >&2
            exit 1
        }
    fi
    command -v xorriso >/dev/null 2>&1 || {
        echo "[ERROR] xorriso is required" >&2
        exit 1
    }
    command -v debugfs >/dev/null 2>&1 || {
        echo "[ERROR] debugfs is required (install e2fsprogs)" >&2
        exit 1
    }

    set_stage "qemu_prepare_assets"
    ensure_assets
    ensure_unattended_iso_current
    local disk iso
    disk="$(qemu_prepare_install_disk)"
    iso="$(qemu_iso_path)"
    if [ ! -f "$iso" ]; then
        echo "[ERROR] Unattended ISO not found: $iso" >&2
        exit 1
    fi
    echo "[INFO] QEMU unattended target disk: $disk"

    set_stage "qemu_launch_installer"
    qemu_stop
    qemu_start_with_media "$disk" "$iso" "d"
    local serial_capture_log serial_capture_pid
    local fsm_work_dir fsm_state_log
    serial_capture_log="$(realpath_repo "$QEMU_SERIAL_CAPTURE_LOG")"
    fsm_work_dir="$(realpath_repo "${RUN_DIR}/fsm")"
    fsm_state_log="${fsm_work_dir}/state.log"
    mkdir -p "$(dirname "$serial_capture_log")"
    mkdir -p "$fsm_work_dir"
    if [ -x "${SCRIPT_DIR}/capture-telnet-log.sh" ]; then
        echo "[STEP] Capturing installer serial output -> $serial_capture_log"
        "${SCRIPT_DIR}/capture-telnet-log.sh" \
            --port "$QEMU_SERIAL_PORT" \
            --seconds "$INSTALL_TIMEOUT_SEC" \
            --out "$serial_capture_log" >/dev/null 2>&1 &
        serial_capture_pid=$!
    fi
    set_stage "qemu_installer_fsm"
    echo "[STEP] Running installer FSM controller..."
    if [ "$FSM_BACKEND" = "serial" ]; then
        run_cmd env \
            SSH_HOST="127.0.0.1" \
            SSH_PORT="$QEMU_HOST_SSH_PORT" \
            MONITOR_HOST="127.0.0.1" \
            MONITOR_PORT="$QEMU_MONITOR_PORT" \
            SERIAL_LOG="$serial_capture_log" \
            FSM_TIMEOUT_SEC="$INSTALL_TIMEOUT_SEC" \
            FSM_POLL_MS="$FSM_POLL_MS" \
            STALL_TIMEOUT_SEC="$STALL_TIMEOUT_SEC" \
            STALL_PROBE_MODE="$STALL_PROBE_MODE" \
            STALL_PROBE_RETRY_COUNT="$STALL_PROBE_RETRY_COUNT" \
            STALL_PROBE_RETRY_TIMEOUT_SEC="$STALL_PROBE_RETRY_TIMEOUT_SEC" \
            STALL_CAPTURE_MAX_PAGES="$STALL_CAPTURE_MAX_PAGES" \
            STALL_PROBE_DIR="${fsm_work_dir}/stall-probe" \
            FSM_STATE_LOG="$fsm_state_log" \
            "${SCRIPT_DIR}/qemu-install-serial-fsm.sh"
    else
        if ! wait_tcp_port "127.0.0.1" "$QEMU_MONITOR_PORT" 30; then
            echo "[ERROR] QEMU monitor not reachable on port ${QEMU_MONITOR_PORT}" >&2
            exit 1
        fi
        run_cmd env \
            MONITOR_HOST="127.0.0.1" \
            MONITOR_PORT="$QEMU_MONITOR_PORT" \
            SSH_HOST="127.0.0.1" \
            SSH_PORT="$QEMU_HOST_SSH_PORT" \
            FSM_TIMEOUT_SEC="$INSTALL_TIMEOUT_SEC" \
            FSM_POLL_MS="$FSM_POLL_MS" \
            FSM_WORK_DIR="$fsm_work_dir" \
            FSM_STATE_LOG="$fsm_state_log" \
            "${SCRIPT_DIR}/qemu-install-fsm.expect"
    fi
    if [ -n "${serial_capture_pid:-}" ] && kill -0 "$serial_capture_pid" >/dev/null 2>&1; then
        kill "$serial_capture_pid" >/dev/null 2>&1 || true
        wait "$serial_capture_pid" >/dev/null 2>&1 || true
    fi

    set_stage "qemu_validate_installer_ssh"
    echo "[STEP] Validating installer completion via SSH auth..."
    wait_ssh "127.0.0.1" "$QEMU_HOST_SSH_PORT" 300

    set_stage "qemu_reboot_disk_only"
    echo "[STEP] Rebooting QEMU disk-only boot..."
    sshpass -p "$ROOT_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        -p "$QEMU_HOST_SSH_PORT" root@127.0.0.1 "shutdown -h now" >/dev/null 2>&1 || true
    sleep 10
    qemu_stop
    qemu_start_with_media "$disk" "" "c"
    set_stage "qemu_validate_post_reboot_ssh"
    wait_ssh "127.0.0.1" "$QEMU_HOST_SSH_PORT" "$BOOT_TIMEOUT_SEC"
    set_stage "qemu_provision_guest"
    provision_guest "127.0.0.1" "$QEMU_HOST_SSH_PORT"
}

run_backend_virtualbox() {
    echo "[WARN] VirtualBox backend is conceptual-only in this phase."
    run_cmd "${SCRIPT_DIR}/vboxmanage-hurd.sh" full-auto --profile "$PROFILE" --root-pass "$ROOT_PASS" --agents-pass "$AGENTS_PASS"
}

run_backend_podman() {
    command -v podman >/dev/null 2>&1 || {
        echo "[ERROR] podman not found" >&2
        exit 1
    }
    ensure_assets

    echo "[STEP] Starting installer run with Podman compose..."
    run_cmd env \
        PODMAN_COMPOSE_PROVIDER="$PODMAN_COMPOSE_PROVIDER" \
        CONTAINER_RUNTIME=podman \
        QEMU_CDROM="$QEMU_CDROM_AUTO" \
        QEMU_BOOT_ORDER=d \
        HURD_IMAGE_BASENAME="$HURD_IMAGE_BASENAME" \
        make up-podman-installer

    echo "[STEP] Waiting for installer completion (SSH)..."
    wait_ssh "127.0.0.1" "2222" "$INSTALL_TIMEOUT_SEC"

    echo "[STEP] Restarting stack disk-first (without installer media)..."
    run_cmd env PODMAN_COMPOSE_PROVIDER="$PODMAN_COMPOSE_PROVIDER" CONTAINER_RUNTIME=podman make down
    run_cmd env \
        PODMAN_COMPOSE_PROVIDER="$PODMAN_COMPOSE_PROVIDER" \
        CONTAINER_RUNTIME=podman \
        QEMU_CDROM= \
        QEMU_BOOT_ORDER=c \
        HURD_IMAGE_BASENAME="$HURD_IMAGE_BASENAME" \
        make up-podman

    wait_ssh "127.0.0.1" "2222" "$BOOT_TIMEOUT_SEC"
    provision_guest "127.0.0.1" "2222"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --backend) BACKEND="$2"; shift 2 ;;
        --profile) PROFILE="$2"; shift 2 ;;
        --root-pass) ROOT_PASS="$2"; shift 2 ;;
        --agents-pass) AGENTS_PASS="$2"; shift 2 ;;
        --skip-setup) SKIP_SETUP=1; shift ;;
        --skip-provision) SKIP_PROVISION=1; shift ;;
        --trace) TRACE=1; shift ;;
        --transcript) TRANSCRIPT_FILE="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "[ERROR] Unknown option: $1" >&2
            usage
            exit 2
            ;;
    esac
done

mkdir -p "$(dirname "$TRANSCRIPT_FILE")"
TRANSCRIPT_FILE="$(realpath_repo "$TRANSCRIPT_FILE")"
mkdir -p "$(dirname "$TRANSCRIPT_FILE")" "$(realpath_repo "$RUN_DIR")"
exec > >(tee -a "$TRANSCRIPT_FILE") 2>&1

if [ "$TRACE" = "1" ]; then
    set -x
fi

trap 'finalize_run_summary_on_error' ERR
trap 'cleanup_on_interrupt' INT TERM

echo "[INFO] Transcript: $TRANSCRIPT_FILE"
echo "[INFO] Run ID: $RUN_ID"
echo "[INFO] Run Directory: $(realpath_repo "$RUN_DIR")"
if [ "$BACKEND" = "auto" ]; then
    BACKEND="$(backend_auto_pick)"
fi
echo "[INFO] Selected backend: $BACKEND"

case "$BACKEND" in
    qemu) run_backend_qemu ;;
    virtualbox) run_backend_virtualbox ;;
    podman) run_backend_podman ;;
    *)
        echo "[ERROR] Unsupported backend: $BACKEND" >&2
        exit 2
        ;;
esac

RUN_STATUS="success"
RUN_FAILURE_TAG="none"
write_run_summary "$RUN_STATUS" "$RUN_FAILURE_TAG" "$(realpath_repo "${RUN_DIR}/fsm/state.log")" "$(realpath_repo "$QEMU_SERIAL_CAPTURE_LOG")"
echo "[SUCCESS] Unattended installer-to-SSH workflow complete on backend: $BACKEND"
