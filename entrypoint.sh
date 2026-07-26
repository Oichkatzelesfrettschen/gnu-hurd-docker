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
# PRIVILEGE/OWNERSHIP MANAGEMENT
# =============================================================================
ensure_kvm_group_membership() {
    if [ "$(id -u)" -ne 0 ]; then
        return 0
    fi
    if [ ! -e /dev/kvm ]; then
        return 0
    fi

    local kvm_gid group_name
    kvm_gid="$(stat -c %g /dev/kvm 2>/dev/null || echo "")"
    if [ -z "$kvm_gid" ]; then
        return 0
    fi

    group_name="$(getent group "$kvm_gid" | cut -d: -f1 || true)"
    if [ -z "$group_name" ]; then
        group_name="kvm"
        groupadd -g "$kvm_gid" "$group_name" 2>/dev/null || true
    fi

    usermod -aG "$group_name" hurd 2>/dev/null || true
}

mount_is_bind() {
    # Returns 0 when PATH is a bind mount (subtree mount), 1 otherwise.
    # Heuristic: in /proc/self/mountinfo, bind mounts typically have a "root"
    # different than "/". Engine-managed volumes typically mount with root "/".
    local target="${1:?path required}"
    local line root mount_point
    while IFS= read -r line; do
        # mountinfo fields: id parent major:minor root mount_point ...
        # We only need root (4th) and mount_point (5th).
        root="$(printf '%s\n' "$line" | awk '{print $4}')"
        mount_point="$(printf '%s\n' "$line" | awk '{print $5}')"
        if [ "$mount_point" = "$target" ]; then
            [ "$root" != "/" ] && return 0
            return 1
        fi
    done < /proc/self/mountinfo
    return 1
}

ensure_volume_ownership() {
    if [ "$(id -u)" -ne 0 ]; then
        return 0
    fi

    mkdir -p /opt/hurd-image /var/log/qemu
    # IMPORTANT: Avoid `chown` on bind mounts because it mutates host file
    # ownership. For engine-managed volumes, it's safe and often required.
    if ! mount_is_bind /opt/hurd-image; then
        chown hurd:hurd /opt/hurd-image 2>/dev/null || true
    fi
    if ! mount_is_bind /var/log/qemu; then
        chown hurd:hurd /var/log/qemu 2>/dev/null || true
    fi

    if [ -f "$QCOW2_IMAGE" ]; then
        # Only chown images on non-bind mounts (avoid changing host bind mounts).
        local image_dir
        image_dir="$(dirname "$QCOW2_IMAGE")"
        if ! mount_is_bind "$image_dir"; then
            chown hurd:hurd "$QCOW2_IMAGE" 2>/dev/null || true
        fi
    fi
}

drop_privileges_and_exec() {
    if [ "$(id -u)" -eq 0 ]; then
        if command -v gosu >/dev/null 2>&1; then
            # Only drop privileges when the disk image path is writable by 'hurd'.
            # IMPORTANT: For bind mounts, "root can write" does not imply the non-root
            # user can write, and `chown` would mutate host ownership. Prefer running
            # QEMU as root over breaking host permissions.
            local image_dir
            image_dir="$(dirname "$QCOW2_IMAGE")"
            if gosu hurd test -w "$image_dir" 2>/dev/null \
                && { [ ! -e "$QCOW2_IMAGE" ] || gosu hurd test -w "$QCOW2_IMAGE" 2>/dev/null; }; then
                exec gosu hurd "${QEMU_CMD[@]}" "$@"
            fi
            log_warn "Not dropping privileges: ${image_dir} is not writable by 'hurd' (running QEMU as root)"
        fi
        exec "${QEMU_CMD[@]}" "$@"
    fi
    exec "${QEMU_CMD[@]}" "$@"
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
QEMU_CDROM="${QEMU_CDROM:-}"
QEMU_BOOT_ORDER="${QEMU_BOOT_ORDER:-}"
SERIAL_PORT="${SERIAL_PORT:-5555}"
MONITOR_PORT="${MONITOR_PORT:-9999}"

# Advanced overrides:
# - Some upstream Hurd images can hit IDE DMA I/O errors on i440fx+PIIX.
#   `QEMU_MACHINE=isapc` uses ISA IDE and can be more reliable.
# - Network model must match the selected machine (e.g. `ne2k_isa` for `isapc`).
QEMU_MACHINE="${QEMU_MACHINE:-pc}"
QEMU_NET_MODEL="${QEMU_NET_MODEL:-}"
QEMU_VGA_DEVICE="${QEMU_VGA_DEVICE:-}"

QEMU_RAM=$(calculate_optimal_ram "$HOST_MEM_MB")
QEMU_SMP=$(calculate_optimal_smp "$HOST_CPUS")

# Machine-specific constraints
if [ "${QEMU_MACHINE}" = "isapc" ] && [ "${QEMU_SMP}" -gt 1 ]; then
    log_warn "Machine '${QEMU_MACHINE}' supports max 1 CPU; forcing QEMU_SMP=1"
    QEMU_SMP=1
fi

log_info "Optimized settings: ${QEMU_SMP} CPUs, ${QEMU_RAM} MB RAM"

# =============================================================================
# ARCHITECTURE VERIFICATION
# =============================================================================
verify_requirements() {
    # GNU/Hurd guest is x86_64-only, but the container may run on multiple host CPU archs.
    # On non-x86_64 hosts, QEMU will run in TCG (software emulation) mode.

    # Verify QEMU x86_64 binary exists (with underscore!)
    if [ ! -x /usr/bin/qemu-system-x86_64 ]; then
        log_error "qemu-system-x86_64 binary not found or not executable"
        log_error "Path should be: /usr/bin/qemu-system-x86_64"
        exit 1
    fi

    local host_arch
    host_arch="$(uname -m)"

    if [ "$host_arch" != "x86_64" ]; then
        log_warn "Host architecture is '$host_arch' (not x86_64)"
        log_warn "KVM acceleration is not available for an x86_64 guest on this host; using TCG emulation"
    fi

    log_info "QEMU target verified: x86_64 guest via /usr/bin/qemu-system-x86_64"
}

# =============================================================================
# KVM AVAILABILITY DETECTION
# =============================================================================
detect_acceleration() {
    # Try KVM first, fall back to TCG
    # This matches the recommended pattern: -accel kvm -accel tcg,thread=multi

    local host_arch
    host_arch="$(uname -m)"

    # KVM is only usable for an x86_64 guest on an x86_64 host.
    if [ "${DISABLE_KVM:-0}" = "1" ]; then
        echo "tcg"
        log_warn "KVM disabled (DISABLE_KVM=1); using TCG software emulation"
        log_info "CPU model: max (all emulated features enabled)"
        return 0
    fi

    if [ "$host_arch" = "x86_64" ] && [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        # KVM is available
        echo "kvm"
        log_info "KVM hardware acceleration detected and will be used"
        log_info "CPU model: host (full CPU passthrough)"
    else
        # Fall back to TCG
        echo "tcg"
        log_warn "KVM not available for this host/guest combination; using TCG software emulation"
        if [ "$host_arch" = "x86_64" ]; then
            log_warn "To enable KVM, run container with: --device=/dev/kvm"
        fi
        log_info "CPU model: max (all emulated features enabled)"
    fi
}

# The accelerator that ran is reconstructed from log prose and a QEMU argv
# otherwise, and reconstruction cannot distinguish a candidate that was never
# available from one that was demoted. The selecting code writes what it
# decided, with the inputs that decided it, before it execs.
ACCELERATOR_DECISION_PATH="${ACCELERATOR_DECISION_PATH:-/run/hurd/accelerator-decision.json}"

write_accelerator_decision() {
    local candidate="$1" selected="$2" reason="$3" disk_bus="$4"
    local host_arch kvm_exists kvm_readable kvm_writable
    host_arch="$(uname -m)"
    kvm_exists=false; kvm_readable=false; kvm_writable=false
    [ -e /dev/kvm ] && kvm_exists=true
    [ -r /dev/kvm ] && kvm_readable=true
    [ -w /dev/kvm ] && kvm_writable=true

    mkdir -p "$(dirname "$ACCELERATOR_DECISION_PATH")" 2>/dev/null || return 0
    cat > "$ACCELERATOR_DECISION_PATH" <<EOF || return 0
{
  "schema_version": 1,
  "host_arch": "${host_arch}",
  "disable_kvm": ${DISABLE_KVM:-0},
  "container_kvm_exists": ${kvm_exists},
  "container_kvm_readable": ${kvm_readable},
  "container_kvm_writable": ${kvm_writable},
  "candidate": "${candidate}",
  "machine": "${QEMU_MACHINE}",
  "disk_bus": "${disk_bus}",
  "auto_disable_kvm_for_ide": ${AUTO_DISABLE_KVM_FOR_IDE:-1},
  "force_kvm": ${FORCE_KVM:-0},
  "smp": ${QEMU_SMP},
  "selected": "${selected}",
  "reason_code": "${reason}"
}
EOF
    log_info "Accelerator decision: ${selected} (${reason}); record at ${ACCELERATOR_DECISION_PATH}"
}

# =============================================================================
# BUILD QEMU COMMAND LINE
# =============================================================================
build_qemu_command() {
	local accel_mode
	accel_mode=$(detect_acceleration)

	# Known issue (observed with Debian GNU/Hurd amd64 images): KVM + PIIX IDE can
	# trigger repeated "bus-master DMA error: missing interrupt" and ext2fs I/O
	# errors (guest corruption symptoms, even when the host qcow2 is fine).
	#
	# Prefer reliability over speed by auto-disabling KVM for IDE on pc/i440fx,
	# unless the user explicitly overrides it.
	local disk_bus_hint="${QEMU_DISK_BUS:-ide}"
	local accel_candidate="$accel_mode"
	local accel_reason="host_detection"
	[ "${DISABLE_KVM:-0}" = "1" ] && accel_reason="disable_kvm_requested"
	[ "$accel_mode" = "kvm" ] && accel_reason="kvm_available"
		if [ "$accel_mode" = "kvm" ] && [ "${AUTO_DISABLE_KVM_FOR_IDE:-1}" = "1" ] && [ "${FORCE_KVM:-0}" != "1" ]; then
			case "${QEMU_MACHINE}" in
				pc*)
					if [ "$disk_bus_hint" = "ide" ]; then
						accel_mode="tcg"
						accel_reason="ide_safety_demotion"
						log_warn "Auto-disabling KVM: detected KVM + IDE on '${QEMU_MACHINE}' (set FORCE_KVM=1 to override)"
					fi
					;;
			esac
		fi
	if [ "$accel_mode" = "kvm" ] && [ "${FORCE_KVM:-0}" = "1" ]; then
		accel_reason="forced_kvm"
	fi
	write_accelerator_decision "$accel_candidate" "$accel_mode" "$accel_reason" \
		"$disk_bus_hint"

	# Start with base command - ALWAYS x86_64 binary
	local -a cmd=(/usr/bin/qemu-system-x86_64)

    # Machine type: pc (i440fx) by default for Hurd compatibility.
    # Some images are more reliable under `isapc` (ISA IDE, no PCI bus mastering).
    cmd+=(-machine "${QEMU_MACHINE}")

	# Acceleration (KVM on x86_64 hosts; TCG everywhere else)
	if [ "$accel_mode" = "kvm" ]; then
		cmd+=(-accel kvm)
	else
        cmd+=(-accel "tcg,thread=multi")
    fi

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
    if [ ! -f "$QCOW2_IMAGE" ] && [ "${AUTO_DOWNLOAD_IMAGE:-0}" = "1" ]; then
        log_warn "Disk image missing; AUTO_DOWNLOAD_IMAGE=1 set, attempting download into /opt/hurd-image"
        if [ -x /opt/scripts/download-image.sh ]; then
            IMAGE_DIR=/opt/hurd-image /opt/scripts/download-image.sh || true
        else
            log_error "Missing /opt/scripts/download-image.sh inside container"
        fi
    fi

    if [ -f "$QCOW2_IMAGE" ]; then
        # Disk I/O defaults:
        # - Use aio=threads for maximum compatibility (works with cache=writeback).
        # - aio=native requires cache.direct=on (typically achieved via cache=none),
        #   so only enable it explicitly.
        local aio_backend="threads"
        local cache_mode="writeback"

        if [ "$accel_mode" = "kvm" ] && [ "${ENABLE_NATIVE_AIO:-0}" = "1" ]; then
            aio_backend="native"
            cache_mode="none"
            log_info "Disk I/O: native AIO enabled (KVM) with cache=none"
        else
            log_info "Disk I/O: threads (default)"
        fi

        # Adjust cache mode for testing (unsafe cache)
        if [ "${UNSAFE_CACHE:-0}" = "1" ]; then
            cache_mode="unsafe"
            log_warn "Using UNSAFE cache mode - faster but risk of data loss"
            aio_backend="threads"
        fi

        # Some upstream Hurd images can hit IDE DMA-related I/O errors on i440fx+PIIX.
        # Workaround (when supported by the host QEMU build): raise bounce buffer sizes
        # for DMA mapping limitations on some controllers.
        local piix_bounce="${QEMU_PIIX_IDE_BOUNCE_SIZE:-}"
        if [ -n "$piix_bounce" ] && [ "${QEMU_MACHINE}" != "isapc" ]; then
            if /usr/bin/qemu-system-x86_64 -device piix3-ide,help 2>/dev/null | grep -q "x-max-bounce-buffer-size"; then
                cmd+=(-global "piix3-ide.x-max-bounce-buffer-size=${piix_bounce}")
                log_info "PIIX3 IDE: bounce buffer size set to ${piix_bounce}"
            else
                log_warn "PIIX3 IDE bounce buffer workaround not supported by this QEMU build; ignoring QEMU_PIIX_IDE_BOUNCE_SIZE"
            fi
        fi

        local ahci_bounce="${QEMU_AHCI_BOUNCE_SIZE:-}"
        if [ -n "$ahci_bounce" ]; then
            if /usr/bin/qemu-system-x86_64 -device ich9-ahci,help 2>/dev/null | grep -q "x-max-bounce-buffer-size"; then
                cmd+=(-global "ich9-ahci.x-max-bounce-buffer-size=${ahci_bounce}")
                log_info "ICH9 AHCI: bounce buffer size set to ${ahci_bounce}"
            else
                log_warn "ICH9 AHCI bounce buffer workaround not supported by this QEMU build; ignoring QEMU_AHCI_BOUNCE_SIZE"
            fi
        fi

        # Prefer explicit -drive + -device wiring so we can tune device properties
        # and allow switching away from IDE when it triggers guest I/O errors.
        local disk_bus="${QEMU_DISK_BUS:-ide}"
        cmd+=(
            -drive "id=drive0,file=${QCOW2_IMAGE},if=none,cache=${cache_mode},aio=${aio_backend},format=qcow2"
        )

        case "$disk_bus" in
            ide)
                local ide_controller="${QEMU_IDE_CONTROLLER:-piix}"
                if [ "${QEMU_MACHINE}" = "isapc" ]; then
                    ide_controller="isa"
                fi

                local ide_write_cache="${QEMU_IDE_WRITE_CACHE:-auto}"
                local ide_rerror="${QEMU_IDE_RERROR:-auto}"
                local ide_werror="${QEMU_IDE_WERROR:-auto}"

                case "$ide_controller" in
                    piix)
                        cmd+=(-device "ide-hd,drive=drive0,write-cache=${ide_write_cache},rerror=${ide_rerror},werror=${ide_werror}")
                        log_info "Disk: IDE (piix, ide-hd) with QCOW2 backend, cache=${cache_mode}, write-cache=${ide_write_cache}"
                        ;;
                    isa)
                        # Workaround: Some upstream Hurd images can hit IDE DMA-related I/O errors on i440fx+PIIX.
                        # Use an ISA IDE controller which is PIO-only (no bus-master DMA).
                        cmd+=(
                            -device "isa-ide,id=isaide0"
                            -device "ide-hd,drive=drive0,bus=isaide0.0,unit=0,write-cache=${ide_write_cache},rerror=${ide_rerror},werror=${ide_werror}"
                        )
                        log_info "Disk: IDE (isa-ide, PIO) with QCOW2 backend, cache=${cache_mode}, write-cache=${ide_write_cache}"
                        ;;
                    *)
                        log_error "Unsupported QEMU_IDE_CONTROLLER='${ide_controller}' (supported: piix, isa)"
                        exit 1
                        ;;
                esac
                ;;
            scsi)
                # Alternative bus: SCSI via LSI 53C895A (often more reliable than IDE DMA paths).
                # Guest device names usually become sd0/sd0s1.
                cmd+=(
                    -device "lsi53c895a,id=scsi0"
                    -device "scsi-hd,drive=drive0,bus=scsi0.0"
                )
                log_info "Disk: SCSI (lsi53c895a + scsi-hd) with QCOW2 backend, cache=${cache_mode}"
                ;;
            ahci)
                # Alternative bus: SATA/AHCI via ICH9 AHCI (PCI). This avoids the PIIX IDE DMA path
                # and can be more reliable on some host/QEMU combinations. Guest device naming varies.
                cmd+=(
                    -device "ich9-ahci,id=ahci0"
                    -device "ide-hd,drive=drive0,bus=ahci0.0,unit=0"
                )
                log_info "Disk: AHCI/SATA (ich9-ahci + ide-hd) with QCOW2 backend, cache=${cache_mode}"
                ;;
            *)
                log_error "Unsupported QEMU_DISK_BUS='${disk_bus}' (supported: ide, scsi, ahci)"
                exit 1
                ;;
        esac
    else
        log_error "Disk image not found: $QCOW2_IMAGE"
        log_error "Please download or create a Debian GNU/Hurd x86_64 image"
        log_error "Hint: run ./scripts/setup-hurd-amd64.sh on the host, or set AUTO_DOWNLOAD_IMAGE=1"
        exit 1
    fi

    # Optional installer media for fresh image provisioning workflows.
    if [ -n "$QEMU_CDROM" ]; then
        if [ ! -f "$QEMU_CDROM" ]; then
            log_error "Installer ISO not found: ${QEMU_CDROM}"
            log_error "Ensure the host path is mounted into /opt/hurd-installer and set QEMU_CDROM accordingly"
            exit 1
        fi
        cmd+=(-cdrom "$QEMU_CDROM")
        log_info "Installer media attached: ${QEMU_CDROM}"
        if [ -z "$QEMU_BOOT_ORDER" ]; then
            QEMU_BOOT_ORDER="d"
            log_info "Boot order auto-set to '${QEMU_BOOT_ORDER}' for installer media"
        fi
    fi

    if [ -n "$QEMU_BOOT_ORDER" ]; then
        cmd+=(-boot "order=${QEMU_BOOT_ORDER}")
        log_info "Boot order: ${QEMU_BOOT_ORDER}"
    fi

    # Network: default is e1000 (NOT virtio - Hurd doesn't support it well)
    # Port forwarding defaults are safe for most setups; customize with QEMU_HOSTFWDS.
    #
    # QEMU_HOSTFWDS format (comma-separated):
    #   tcp::2222-:22,tcp::8080-:80,tcp::8443-:443
    #
    # Note: host port selection is typically handled by Compose port mappings; changing the
    # host->container port does NOT require changing QEMU_HOSTFWDS.
    local hostfwds="${QEMU_HOSTFWDS:-tcp::2222-:22,tcp::8080-:80}"

    local net_model="${QEMU_NET_MODEL}"
    if [ -z "$net_model" ] && [ "${QEMU_MACHINE}" = "isapc" ]; then
        net_model="ne2k_isa"
    fi
    if [ -z "$net_model" ]; then
        net_model="e1000"
    fi

    local net_opts="user,model=${net_model}"

    if [ -n "$hostfwds" ]; then
        local IFS=,
        local fwd
        for fwd in $hostfwds; do
            [ -z "$fwd" ] && continue
            fwd="${fwd#hostfwd=}"
            net_opts="${net_opts},hostfwd=${fwd}"
        done
    fi

    # Slirp user networking:
    # - Keep defaults unless explicitly overridden; forcing a custom subnet here can
    #   break in-container connectivity (seen as repeated "Slirp: Failed to send packet").
    # - If you want a custom subnet, set QEMU_SLIRP_NET (e.g. 192.168.76.0/24) and
    #   optionally QEMU_SLIRP_DHCPSTART (e.g. 192.168.76.9).
    local slirp_net="${QEMU_SLIRP_NET:-}"
    local slirp_dhcp="${QEMU_SLIRP_DHCPSTART:-}"
    if [ -n "$slirp_net" ]; then
        net_opts="${net_opts},net=${slirp_net}"
    fi
    if [ -n "$slirp_dhcp" ]; then
        net_opts="${net_opts},dhcpstart=${slirp_dhcp}"
    fi

    cmd+=(-nic "$net_opts")
    log_info "Network: ${net_model} NIC with user-mode NAT"

    # Serial console and monitor (disable explicitly for hardened deployments)
    if [ "${DISABLE_SERIAL:-0}" != "1" ]; then
        cmd+=(-serial "telnet:0.0.0.0:${SERIAL_PORT},server,nowait")
    else
        log_warn "Serial console disabled (DISABLE_SERIAL=1)"
    fi

    if [ "${DISABLE_MONITOR:-0}" != "1" ]; then
        cmd+=(-monitor "telnet:0.0.0.0:${MONITOR_PORT},server,nowait")
    else
        log_warn "QEMU monitor disabled (DISABLE_MONITOR=1)"
    fi

    # Optional 9p host share (best-effort; guest support may vary)
    if [ "${ENABLE_9P:-0}" = "1" ] && [ -d /share ]; then
        cmd+=(-virtfs "local,path=/share,mount_tag=hostshare,security_model=none")
        log_info "9p share enabled: mount_tag=hostshare (path=/share)"
    fi

    # VGA device selection (needed for ISA-only machines like isapc)
    local vga_dev="${QEMU_VGA_DEVICE}"
    if [ -z "$vga_dev" ] && [ "${QEMU_MACHINE}" = "isapc" ]; then
        vga_dev="isa-vga"
    fi
    if [ -n "$vga_dev" ]; then
        cmd+=(-device "$vga_dev")
        log_info "Display device: ${vga_dev}"
    fi

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

    # Keep guest reboots in-container by default; opt into one-shot mode only.
    if [ "${QEMU_NO_REBOOT:-0}" = "1" ]; then
        cmd+=(-no-reboot)
        log_info "QEMU one-shot mode enabled (-no-reboot)"
    else
        log_info "QEMU reboot loop mode enabled (default)"
    fi

    # Enable guest error logging (to /tmp which is writable)
    cmd+=(-d guest_errors -D /tmp/qemu-guest-errors.log)

    QEMU_CMD=("${cmd[@]}")
    return 0
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

    # Verify required tools and guest-target invariants
    verify_requirements

    # If running as root, ensure mounts and KVM device are usable by the 'hurd' user.
    ensure_kvm_group_membership
    ensure_volume_ownership

    # Build command
    build_qemu_command

    echo "Configuration:"
    echo "  - Binary: /usr/bin/qemu-system-x86_64"
    echo "  - Image: ${QCOW2_IMAGE}"
    if [ -n "${QEMU_CDROM}" ]; then
        echo "  - CDROM: ${QEMU_CDROM}"
    fi
    if [ -n "${QEMU_BOOT_ORDER}" ]; then
        echo "  - Boot order: ${QEMU_BOOT_ORDER}"
    fi
    echo "  - Memory: ${QEMU_RAM} MB"
    echo "  - CPUs: ${QEMU_SMP}"
    echo "  - Machine: ${QEMU_MACHINE}"
    echo "  - Disk: ${QEMU_DISK_BUS:-ide} (guest-visible root device may differ)"
    echo "  - Network: ${QEMU_NET_MODEL:-auto} (Hurd compatible)"
    echo ""
    echo "Port Forwarding:"
    if [ -n "${HOST_SSH_PORT:-}" ]; then
        echo "  - SSH: host localhost:${HOST_SSH_PORT} -> container:2222 -> guest:22"
    else
        echo "  - SSH: container:2222 -> guest:22"
    fi
    if [ -n "${HOST_HTTP_PORT:-}" ]; then
        echo "  - HTTP: host localhost:${HOST_HTTP_PORT} -> container:8080 -> guest:80"
    else
        echo "  - HTTP: container:8080 -> guest:80"
    fi
    echo ""
    echo "Management:"
    if [ -n "${HOST_SERIAL_PORT:-}" ]; then
        echo "  - Serial: host telnet localhost:${HOST_SERIAL_PORT} (container:${SERIAL_PORT})"
    else
        echo "  - Serial: telnet localhost:${SERIAL_PORT}"
    fi
    if [ -n "${HOST_MONITOR_PORT:-}" ]; then
        echo "  - Monitor: host telnet localhost:${HOST_MONITOR_PORT} (container:${MONITOR_PORT})"
    else
        echo "  - Monitor: telnet localhost:${MONITOR_PORT}"
    fi
    echo ""
    echo "=============================================================================="
    echo ""
    echo "Starting QEMU..."
    echo ""

    # Ensure ownership of any downloaded/created image before dropping privileges.
    ensure_volume_ownership

    if [ "${PRINT_QEMU_CMD:-0}" = "1" ]; then
        echo "QEMU command:"
        printf '  %q' "${QEMU_CMD[@]}"
        echo ""
    fi

    # Execute QEMU (prefer non-root; falls back to current user if not root)
    drop_privileges_and_exec "$@"
}

# Signal handling for graceful shutdown
trap 'log_info "Shutting down..."; exit 0' SIGTERM SIGINT

# Run main
main "$@"
