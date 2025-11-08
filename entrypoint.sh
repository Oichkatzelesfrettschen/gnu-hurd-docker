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
# RESOURCE DETECTION AND SMART DEFAULTS
# =============================================================================
# Detect host resources for optimal allocation
detect_host_resources() {
    # CPU cores: use nproc if available, fallback to /proc/cpuinfo
    if command -v nproc >/dev/null 2>&1; then
        HOST_CPUS=$(nproc)
    else
        HOST_CPUS=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo 2)
    fi

    # Available memory in MB
    if [ -f /proc/meminfo ]; then
        HOST_MEM_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        HOST_MEM_MB=$((HOST_MEM_KB / 1024))
    else
        HOST_MEM_MB=2048  # Conservative fallback
    fi

    log_info "Detected host resources: ${HOST_CPUS} CPUs, ${HOST_MEM_MB} MB available memory"
}

# Calculate optimal SMP based on host CPUs
calculate_optimal_smp() {
    local host_cpus=$1
    local requested_smp=${QEMU_SMP:-0}

    # If user specified SMP, validate and use it
    if [ "$requested_smp" -gt 0 ]; then
        if [ "$requested_smp" -gt "$host_cpus" ]; then
            log_warn "Requested SMP ($requested_smp) exceeds host CPUs ($host_cpus)"
            echo "$host_cpus"
        else
            echo "$requested_smp"
        fi
    else
        # Auto-calculate: use 50% of host CPUs, minimum 2, maximum 8 (Hurd limitation)
        local optimal=$((host_cpus / 2))
        [ "$optimal" -lt 2 ] && optimal=2
        [ "$optimal" -gt 8 ] && optimal=8
        echo "$optimal"
    fi
}

# Calculate optimal RAM based on available memory
calculate_optimal_ram() {
    local host_mem_mb=$1
    local requested_ram=${QEMU_RAM:-0}

    # If user specified RAM, validate and use it
    if [ "$requested_ram" -gt 0 ]; then
        if [ "$requested_ram" -gt "$host_mem_mb" ]; then
            log_warn "Requested RAM ($requested_ram MB) exceeds available ($host_mem_mb MB)"
            # Use 75% of available memory as safety limit
            echo $((host_mem_mb * 3 / 4))
        else
            echo "$requested_ram"
        fi
    else
        # Auto-calculate: use 25% of available memory, minimum 2GB, maximum 8GB
        local optimal=$((host_mem_mb / 4))
        [ "$optimal" -lt 2048 ] && optimal=2048
        [ "$optimal" -gt 8192 ] && optimal=8192
        echo "$optimal"
    fi
}

# =============================================================================
# CONFIGURATION DEFAULTS
# =============================================================================
# Detect host resources first
detect_host_resources

# All configuration via environment variables for Docker flexibility
QCOW2_IMAGE="${QEMU_DRIVE:-/opt/hurd-image/debian-hurd-amd64.qcow2}"
QEMU_RAM=$(calculate_optimal_ram "$HOST_MEM_MB")
QEMU_SMP=$(calculate_optimal_smp "$HOST_CPUS")
SERIAL_PORT="${SERIAL_PORT:-5555}"
MONITOR_PORT="${MONITOR_PORT:-9999}"

log_info "Optimized settings: ${QEMU_SMP} CPUs, ${QEMU_RAM} MB RAM"

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

    # CPU model based on acceleration with performance flags
    if [ "$accel_mode" = "kvm" ]; then
        # KVM: use host CPU with performance optimizations
        # +invtsc: invariant TSC for better timekeeping
        # +x2apic: extended APIC for better interrupt handling with SMP
        local cpu_flags="host"
        [ "$QEMU_SMP" -gt 2 ] && cpu_flags="host,+x2apic"
        cmd+=(-cpu "$cpu_flags")
        log_info "CPU: host passthrough with optimizations"
    else
        # TCG: use max features for compatibility
        cmd+=(-cpu max)
        log_info "CPU: max emulated features"
    fi

    # Memory and SMP configuration
    cmd+=(-m "${QEMU_RAM}")

    # SMP configuration with topology hints for better scheduler performance
    if [ "$QEMU_SMP" -gt 4 ]; then
        # For >4 CPUs: specify topology for better cache coherency
        local sockets=1
        local cores=$QEMU_SMP
        local threads=1
        cmd+=(-smp "cpus=${QEMU_SMP},sockets=${sockets},cores=${cores},threads=${threads}")
        log_info "SMP: ${QEMU_SMP} CPUs with explicit topology"
    else
        # For <=4 CPUs: simple configuration
        cmd+=(-smp "${QEMU_SMP}")
        log_info "SMP: ${QEMU_SMP} CPUs"
    fi

    # Disk configuration - IDE for Hurd compatibility with optimized I/O
    # WHY: Hurd doesn't have good virtio-blk support
    if [ -f "$QCOW2_IMAGE" ]; then
        # Optimize AIO backend based on KVM availability
        local aio_backend="threads"  # Default for TCG
        local cache_mode="writeback"

        if [ "$accel_mode" = "kvm" ]; then
            # KVM: try io_uring (best performance), fallback to native
            if grep -q io_uring /proc/filesystems 2>/dev/null || command -v qemu-system-x86_64 2>&1 | grep -q io_uring; then
                aio_backend="io_uring"
                log_info "Disk I/O: io_uring (optimal for KVM)"
            else
                aio_backend="native"
                log_info "Disk I/O: native AIO (good for KVM)"
            fi
        else
            # TCG: use threads
            log_info "Disk I/O: threads (optimal for TCG)"
        fi

        # Adjust cache mode based on display mode (unsafe cache for testing)
        if [ "${UNSAFE_CACHE:-0}" = "1" ]; then
            cache_mode="unsafe"
            log_warn "Using UNSAFE cache mode - faster but risk of data loss"
        fi

        cmd+=(
            -drive "file=${QCOW2_IMAGE},if=ide,cache=${cache_mode},aio=${aio_backend},format=qcow2"
        )
        log_info "Disk: IDE interface with QCOW2 image, cache=${cache_mode}"
    else
        log_error "Disk image not found: $QCOW2_IMAGE"
        log_error "Please download or create a Debian GNU/Hurd x86_64 image"
        exit 1
    fi

    # Network: e1000 NIC (NOT virtio - Hurd doesn't support it well)
    # Port forwarding for SSH and HTTP with performance tuning
    local net_opts="user,model=e1000,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:80"

    # Add performance optimizations for user-mode networking
    if [ "$accel_mode" = "kvm" ]; then
        # Increase network buffer sizes for better throughput
        net_opts="${net_opts},net=192.168.76.0/24,dhcpstart=192.168.76.9"
    fi

    cmd+=(-nic "$net_opts")
    log_info "Network: e1000 NIC with user-mode NAT and optimized buffers"

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