#!/bin/bash
set -e

if [ ! -f /opt/hurd-image/debian-hurd-i386-20250807.qcow2 ]; then
    echo "ERROR: QCOW2 not found at /opt/hurd-image/"
    exit 1
fi

echo "[INFO] Starting QEMU GNU/Hurd..."

exec qemu-system-i386 \
    -m 1.5G \
    -cpu pentium \
    -drive file=/opt/hurd-image/debian-hurd-i386-20250807.qcow2,format=qcow2,cache=writeback \
    -net user,hostfwd=tcp::2222-:22 \
    -net nic,model=e1000 \
    -nographic \
    -monitor none \
    -serial pty \
    -D /tmp/qemu.log
