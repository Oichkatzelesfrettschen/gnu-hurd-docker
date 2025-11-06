#!/bin/bash
set -e

# ============================================================================
# GNU/Hurd Docker - Enhanced QEMU Launcher
# Portable baseline with Linux-specific optimizations
# ============================================================================

# Configuration variables (override via environment)
QCOW2_IMAGE="${QEMU_DRIVE:-/opt/hurd-image/debian-hurd-i386-20250807.qcow2}"
QEMU_RAM="${QEMU_RAM:-2048}"
QEMU_SMP="${QEMU_SMP:-1}"
QEMU_LOG="/tmp/qemu.log"
QEMU_MONITOR="/qmp/monitor.sock"
QEMU_QMP="/qmp/qmp.sock"
SERIAL_PORT="${SERIAL_PORT:-5555}"
VNC_DISPLAY="${VNC_DISPLAY:-:1}"
SHARE_TAG="${SHARE_TAG:-scripts}"
DISPLAY_MODE="${DISPLAY_MODE:-nographic}"  # nographic|vnc|sdl-gl|gtk-gl
QEMU_VIDEO="${QEMU_VIDEO:-std}"  # std|virtio-vga-gl|cirrus
QEMU_STORAGE="${QEMU_STORAGE:-virtio}"  # ide|virtio
QEMU_NET="${QEMU_NET:-virtio}"  # e1000|virtio

# ============================================================================
# Validation
# ============================================================================

if [ ! -f "$QCOW2_IMAGE" ]; then
    echo "ERROR: QCOW2 image not found at $QCOW2_IMAGE"
    echo "Download with: ./download-image.sh"
    exit 1
fi

# ============================================================================
# Feature Detection
# ============================================================================

# Detect KVM availability (Linux hosts only)
KVM_OPTS=()
CPU_MODEL="pentium3"  # Default for maximum compatibility
if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    KVM_OPTS+=(-enable-kvm)
    CPU_MODEL="host"  # Use host CPU for best performance with KVM
    ACCEL="KVM"
    echo "[INFO] KVM acceleration: ENABLED"
else
    ACCEL="TCG"
    echo "[INFO] KVM acceleration: DISABLED (not available or no permissions)"
    echo "[INFO] Using TCG software emulation (slower but portable)"
fi

# ============================================================================
# Display Configuration
# ============================================================================

DISPLAY_OPTS=()
VIDEO_OPTS=()

case "$DISPLAY_MODE" in
    nographic)
        DISPLAY_OPTS+=(-nographic)
        echo "[INFO] Display: No graphics (serial console only)"
        ;;
    vnc)
        DISPLAY_OPTS+=(-display "vnc=$VNC_DISPLAY")
        VIDEO_OPTS+=(-vga "$QEMU_VIDEO")
        echo "[INFO] Display: VNC on ${VNC_DISPLAY} (port $((5900 + ${VNC_DISPLAY#:})))"
        echo "[INFO] Video: $QEMU_VIDEO"
        ;;
    sdl-gl)
        DISPLAY_OPTS+=(-display "sdl,gl=on")
        if [ "$QEMU_VIDEO" = "virtio-vga-gl" ]; then
            VIDEO_OPTS+=(-device virtio-vga-gl)
        else
            VIDEO_OPTS+=(-vga "$QEMU_VIDEO")
        fi
        echo "[INFO] Display: SDL with OpenGL acceleration"
        echo "[INFO] Video: $QEMU_VIDEO"
        ;;
    gtk-gl)
        DISPLAY_OPTS+=(-display "gtk,gl=on")
        if [ "$QEMU_VIDEO" = "virtio-vga-gl" ]; then
            VIDEO_OPTS+=(-device virtio-vga-gl)
        else
            VIDEO_OPTS+=(-vga "$QEMU_VIDEO")
        fi
        echo "[INFO] Display: GTK with OpenGL acceleration"
        echo "[INFO] Video: $QEMU_VIDEO"
        ;;
    sdl)
        DISPLAY_OPTS+=(-display sdl)
        VIDEO_OPTS+=(-vga "$QEMU_VIDEO")
        echo "[INFO] Display: SDL (no GL)"
        echo "[INFO] Video: $QEMU_VIDEO"
        ;;
    gtk)
        DISPLAY_OPTS+=(-display gtk)
        VIDEO_OPTS+=(-vga "$QEMU_VIDEO")
        echo "[INFO] Display: GTK (no GL)"
        echo "[INFO] Video: $QEMU_VIDEO"
        ;;
    *)
        DISPLAY_OPTS+=(-nographic)
        echo "[WARN] Unknown display mode '$DISPLAY_MODE', using nographic"
        ;;
esac

# USB support for GUI modes
USB_OPTS=()
if [[ "$DISPLAY_MODE" != "nographic" ]]; then
    USB_OPTS+=(-usb -device usb-tablet)
    echo "[INFO] USB: Enabled with tablet device for better mouse integration"
fi

# ============================================================================
# Storage Configuration
# ============================================================================

STORAGE_OPTS=()
if [ "$QEMU_STORAGE" = "virtio" ]; then
    STORAGE_OPTS+=(-drive "file=$QCOW2_IMAGE,format=qcow2,cache=writeback,aio=threads,if=virtio,discard=unmap")
    echo "[INFO] Storage: VirtIO with writeback cache (best performance)"
else
    STORAGE_OPTS+=(-drive "file=$QCOW2_IMAGE,format=qcow2,cache=writeback,aio=threads,if=ide")
    echo "[INFO] Storage: IDE with writeback cache (compatibility mode)"
fi

# ============================================================================
# Network Configuration
# ============================================================================

NETWORK_OPTS=()
if [ "$QEMU_NET" = "virtio" ]; then
    NETWORK_OPTS+=(-netdev "user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:80,hostfwd=tcp::9999-:9999")
    NETWORK_OPTS+=(-device "virtio-net-pci,netdev=net0")
    echo "[INFO] Network: VirtIO-Net (best performance)"
else
    NETWORK_OPTS+=(-netdev "user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:80,hostfwd=tcp::9999-:9999")
    NETWORK_OPTS+=(-device "e1000,netdev=net0")
    echo "[INFO] Network: E1000 (compatibility mode)"
fi

# ============================================================================
# File Sharing Configuration (9p - portable)
# ============================================================================

# Export /share directory to guest via 9p virtio
# Guest mounts with: mount -t 9p -o trans=virtio,version=9p2000.L scripts /mnt
SHARE_OPTS=()
if [ -d /share ]; then
    # Note: commas in virtfs parameters are not array separators
    # shellcheck disable=SC2054
    SHARE_OPTS+=(-virtfs "local,path=/share,mount_tag=$SHARE_TAG,security_model=none,id=fsdev0")
    echo "[INFO] File sharing: 9p export /share as '$SHARE_TAG'"
    echo "       Mount in guest: mount -t 9p -o trans=virtio $SHARE_TAG /mnt"
else
    echo "[WARN] File sharing: /share not mounted, skipping 9p export"
fi

# ============================================================================
# Info Banner
# ============================================================================

echo ""
echo "======================================================================"
echo "  GNU/Hurd Docker - QEMU i386 Microkernel Environment (2025 Optimized)"
echo "======================================================================"
echo ""
echo "Configuration:"
echo "  - Image: $QCOW2_IMAGE"
echo "  - Memory: ${QEMU_RAM} MB"
echo "  - CPU: $CPU_MODEL"
echo "  - SMP: ${QEMU_SMP} core(s)"
echo "  - Acceleration: $ACCEL"
echo "  - Machine: pc"
echo "  - Storage: $QEMU_STORAGE (writeback cache, threaded AIO)"
echo "  - Video: $QEMU_VIDEO"
echo "  - Display: $DISPLAY_MODE"
echo ""
echo "Networking:"
echo "  - Mode: User-mode NAT ($QEMU_NET)"
echo "  - SSH: localhost:2222 → guest:22"
echo "  - HTTP: localhost:8080 → guest:80"
echo "  - Custom: localhost:9999 → guest:9999"
echo ""
echo "Control Channels:"
echo "  - Serial console: telnet localhost:${SERIAL_PORT}"
echo "  - QEMU Monitor: socat - UNIX-CONNECT:/qmp/monitor.sock"
echo "  - QMP automation: socat - UNIX-CONNECT:/qmp/qmp.sock"
echo ""
echo "Logs:"
echo "  - QEMU errors: $QEMU_LOG"
echo "  - Container logs: docker-compose logs -f"
echo ""
echo "======================================================================"
echo ""

# ============================================================================
# Launch QEMU
# ============================================================================

exec qemu-system-i386 \
    "${KVM_OPTS[@]}" \
    -m "$QEMU_RAM" \
    -cpu "$CPU_MODEL" \
    -machine pc \
    -smp "$QEMU_SMP" \
    "${STORAGE_OPTS[@]}" \
    "${NETWORK_OPTS[@]}" \
    "${DISPLAY_OPTS[@]}" \
    "${VIDEO_OPTS[@]}" \
    "${USB_OPTS[@]}" \
    -monitor unix:"$QEMU_MONITOR",server,nowait \
    -qmp unix:"$QEMU_QMP",server,nowait \
    -serial telnet:0.0.0.0:"$SERIAL_PORT",server,nowait \
    "${SHARE_OPTS[@]}" \
    -rtc base=utc,clock=host \
    -no-reboot \
    -d guest_errors \
    -D "$QEMU_LOG" \
    "$@"
