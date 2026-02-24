#!/bin/bash
set -euo pipefail

# VirtualBox automation for unattended Debian GNU/Hurd amd64 install/provision.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

VBOX_ENV_FILE="${VBOX_ENV_FILE:-${REPO_ROOT}/config/virtualbox/hurd-amd64.env}"

load_env_file() {
    if [ -f "$VBOX_ENV_FILE" ]; then
        # shellcheck disable=SC1090
        source "$VBOX_ENV_FILE"
    fi
}

load_env_file

VBOX_VM_NAME="${VBOX_VM_NAME:-gnu-hurd-amd64-auto}"
VBOX_OS_TYPE="${VBOX_OS_TYPE:-Debian_64}"
VBOX_RAM_MB="${VBOX_RAM_MB:-4096}"
VBOX_CPUS="${VBOX_CPUS:-2}"
VBOX_VRAM_MB="${VBOX_VRAM_MB:-16}"
VBOX_CONTROLLER_NAME="${VBOX_CONTROLLER_NAME:-SATA Controller}"
VBOX_DISK_PATH="${VBOX_DISK_PATH:-infrastructure/cache/images/virtualbox/gnu-hurd-amd64-auto.vdi}"
VBOX_DISK_SIZE_MB="${VBOX_DISK_SIZE_MB:-40960}"
VBOX_ISO_PATH="${VBOX_ISO_PATH:-infrastructure/cache/images/installers/debian-hurd-amd64-installer.latest-mini-auto.iso}"
VBOX_NATPF_RULE_NAME="${VBOX_NATPF_RULE_NAME:-ssh}"
VBOX_HOST_SSH_PORT="${VBOX_HOST_SSH_PORT:-2224}"
VBOX_UART_PORT="${VBOX_UART_PORT:-4555}"
VBOX_INSTALL_TIMEOUT_SEC="${VBOX_INSTALL_TIMEOUT_SEC:-3600}"
VBOX_BOOT_TIMEOUT_SEC="${VBOX_BOOT_TIMEOUT_SEC:-600}"
ROOT_PASS="${ROOT_PASS:-root}"
AGENTS_PASS="${AGENTS_PASS:-agents}"
PROFILE="${PROFILE:-x11}"
SKIP_SETUP=0

usage() {
    cat <<'EOF'
Usage: scripts/vboxmanage-hurd.sh <command> [options]

Commands:
  doctor         Check host and VirtualBox prerequisites
  create         Create/update VM and attach disk
  start          Start VM headless
  stop           Graceful stop (fallback poweroff)
  status         Show VM info/state
  attach-iso     Attach unattended installer ISO and boot from DVD first
  detach-iso     Detach installer ISO and boot from disk first
  install-auto   Setup installer assets, create VM, boot unattended install, wait for SSH
  provision      Provision guest to dev/x11 baseline over SSH
  full-auto      install-auto + provision
  destroy        Unregister and delete VM

Options:
  --config PATH          Alternative env file (default: config/virtualbox/hurd-amd64.env)
  --profile dev|x11      Provisioning profile (default: x11)
  --root-pass PASS       Root password for SSH checks/provision (default: root)
  --agents-pass PASS     Agents password for provisioning (default: agents)
  --skip-setup           Skip scripts/setup-hurd-amd64-daily-installer.sh in install-auto/full-auto
  -h, --help             Show this help
EOF
}

realpath_repo() {
    local value="$1"
    if [ -z "$value" ]; then
        echo ""
        return
    fi
    if [[ "$value" = /* ]]; then
        echo "$value"
        return
    fi
    echo "${REPO_ROOT}/${value}"
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "[ERROR] Required command not found: $1" >&2
        exit 1
    fi
}

require_vbox() {
    require_cmd VBoxManage
}

has_vm() {
    VBoxManage list vms | grep -Fq "\"${VBOX_VM_NAME}\""
}

vm_is_running() {
    VBoxManage list runningvms | grep -Fq "\"${VBOX_VM_NAME}\""
}

check_vboxdrv_linux() {
    if [ "$(uname -s)" != "Linux" ]; then
        return 0
    fi
    # Avoid pipefail + grep -q SIGPIPE false-negatives by checking /proc/modules directly.
    if [ -r /proc/modules ] && grep -q '^vboxdrv ' /proc/modules; then
        return 0
    fi
    echo "[ERROR] VirtualBox kernel module 'vboxdrv' is not loaded." >&2
    echo "        Run (Arch/CachyOS): sudo -A rcvboxdrv setup" >&2
    echo "        Run (Debian/Ubuntu): sudo -A /sbin/vboxconfig" >&2
    return 1
}

doctor() {
    require_vbox
    local version
    version="$(VBoxManage --version)"
    echo "[OK] VBoxManage: ${version}"
    if check_vboxdrv_linux; then
        echo "[OK] vboxdrv is loaded"
    else
        exit 1
    fi
    if [ -f "$VBOX_ISO_PATH" ]; then
        echo "[OK] Installer ISO exists: $VBOX_ISO_PATH"
    else
        echo "[WARN] Installer ISO missing: $VBOX_ISO_PATH"
        echo "       Run: make setup-daily-installer"
    fi
    if [ -f "$VBOX_DISK_PATH" ]; then
        echo "[OK] VM disk exists: $VBOX_DISK_PATH"
    else
        echo "[INFO] VM disk will be created: $VBOX_DISK_PATH"
    fi
}

create_or_update_vm() {
    require_vbox
    check_vboxdrv_linux >/dev/null

    mkdir -p "$(dirname "$VBOX_DISK_PATH")"

    if has_vm; then
        echo "[INFO] VM exists: $VBOX_VM_NAME"
    else
        echo "[STEP] Creating VM: $VBOX_VM_NAME"
        VBoxManage createvm --name "$VBOX_VM_NAME" --ostype "$VBOX_OS_TYPE" --register >/dev/null
    fi

    VBoxManage modifyvm "$VBOX_VM_NAME" \
        --memory "$VBOX_RAM_MB" \
        --cpus "$VBOX_CPUS" \
        --vram "$VBOX_VRAM_MB" \
        --chipset piix3 \
        --ioapic on \
        --hpet on \
        --rtcuseutc on \
        --nic1 nat \
        --audio-enabled off \
        --usbxhci off \
        --boot1 dvd \
        --boot2 disk \
        --boot3 none \
        --boot4 none >/dev/null

    # Reset NAT SSH forwarding rule to deterministic mapping.
    VBoxManage modifyvm "$VBOX_VM_NAME" --natpf1 delete "$VBOX_NATPF_RULE_NAME" >/dev/null 2>&1 || true
    VBoxManage modifyvm "$VBOX_VM_NAME" \
        --natpf1 "${VBOX_NATPF_RULE_NAME},tcp,127.0.0.1,${VBOX_HOST_SSH_PORT},,22" >/dev/null

    # Serial-over-TCP for diagnostics.
    VBoxManage modifyvm "$VBOX_VM_NAME" \
        --uart1 0x3F8 4 \
        --uartmode1 "tcpserver,127.0.0.1:${VBOX_UART_PORT}" >/dev/null

    VBoxManage storagectl "$VBOX_VM_NAME" \
        --name "$VBOX_CONTROLLER_NAME" \
        --add sata \
        --controller IntelAhci \
        --portcount 4 \
        --hostiocache on >/dev/null 2>&1 || true

    if [ -f "$VBOX_DISK_PATH" ]; then
        echo "[INFO] Using existing disk: $VBOX_DISK_PATH"
    else
        echo "[STEP] Creating VDI disk: $VBOX_DISK_PATH (${VBOX_DISK_SIZE_MB} MB)"
        VBoxManage createmedium disk --filename "$VBOX_DISK_PATH" --size "$VBOX_DISK_SIZE_MB" --format VDI >/dev/null
    fi

    VBoxManage storageattach "$VBOX_VM_NAME" \
        --storagectl "$VBOX_CONTROLLER_NAME" \
        --port 0 --device 0 \
        --type hdd \
        --medium "$VBOX_DISK_PATH" >/dev/null

    echo "[OK] VM ready: $VBOX_VM_NAME"
}

attach_iso() {
    require_vbox
    if ! has_vm; then
        echo "[ERROR] VM not found: $VBOX_VM_NAME (run 'create' first)" >&2
        exit 1
    fi
    if [ ! -f "$VBOX_ISO_PATH" ]; then
        echo "[ERROR] ISO not found: $VBOX_ISO_PATH" >&2
        echo "        Run: make setup-daily-installer" >&2
        exit 1
    fi
    VBoxManage storageattach "$VBOX_VM_NAME" \
        --storagectl "$VBOX_CONTROLLER_NAME" \
        --port 1 --device 0 \
        --type dvddrive \
        --medium "$VBOX_ISO_PATH" >/dev/null
    VBoxManage modifyvm "$VBOX_VM_NAME" --boot1 dvd --boot2 disk --boot3 none --boot4 none >/dev/null
    echo "[OK] ISO attached: $VBOX_ISO_PATH"
}

detach_iso() {
    require_vbox
    if ! has_vm; then
        echo "[ERROR] VM not found: $VBOX_VM_NAME" >&2
        exit 1
    fi
    VBoxManage storageattach "$VBOX_VM_NAME" \
        --storagectl "$VBOX_CONTROLLER_NAME" \
        --port 1 --device 0 \
        --type dvddrive \
        --medium none >/dev/null 2>&1 || true
    VBoxManage modifyvm "$VBOX_VM_NAME" --boot1 disk --boot2 none --boot3 none --boot4 none >/dev/null
    echo "[OK] ISO detached; boot order set to disk first"
}

start_vm() {
    require_vbox
    if ! has_vm; then
        echo "[ERROR] VM not found: $VBOX_VM_NAME (run 'create' first)" >&2
        exit 1
    fi
    if vm_is_running; then
        echo "[INFO] VM already running: $VBOX_VM_NAME"
        return 0
    fi
    VBoxManage startvm "$VBOX_VM_NAME" --type headless >/dev/null
    echo "[OK] VM started headless: $VBOX_VM_NAME"
}

stop_vm() {
    require_vbox
    if ! has_vm; then
        echo "[INFO] VM not found: $VBOX_VM_NAME"
        return 0
    fi
    if ! vm_is_running; then
        echo "[INFO] VM already stopped: $VBOX_VM_NAME"
        return 0
    fi
    echo "[STEP] Sending ACPI shutdown..."
    VBoxManage controlvm "$VBOX_VM_NAME" acpipowerbutton >/dev/null || true
    local waited=0
    while vm_is_running && [ "$waited" -lt 90 ]; do
        sleep 2
        waited=$((waited + 2))
    done
    if vm_is_running; then
        echo "[WARN] ACPI shutdown timed out; forcing poweroff"
        VBoxManage controlvm "$VBOX_VM_NAME" poweroff >/dev/null || true
    fi
    echo "[OK] VM stopped: $VBOX_VM_NAME"
}

status_vm() {
    require_vbox
    if ! has_vm; then
        echo "[INFO] VM not found: $VBOX_VM_NAME"
        return 0
    fi
    VBoxManage showvminfo "$VBOX_VM_NAME"
}

destroy_vm() {
    require_vbox
    if ! has_vm; then
        echo "[INFO] VM not found: $VBOX_VM_NAME"
        return 0
    fi
    if vm_is_running; then
        stop_vm
    fi
    echo "[STEP] Unregistering VM: $VBOX_VM_NAME"
    VBoxManage unregistervm "$VBOX_VM_NAME" --delete >/dev/null || true
    echo "[OK] VM removed: $VBOX_VM_NAME"
}

wait_for_install_ssh() {
    HOST="127.0.0.1" \
    PORT="$VBOX_HOST_SSH_PORT" \
    USER_NAME="root" \
    PASSWORD="$ROOT_PASS" \
    TIMEOUT_SEC="$VBOX_INSTALL_TIMEOUT_SEC" \
    "${SCRIPT_DIR}/wait-for-guest-ssh.sh"
}

install_auto() {
    if [ "$SKIP_SETUP" != "1" ]; then
        "${SCRIPT_DIR}/setup-hurd-amd64-daily-installer.sh"
    fi
    create_or_update_vm
    attach_iso
    start_vm

    echo "[STEP] Waiting for unattended install to finish and SSH to come up..."
    wait_for_install_ssh

    echo "[STEP] Switching VM to disk-first boot..."
    detach_iso
    echo "[OK] Automated install reached SSH-ready state on localhost:${VBOX_HOST_SSH_PORT}"
}

provision_vm() {
    HOST="127.0.0.1" \
    PORT="$VBOX_HOST_SSH_PORT" \
    ROOT_PASS="$ROOT_PASS" \
    AGENTS_PASS="$AGENTS_PASS" \
    PROFILE="$PROFILE" \
    TIMEOUT_SEC="$VBOX_BOOT_TIMEOUT_SEC" \
    "${SCRIPT_DIR}/provision-hurd-x11.sh"
}

full_auto() {
    install_auto
    provision_vm
    echo "[SUCCESS] VirtualBox unattended install + provisioning complete."
}

COMMAND="${1:-help}"
if [ $# -gt 0 ]; then
    shift
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --config)
            VBOX_ENV_FILE="$2"
            load_env_file
            shift 2
            ;;
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --root-pass)
            ROOT_PASS="$2"
            shift 2
            ;;
        --agents-pass)
            AGENTS_PASS="$2"
            shift 2
            ;;
        --skip-setup)
            SKIP_SETUP=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[ERROR] Unknown option: $1" >&2
            usage
            exit 2
            ;;
    esac
done

VBOX_DISK_PATH="$(realpath_repo "$VBOX_DISK_PATH")"
VBOX_ISO_PATH="$(realpath_repo "$VBOX_ISO_PATH")"

case "$COMMAND" in
    doctor) doctor ;;
    create) create_or_update_vm ;;
    start) start_vm ;;
    stop) stop_vm ;;
    status) status_vm ;;
    attach-iso) attach_iso ;;
    detach-iso) detach_iso ;;
    install-auto) install_auto ;;
    provision) provision_vm ;;
    full-auto) full_auto ;;
    destroy) destroy_vm ;;
    help|-h|--help)
        usage
        ;;
    *)
        echo "[ERROR] Unknown command: $COMMAND" >&2
        usage
        exit 2
        ;;
esac
