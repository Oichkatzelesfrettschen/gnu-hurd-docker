#!/bin/bash
set -euo pipefail

# GNU/Hurd Docker - Full Debugging Launch Script
# Launches Debian GNU/Hurd with comprehensive debugging and CLI access
# WHY: Enable full CLI orchestration of QEMU and Hurd
# WHAT: QEMU monitor, serial console, VNC, SSH, and debugging interfaces
# HOW: Multiple access methods via telnet, socat, and network sockets

echo "=========================================="
echo "GNU/Hurd Full Debugging Launch"
echo "=========================================="
echo ""

# Configuration
IMAGE_PATH="${IMAGE_PATH:-images/debian-hurd-amd64.qcow2}"
MEMORY="${MEMORY:-2048}"
CPUS="${CPUS:-2}"
VNC_DISPLAY="${VNC_DISPLAY:-:0}"
MONITOR_PORT="${MONITOR_PORT:-9999}"
SERIAL_PORT="${SERIAL_PORT:-5555}"
SSH_PORT="${SSH_PORT:-2222}"
VNC_PORT="${VNC_PORT:-5900}"

# Check prerequisites
if [ ! -f "$IMAGE_PATH" ]; then
    echo "[ERROR] Image not found: $IMAGE_PATH"
    echo "Please run ./scripts/download-image.sh first"
    exit 1
fi

echo "Configuration:"
echo "  Image: $IMAGE_PATH"
echo "  Memory: ${MEMORY}M"
echo "  CPUs: $CPUS"
echo "  VNC Display: $VNC_DISPLAY"
echo ""

echo "Access Methods:"
echo "  QEMU Monitor: telnet localhost $MONITOR_PORT"
echo "  Serial Console: telnet localhost $SERIAL_PORT"
echo "  SSH: ssh -p $SSH_PORT root@localhost"
echo "  VNC: vncviewer localhost:$VNC_DISPLAY"
echo ""

# Create snapshot for testing
echo "[INFO] Creating VM snapshot for safe testing..."
qemu-img snapshot -c "pre-launch-$(date +%Y%m%d-%H%M%S)" "$IMAGE_PATH" || true

echo "[INFO] Launching QEMU with full debugging enabled..."
echo ""

# Launch QEMU with comprehensive debugging
qemu-system-x86_64 \
  -name "debian-hurd-debug" \
  -machine q35,accel=tcg \
  -cpu qemu64 \
  -smp cpus=$CPUS,cores=$CPUS,threads=1,sockets=1 \
  -m ${MEMORY}M \
  -rtc base=utc,clock=host \
  -drive file="$IMAGE_PATH",format=qcow2,media=disk,if=virtio,cache=writeback \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \
  -display none \
  -vnc ${VNC_DISPLAY} \
  -monitor telnet:0.0.0.0:${MONITOR_PORT},server,nowait \
  -serial telnet:0.0.0.0:${SERIAL_PORT},server,nowait \
  -device virtio-rng-pci \
  -device virtio-balloon-pci \
  -boot order=c \
  -no-reboot \
  -D /tmp/qemu-hurd-debug.log \
  -d guest_errors,unimp \
  &

QEMU_PID=$!
echo "[OK] QEMU launched with PID: $QEMU_PID"
echo ""

# Save PID for later management
echo $QEMU_PID > /tmp/qemu-hurd.pid

# Wait for ports to be available
echo "[INFO] Waiting for interfaces to become available..."
sleep 3

echo ""
echo "=========================================="
echo "Hurd VM is now running!"
echo "=========================================="
echo ""
echo "📊 Process Management:"
echo "  PID: $QEMU_PID"
echo "  Status: ps -p $QEMU_PID"
echo "  Stop: kill $QEMU_PID"
echo ""
echo "🔧 Access Methods:"
echo "  1. QEMU Monitor (QMP):"
echo "     telnet localhost $MONITOR_PORT"
echo "     Commands: info status, info snapshots, savevm, loadvm, quit"
echo ""
echo "  2. Serial Console:"
echo "     telnet localhost $SERIAL_PORT"
echo "     Direct kernel/boot messages"
echo ""
echo "  3. SSH Access (after boot):"
echo "     ssh -p $SSH_PORT root@localhost"
echo "     Default password: root"
echo ""
echo "  4. VNC Graphical Console:"
echo "     vncviewer localhost${VNC_DISPLAY}"
echo "     Port: $VNC_PORT"
echo ""
echo "🐛 Debugging:"
echo "  QEMU Log: tail -f /tmp/qemu-hurd-debug.log"
echo "  VM Info: echo 'info status' | nc localhost $MONITOR_PORT"
echo "  Snapshots: echo 'info snapshots' | nc localhost $MONITOR_PORT"
echo ""
echo "📝 Management Commands:"
echo "  Save state: echo 'savevm backup1' | nc localhost $MONITOR_PORT"
echo "  Load state: echo 'loadvm backup1' | nc localhost $MONITOR_PORT"
echo "  Shutdown: echo 'system_powerdown' | nc localhost $MONITOR_PORT"
echo "  Force quit: echo 'quit' | nc localhost $MONITOR_PORT"
echo ""
echo "⏳ Waiting for boot (this may take 30-60 seconds)..."
echo "   Watch progress: telnet localhost $SERIAL_PORT"
echo ""

# Monitor boot progress
sleep 5
if ps -p $QEMU_PID > /dev/null; then
    echo "[OK] VM is running successfully"
    echo "     Attach to serial console to see boot messages"
else
    echo "[ERROR] VM process died unexpectedly"
    echo "        Check log: cat /tmp/qemu-hurd-debug.log"
    exit 1
fi
