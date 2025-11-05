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
DISPLAY_MODE="${DISPLAY_MODE:-nographic}"  # nographic|vnc

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
if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    KVM_OPTS+=(-enable-kvm)
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
case "$DISPLAY_MODE" in
    nographic)
        DISPLAY_OPTS+=(-nographic)
        echo "[INFO] Display: No graphics (serial console only)"
        ;;
    vnc)
        DISPLAY_OPTS+=(-vnc "$VNC_DISPLAY")
        echo "[INFO] Display: VNC on ${VNC_DISPLAY} (port $((5900 + ${VNC_DISPLAY#:})))"
        ;;
    *)
        DISPLAY_OPTS+=(-nographic)
        ;;
esac

# ============================================================================
# File Sharing Configuration (9p - portable)
# ============================================================================

# Export /share directory to guest via 9p virtio
# Guest mounts with: mount -t 9p -o trans=virtio,version=9p2000.L scripts /mnt
SHARE_OPTS=()
if [ -d /share ]; then
    SHARE_OPTS+=(
        -virtfs local,path=/share,mount_tag="$SHARE_TAG",security_model=none,id=fsdev0
    )
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
echo "  GNU/Hurd Docker - QEMU i386 Microkernel Environment"
echo "======================================================================"
echo ""
echo "Configuration:"
echo "  - Image: $QCOW2_IMAGE"
echo "  - Memory: ${QEMU_RAM} MB"
echo "  - CPU: Pentium3 (i686, SSE support)"
echo "  - SMP: ${QEMU_SMP} core(s)"
echo "  - Acceleration: $ACCEL"
echo "  - Machine: pc-i440fx-7.2"
echo "  - Storage: QCOW2 with writeback cache, threaded AIO"
echo ""
echo "Networking:"
echo "  - Mode: User-mode NAT"
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
    -cpu pentium3 \
    -machine pc-i440fx-7.2,usb=off \
    -smp "$QEMU_SMP" \
    -drive file="$QCOW2_IMAGE",format=qcow2,cache=writeback,aio=threads,if=ide \
    -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:80,hostfwd=tcp::9999-:9999 \
    -device e1000,netdev=net0 \
    "${DISPLAY_OPTS[@]}" \
    -monitor unix:"$QEMU_MONITOR",server,nowait \
    -qmp unix:"$QEMU_QMP",server,nowait \
    -serial telnet:0.0.0.0:"$SERIAL_PORT",server,nowait \
    "${SHARE_OPTS[@]}" \
    -rtc base=utc,clock=host \
    -no-reboot \
    -d guest_errors \
    -D "$QEMU_LOG" \
    "$@"
