#!/bin/bash
set -e

# Configuration variables
QCOW2_IMAGE="/opt/hurd-image/debian-hurd-i386-20250807.qcow2"
QEMU_LOG="/tmp/qemu.log"
QEMU_MONITOR="/tmp/qemu-monitor.sock"

# Validate QCOW2 image exists
if [ ! -f "$QCOW2_IMAGE" ]; then
    echo "ERROR: QCOW2 image not found at $QCOW2_IMAGE"
    exit 1
fi

echo "[INFO] GNU/Hurd Docker - Optimized QEMU Configuration"
echo "[INFO] Starting QEMU with:"
echo "  - Memory: 2048 MB"
echo "  - CPU: Pentium3 (i686, SSE support)"
echo "  - Machine: pc-i440fx (latest stable)"
echo "  - Storage: QCOW2 with writeback cache and threaded AIO"
echo "  - Network: User-mode NAT (SSH:2222, HTTP:8080)"
echo "  - Monitor: Unix socket at $QEMU_MONITOR"
echo ""

# Launch QEMU with optimized parameters
# Rationale for each parameter documented in docs/QEMU-TUNING.md
exec qemu-system-i386 \
    -m 2048 \
    -cpu pentium3 \
    -machine pc-i440fx-7.2,usb=off \
    -smp 1 \
    -drive file="$QCOW2_IMAGE",format=qcow2,cache=writeback,aio=threads,if=ide \
    -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:80 \
    -device e1000,netdev=net0 \
    -nographic \
    -monitor unix:"$QEMU_MONITOR",server,nowait \
    -serial pty \
    -rtc base=utc,clock=host \
    -no-reboot \
    -d guest_errors \
    -D "$QEMU_LOG" \
    "$@"
