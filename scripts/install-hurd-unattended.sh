#!/bin/bash
set -euo pipefail

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

QEMU_RAM_MB="${QEMU_RAM_MB:-4096}"
QEMU_CPUS="${QEMU_CPUS:-2}"
QEMU_HOST_SSH_PORT="${QEMU_HOST_SSH_PORT:-2226}"
QEMU_SERIAL_PORT="${QEMU_SERIAL_PORT:-5566}"
QEMU_MONITOR_PORT="${QEMU_MONITOR_PORT:-9998}"
QEMU_PID_FILE="${QEMU_PID_FILE:-infrastructure/cache/images/qemu/hurd-unattended.pid}"
QEMU_STDOUT_LOG="${QEMU_STDOUT_LOG:-logs/hurd-unattended-qemu.log}"

INSTALL_TIMEOUT_SEC="${INSTALL_TIMEOUT_SEC:-3600}"
BOOT_TIMEOUT_SEC="${BOOT_TIMEOUT_SEC:-900}"

PODMAN_COMPOSE_PROVIDER="${PODMAN_COMPOSE_PROVIDER:-podman-compose}"
HURD_IMAGE_BASENAME="${HURD_IMAGE_BASENAME:-debian-hurd-amd64.fresh.qcow2}"
QEMU_CDROM_AUTO="/opt/hurd-installer/debian-hurd-amd64-installer.latest-mini-auto.iso"

TRACE="${TRACE:-0}"
TRANSCRIPT_FILE="${TRANSCRIPT_FILE:-logs/unattended-transcript-$(date -u +%Y%m%d-%H%M%S).log}"

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
  scripts/install-hurd-unattended.sh --backend virtualbox --profile dev
  scripts/install-hurd-unattended.sh --backend podman --skip-provision
EOF
}

run_cmd() {
    echo "+ $*"
    "$@"
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

qemu_iso_path() {
    realpath_repo "infrastructure/cache/images/installers/debian-hurd-amd64-installer.latest-mini-auto.iso"
}

backend_auto_pick() {
    if command -v VBoxManage >/dev/null 2>&1 && [ "$(uname -s)" = "Linux" ] && lsmod | grep -q '^vboxdrv'; then
        echo "virtualbox"
        return
    fi
    if command -v qemu-system-x86_64 >/dev/null 2>&1; then
        echo "qemu"
        return
    fi
    if command -v podman >/dev/null 2>&1; then
        echo "podman"
        return
    fi
    echo "[ERROR] Could not auto-pick backend (need VBoxManage, qemu-system-x86_64, or podman)" >&2
    exit 1
}

ensure_assets() {
    if [ "$SKIP_SETUP" = "1" ]; then
        echo "[INFO] Skipping installer asset setup (--skip-setup)"
        return
    fi
    run_cmd "${SCRIPT_DIR}/setup-hurd-amd64-daily-installer.sh"
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

    local -a cmd=(
        qemu-system-x86_64
        -name hurd-unattended
        -machine pc
        -accel "$accel"
        -cpu "$cpu"
        -m "$QEMU_RAM_MB"
        -smp "$QEMU_CPUS"
        -drive "file=${disk},if=ide,cache=writeback,aio=threads,format=qcow2"
        -boot "order=${boot_order}"
        -nic "user,model=e1000,hostfwd=tcp:127.0.0.1:${QEMU_HOST_SSH_PORT}-:22"
        -serial "tcp:127.0.0.1:${QEMU_SERIAL_PORT},server,nowait"
        -monitor "tcp:127.0.0.1:${QEMU_MONITOR_PORT},server,nowait"
        -display none
        -daemonize
        -pidfile "$pid_file"
    )

    if [ -n "$iso" ]; then
        cmd+=(-cdrom "$iso")
    fi

    echo "+ ${cmd[*]}"
    "${cmd[@]}"
    echo "[INFO] QEMU launched (SSH localhost:${QEMU_HOST_SSH_PORT}, serial ${QEMU_SERIAL_PORT}, monitor ${QEMU_MONITOR_PORT})"
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
    command -v sshpass >/dev/null 2>&1 || {
        echo "[ERROR] sshpass is required" >&2
        exit 1
    }

    ensure_assets
    local disk iso
    disk="$(qemu_disk_path)"
    iso="$(qemu_iso_path)"
    if [ ! -f "$disk" ]; then
        echo "[ERROR] Fresh disk not found: $disk" >&2
        echo "        Run scripts/setup-hurd-amd64-daily-installer.sh first." >&2
        exit 1
    fi
    if [ ! -f "$iso" ]; then
        echo "[ERROR] Unattended ISO not found: $iso" >&2
        exit 1
    fi

    qemu_stop
    qemu_start_with_media "$disk" "$iso" "d"
    echo "[STEP] Waiting for unattended installer completion..."
    wait_ssh "127.0.0.1" "$QEMU_HOST_SSH_PORT" "$INSTALL_TIMEOUT_SEC"

    echo "[STEP] Rebooting QEMU disk-only boot..."
    sshpass -p "$ROOT_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        -p "$QEMU_HOST_SSH_PORT" root@127.0.0.1 "shutdown -h now" >/dev/null 2>&1 || true
    sleep 10
    qemu_stop
    qemu_start_with_media "$disk" "" "c"
    wait_ssh "127.0.0.1" "$QEMU_HOST_SSH_PORT" "$BOOT_TIMEOUT_SEC"
    provision_guest "127.0.0.1" "$QEMU_HOST_SSH_PORT"
}

run_backend_virtualbox() {
    ensure_assets
    if [ "$SKIP_PROVISION" = "1" ]; then
        run_cmd "${SCRIPT_DIR}/vboxmanage-hurd.sh" install-auto --profile "$PROFILE" --root-pass "$ROOT_PASS" --agents-pass "$AGENTS_PASS" --skip-setup
    else
        run_cmd "${SCRIPT_DIR}/vboxmanage-hurd.sh" full-auto --profile "$PROFILE" --root-pass "$ROOT_PASS" --agents-pass "$AGENTS_PASS" --skip-setup
    fi
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
exec > >(tee -a "$TRANSCRIPT_FILE") 2>&1

if [ "$TRACE" = "1" ]; then
    set -x
fi

echo "[INFO] Transcript: $TRANSCRIPT_FILE"
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

echo "[SUCCESS] Unattended installer-to-SSH workflow complete on backend: $BACKEND"
