#!/bin/bash
# =============================================================================
# Pure x86_64 Debian GNU/Hurd QEMU Launcher with Smart KVM/TCG Detection
# =============================================================================
# PURPOSE:
# - Launch QEMU with x86_64-only configuration
# - Automatically detect and use KVM when available
# - Gracefully fall back to TCG when KVM unavailable
# - Configure optimal settings for Hurd's requirements
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output (makes debugging easier)
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
# shellcheck disable=SC2034  # Reserved for future use
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# =============================================================================
# CONFIGURATION DEFAULTS
# =============================================================================
# All configuration via environment variables for Docker flexibility
QCOW2_IMAGE="${QEMU_DRIVE:-/opt/hurd-image/debian-hurd-amd64.qcow2}"
QEMU_RAM="${QEMU_RAM:-2048}"
QEMU_SMP="${QEMU_SMP:-2}"
SERIAL_PORT="${SERIAL_PORT:-5555}"
MONITOR_PORT="${MONITOR_PORT:-9999}"

# =============================================================================
# ARCHITECTURE VERIFICATION - x86_64 ONLY!
# =============================================================================
verify_x86_64_only() {
    # Verify host architecture
    if [ "$(uname -m)" != "x86_64" ]; then
        log_error "This container requires x86_64 host architecture"
        exit 1
    fi

    # Verify QEMU x86_64 binary exists (with underscore!)
    if [ ! -x /usr/bin/qemu-system-x86_64 ]; then
        log_error "qemu-system-x86_64 binary not found or not executable"
        log_error "Path should be: /usr/bin/qemu-system-x86_64"
        exit 1
    fi

    log_info "Architecture verified: x86_64-only configuration"
}

# =============================================================================
# KVM AVAILABILITY DETECTION
# =============================================================================
detect_acceleration() {
    # Try KVM first, fall back to TCG
    # This matches the recommended pattern: -accel kvm -accel tcg,thread=multi

    if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        # KVM is available
        echo "kvm"
        log_info "KVM hardware acceleration detected and will be used"
        log_info "CPU model: host (full CPU passthrough)"
    else
        # Fall back to TCG
        echo "tcg"
        log_warn "KVM not available, using TCG software emulation"
        log_warn "To enable KVM, run container with: --device=/dev/kvm"
        log_info "CPU model: max (all emulated features enabled)"
    fi
}

# =============================================================================
# BUILD QEMU COMMAND LINE
# =============================================================================
build_qemu_command() {
    local accel_mode
    accel_mode=$(detect_acceleration)

    # Start with base command - ALWAYS x86_64 binary
    local -a cmd=(/usr/bin/qemu-system-x86_64)

    # Machine type: pc (i440fx) for Hurd compatibility
    # WHY: Hurd has better support for legacy PC hardware than Q35
    cmd+=(-machine pc)

    # Acceleration with automatic fallback
    # This follows the ChatGPT guide recommendation
    cmd+=(-accel kvm -accel "tcg,thread=multi")

    # CPU model based on acceleration
    if [ "$accel_mode" = "kvm" ]; then
        cmd+=(-cpu host)  # Full passthrough with KVM
    else
        cmd+=(-cpu max)   # Maximum features with TCG
    fi

    # Memory and SMP
    cmd+=(-m "${QEMU_RAM}")
    cmd+=(-smp "${QEMU_SMP}")

    # Disk configuration - IDE for Hurd compatibility
    # WHY: Hurd doesn't have good virtio-blk support
    if [ -f "$QCOW2_IMAGE" ]; then
        cmd+=(
            -drive "file=${QCOW2_IMAGE},if=ide,cache=writeback,aio=threads,format=qcow2"
        )
        log_info "Disk: IDE interface with QCOW2 image"
    else
        log_error "Disk image not found: $QCOW2_IMAGE"
        log_error "Please download or create a Debian GNU/Hurd x86_64 image"
        exit 1
    fi

    # Network: e1000 NIC (NOT virtio - Hurd doesn't support it well)
    # Port forwarding for SSH and HTTP
    cmd+=(
        -nic "user,model=e1000,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:80"
    )
    log_info "Network: e1000 NIC with user-mode NAT"

    # Serial console and monitor
    cmd+=(
        -serial "telnet:0.0.0.0:${SERIAL_PORT},server,nowait"
        -monitor "telnet:0.0.0.0:${MONITOR_PORT},server,nowait"
    )

    # Display options
    if [ "${ENABLE_VNC:-0}" = "1" ]; then
        cmd+=(-vnc :0)
        log_info "VNC enabled on port 5900"
    else
        cmd+=(-nographic)
        log_info "Running headless (serial console only)"
    fi

    # RTC for proper timekeeping
    cmd+=(-rtc "base=utc,clock=host")

    # Disable reboot on exit
    cmd+=(-no-reboot)

    # Enable guest error logging (to /tmp which is writable)
    cmd+=(-d guest_errors -D /tmp/qemu-guest-errors.log)

    echo "${cmd[@]}"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================
main() {
    echo ""
    echo "=============================================================================="
    echo "  Pure x86_64 Debian GNU/Hurd QEMU Environment"
    echo "=============================================================================="
    echo ""

    # Verify x86_64-only setup
    verify_x86_64_only

    # Build command
    local qemu_cmd
    qemu_cmd=$(build_qemu_command)

    echo "Configuration:"
    echo "  - Binary: /usr/bin/qemu-system-x86_64"
    echo "  - Image: ${QCOW2_IMAGE}"
    echo "  - Memory: ${QEMU_RAM} MB"
    echo "  - CPUs: ${QEMU_SMP}"
    echo "  - Machine: pc (i440fx)"
    echo "  - Disk: IDE interface (Hurd compatible)"
    echo "  - Network: e1000 (Hurd compatible)"
    echo ""
    echo "Port Forwarding:"
    echo "  - SSH: localhost:2222 -> guest:22"
    echo "  - HTTP: localhost:8080 -> guest:80"
    echo ""
    echo "Management:"
    echo "  - Serial: telnet localhost:${SERIAL_PORT}"
    echo "  - Monitor: telnet localhost:${MONITOR_PORT}"
    echo ""
    echo "=============================================================================="
    echo ""
    echo "Starting QEMU..."
    echo ""

    # Ensure log directory exists with correct permissions
    mkdir -p /var/log/qemu
    chown -R hurd:hurd /var/log/qemu 2>/dev/null || true

    # Execute QEMU (run as root for testing - volume permission issues)
    # shellcheck disable=SC2086
    exec $qemu_cmd "$@"
}

# Signal handling for graceful shutdown
trap 'log_info "Shutting down..."; exit 0' SIGTERM SIGINT

# Run main
main "$@"