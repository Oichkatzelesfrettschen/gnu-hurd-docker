#!/bin/bash
# =============================================================================
# Standalone QEMU Launcher for Debian GNU/Hurd x86_64
# =============================================================================
# PURPOSE:
# - Launch GNU/Hurd QEMU VM without Docker
# - Automatic KVM detection with TCG fallback
# - Simple configuration via environment variables or CLI args
# - Based on release-qemu-image.yml and entrypoint.sh best practices
# =============================================================================
# USAGE:
#   ./run-hurd-qemu.sh [OPTIONS]
#
# OPTIONS:
#   -i, --image PATH       Path to QCOW2 image (default: auto-detect)
#   -m, --memory MB        RAM in MB (default: 4096)
#   -c, --cpus NUM         CPU cores (default: 2)
#   -p, --ssh-port PORT    SSH port forwarding (default: 2222)
#   -s, --serial PORT      Serial console port (default: 5555)
#   --no-kvm               Disable KVM, force TCG emulation
#   --vnc DISPLAY          Enable VNC on display (e.g., :0)
#   --help                 Show this help message
#
# EXAMPLES:
#   # Basic usage (auto-detect image in current or images/ directory)
#   ./run-hurd-qemu.sh
#
#   # Specify custom image and resources
#   ./run-hurd-qemu.sh --image ~/hurd/debian-hurd-amd64.qcow2 --memory 8192 --cpus 4
#
#   # Force TCG emulation (no KVM)
#   ./run-hurd-qemu.sh --no-kvm
#
#   # Enable VNC display
#   ./run-hurd-qemu.sh --vnc :0
#
# ENVIRONMENT VARIABLES:
#   QEMU_IMAGE             Path to QCOW2 image
#   QEMU_RAM               RAM in MB
#   QEMU_SMP               CPU cores
#   SSH_PORT               SSH port forwarding
#   SERIAL_PORT            Serial console port
#   DISABLE_KVM            Set to 1 to force TCG
# =============================================================================

set -euo pipefail

# =============================================================================
# COLOR OUTPUT
# =============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $*" >&2
}

# =============================================================================
# HELP TEXT
# =============================================================================
show_help() {
    cat <<'EOF'
Standalone QEMU Launcher for Debian GNU/Hurd x86_64

USAGE:
  ./run-hurd-qemu.sh [OPTIONS]

OPTIONS:
  -i, --image PATH       Path to QCOW2 image (default: auto-detect)
  -m, --memory MB        RAM in MB (default: 4096)
  -c, --cpus NUM         CPU cores (default: 2)
  -p, --ssh-port PORT    SSH port forwarding (default: 2222)
  -s, --serial PORT      Serial console port (default: 5555)
  --no-kvm               Disable KVM, force TCG emulation
  --vnc DISPLAY          Enable VNC on display (e.g., :0)
  --help                 Show this help message

EXAMPLES:
  # Basic usage (auto-detect image)
  ./run-hurd-qemu.sh

  # Custom configuration
  ./run-hurd-qemu.sh --image ~/debian-hurd-amd64.qcow2 --memory 8192 --cpus 4

  # Force TCG (no KVM)
  ./run-hurd-qemu.sh --no-kvm

  # With VNC display
  ./run-hurd-qemu.sh --vnc :0

ENVIRONMENT VARIABLES:
  QEMU_IMAGE             Override image path
  QEMU_RAM               Override RAM (MB)
  QEMU_SMP               Override CPU cores
  SSH_PORT               Override SSH port
  SERIAL_PORT            Override serial port
  DISABLE_KVM            Set to 1 to force TCG

DEFAULT CREDENTIALS:
  SSH:     ssh -p 2222 root@localhost
  User:    root
  Pass:    root (or press Enter)

MORE INFO:
  Repository: https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker
  Documentation: docs/01-GETTING-STARTED/STANDALONE-QEMU.md

EOF
}

# =============================================================================
# CONFIGURATION DEFAULTS
# =============================================================================
QEMU_IMAGE="${QEMU_IMAGE:-}"
QEMU_RAM="${QEMU_RAM:-4096}"
QEMU_SMP="${QEMU_SMP:-2}"
SSH_PORT="${SSH_PORT:-2222}"
SERIAL_PORT="${SERIAL_PORT:-5555}"
MONITOR_PORT="${MONITOR_PORT:-9999}"
DISABLE_KVM="${DISABLE_KVM:-0}"
VNC_DISPLAY=""

# =============================================================================
# ARGUMENT PARSING
# =============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--image)
                QEMU_IMAGE="$2"
                shift 2
                ;;
            -m|--memory)
                QEMU_RAM="$2"
                shift 2
                ;;
            -c|--cpus)
                QEMU_SMP="$2"
                shift 2
                ;;
            -p|--ssh-port)
                SSH_PORT="$2"
                shift 2
                ;;
            -s|--serial)
                SERIAL_PORT="$2"
                shift 2
                ;;
            --no-kvm)
                DISABLE_KVM=1
                shift
                ;;
            --vnc)
                VNC_DISPLAY="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information" >&2
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# IMAGE AUTO-DETECTION
# =============================================================================
auto_detect_image() {
    local search_paths=(
        "debian-hurd-amd64.qcow2"
        "images/debian-hurd-amd64.qcow2"
        "../images/debian-hurd-amd64.qcow2"
        "debian-hurd-amd64-80gb.qcow2"
        "images/debian-hurd-amd64-80gb.qcow2"
    )

    for path in "${search_paths[@]}"; do
        if [[ -f "$path" ]]; then
            log_info "Auto-detected QCOW2 image: $path"
            echo "$path"
            return 0
        fi
    done

    log_error "Could not auto-detect QCOW2 image"
    log_error "Searched: ${search_paths[*]}"
    log_error "Please specify image with --image PATH"
    exit 1
}

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================
check_prerequisites() {
    log_step "Checking prerequisites..."

    # Check for qemu-system-x86_64
    if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
        log_error "qemu-system-x86_64 not found in PATH"
        log_error "Please install QEMU: sudo pacman -S qemu-base"
        exit 1
    fi

    local qemu_version
    qemu_version=$(qemu-system-x86_64 --version | head -1)
    log_info "QEMU: $qemu_version"

    # Verify architecture
    if [[ "$(uname -m)" != "x86_64" ]]; then
        log_error "This script requires x86_64 host architecture"
        exit 1
    fi

    log_info "Architecture: x86_64 ✓"
}

# =============================================================================
# KVM DETECTION
# =============================================================================
detect_kvm() {
    if [[ "$DISABLE_KVM" == "1" ]]; then
        log_warn "KVM disabled by user (--no-kvm or DISABLE_KVM=1)"
        echo "tcg"
        return
    fi

    if [[ -e /dev/kvm ]] && [[ -r /dev/kvm ]] && [[ -w /dev/kvm ]]; then
        log_info "KVM acceleration: ENABLED ✓"
        echo "kvm"
    else
        log_warn "KVM acceleration: NOT AVAILABLE"
        if [[ -e /dev/kvm ]]; then
            log_warn "Hint: Check /dev/kvm permissions (may need to add user to 'kvm' group)"
        else
            log_warn "Hint: Ensure VT-x/AMD-V is enabled in BIOS and KVM kernel module is loaded"
        fi
        log_info "Falling back to TCG software emulation (slower but works)"
        echo "tcg"
    fi
}

# =============================================================================
# BUILD QEMU COMMAND
# =============================================================================
build_qemu_command() {
    local accel_mode
    accel_mode=$(detect_kvm)

    log_step "Building QEMU command..."

    local -a cmd=(qemu-system-x86_64)

    # Machine type: pc (i440FX) for Hurd compatibility
    cmd+=(-machine pc)

    # Acceleration with automatic fallback
    cmd+=(-accel kvm -accel "tcg,thread=multi")

    # CPU model
    if [[ "$accel_mode" == "kvm" ]]; then
        cmd+=(-cpu host)
        log_info "CPU: host passthrough (KVM)"
    else
        cmd+=(-cpu max)
        log_info "CPU: max features (TCG emulation)"
    fi

    # Memory and SMP
    cmd+=(-m "$QEMU_RAM")
    cmd+=(-smp "$QEMU_SMP")
    log_info "Resources: ${QEMU_RAM} MB RAM, ${QEMU_SMP} CPU cores"

    # Storage: IDE with writeback cache for better performance
    cmd+=(-drive "file=$QEMU_IMAGE,if=ide,cache=writeback,aio=threads")
    log_info "Disk: $QEMU_IMAGE"

    # Network: E1000 NIC with SSH port forwarding
    cmd+=(-nic "user,model=e1000,hostfwd=tcp::${SSH_PORT}-:22")
    log_info "Network: SSH forwarded to localhost:${SSH_PORT}"

    # Serial console (telnet access)
    cmd+=(-serial "telnet::${SERIAL_PORT},server,nowait")
    log_info "Serial console: telnet localhost:${SERIAL_PORT}"

    # QEMU monitor (for snapshots, debugging)
    cmd+=(-monitor "telnet::${MONITOR_PORT},server,nowait")
    log_info "QEMU monitor: telnet localhost:${MONITOR_PORT}"

    # Display mode
    if [[ -n "$VNC_DISPLAY" ]]; then
        cmd+=(-vnc "$VNC_DISPLAY")
        log_info "Display: VNC on $VNC_DISPLAY"
    else
        cmd+=(-nographic)
        log_info "Display: nographic (serial console only)"
    fi

    echo "${cmd[@]}"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================
main() {
    # Parse command-line arguments
    parse_args "$@"

    # Show banner
    echo ""
    echo "=================================================================="
    echo "  Debian GNU/Hurd x86_64 - Standalone QEMU Launcher"
    echo "=================================================================="
    echo ""

    # Check prerequisites
    check_prerequisites

    # Auto-detect image if not specified
    if [[ -z "$QEMU_IMAGE" ]]; then
        QEMU_IMAGE=$(auto_detect_image)
    fi

    # Verify image exists
    if [[ ! -f "$QEMU_IMAGE" ]]; then
        log_error "QCOW2 image not found: $QEMU_IMAGE"
        exit 1
    fi

    # Show image info
    log_step "Image information:"
    if command -v qemu-img >/dev/null 2>&1; then
        qemu-img info "$QEMU_IMAGE" | grep -E "^(file format|virtual size|disk size)" | sed 's/^/  /'
    fi

    # Build and display QEMU command
    echo ""
    log_step "Launching QEMU..."
    local qemu_cmd
    qemu_cmd=$(build_qemu_command)

    echo ""
    echo "=================================================================="
    echo "  Starting GNU/Hurd VM"
    echo "=================================================================="
    echo ""
    log_info "Boot time: ~30-60 seconds (KVM) or ~3-5 minutes (TCG)"
    log_info "SSH access: ssh -p ${SSH_PORT} root@localhost"
    log_info "Password: root (or press Enter)"
    log_info ""
    log_info "Serial console: telnet localhost:${SERIAL_PORT}"
    log_info "QEMU monitor: telnet localhost:${MONITOR_PORT}"
    echo ""
    log_info "Press Ctrl+A then X to quit QEMU"
    echo ""

    # Execute QEMU
    # shellcheck disable=SC2086
    exec $qemu_cmd
}

# Run main function with all arguments
main "$@"
