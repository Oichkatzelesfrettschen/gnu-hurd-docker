# GNU/Hurd Docker - LLM-Optimized Control Plane Implementation

**Date:** 2025-11-05
**Based on:** ChatGPT "max-CLI" QEMU brainstorm + CachyOS best practices
**Goal:** Create a reproducible, deterministic Hurd environment optimized for CLI access from Claude Code and other LLM tools

---

## Key Insights from ChatGPT Brainstorm

### What Applies to GNU/Hurd

✅ **Directly Applicable:**
- QMP (JSON) control socket for machine automation
- Serial console (telnet/unix) for firmware→kernel→shell I/O
- HMP (human monitor) for ad-hoc low-level commands
- 9p/virtiofs for fast host↔guest file sharing
- Deterministic SSH with key-based auth
- Systemd service management
- mosh for resilient interactive sessions

⚠️ **Needs Adaptation:**
- cloud-init (Debian Hurd doesn't have cloud-init packages yet)
  → Use manual provisioning + snapshot approach
- UEFI/OVMF firmware (Hurd is i386, uses SeaBIOS)
  → Focus on SeaBIOS boot menu control
- virtiofs (may not be stable on Hurd yet)
  → Stick with 9p for reliability

❌ **Not Applicable:**
- x86_64 / q35 machine type → Hurd needs i386
- Modern cloud images → Use official Debian Hurd QCOW2
- GDB stub for firmware → Less relevant for Hurd (focus on userspace)

---

## Architecture: Four-Channel Control Plane

```
┌─────────────────────────────────────────────────────────────┐
│                      Docker Container                        │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                    QEMU Process                        │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │           GNU/Hurd i386 Guest                  │  │  │
│  │  │                                                 │  │  │
│  │  │  ┌──────────────────────────────────────────┐  │  │  │
│  │  │  │  1. SSH (port 2222)                      │  │  │  │
│  │  │  │     - Key-based auth only                │  │  │  │
│  │  │  │     - tmux auto-attach                   │  │  │  │
│  │  │  │     - mosh for resilience                │  │  │  │
│  │  │  └──────────────────────────────────────────┘  │  │  │
│  │  │  ┌──────────────────────────────────────────┐  │  │  │
│  │  │  │  2. Serial Console (telnet :5555)        │  │  │  │
│  │  │  │     - GRUB menu                          │  │  │  │
│  │  │  │     - Kernel messages                    │  │  │  │
│  │  │  │     - Early boot debugging               │  │  │  │
│  │  │  └──────────────────────────────────────────┘  │  │  │
│  │  │  ┌──────────────────────────────────────────┐  │  │  │
│  │  │  │  3. 9p Filesystem (virtio)               │  │  │  │
│  │  │  │     - /mnt/host ← host /share           │  │  │  │
│  │  │  │     - Bidirectional file access          │  │  │  │
│  │  │  └──────────────────────────────────────────┘  │  │  │
│  │  └─────────────────────────────────────────────┘  │  │  │
│  │                                                     │  │  │
│  │  4. QMP Socket (unix:/qmp/qmp.sock)               │  │  │
│  │     - JSON automation                              │  │  │
│  │     - Machine control (power, reset, snapshot)    │  │  │
│  │     - sendkey injection                            │  │  │
│  │                                                     │  │  │
│  │  5. HMP Monitor (telnet :4444 or via QMP)         │  │  │
│  │     - Human-readable commands                      │  │  │
│  │     - Device inspection                            │  │  │
│  └─────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Enhanced entrypoint.sh with Full Control Plane

### Current vs. Proposed

**Current** (entrypoint.sh:141 lines):
- ✅ KVM detection
- ✅ Serial console (telnet)
- ✅ QMP socket
- ✅ Monitor socket
- ✅ 9p file sharing
- ⚠️ No HMP telnet
- ⚠️ No sendkey automation
- ⚠️ No SeaBIOS menu control

**Proposed Enhancement:**

```bash
#!/bin/bash
# Enhanced entrypoint.sh with full control plane

set -e

# Configuration
QCOW2_IMAGE="${QEMU_DRIVE:-/opt/hurd-image/debian-hurd-i386-20251105.qcow2}"
QEMU_RAM="${QEMU_RAM:-2048}"
QEMU_SMP="${QEMU_SMP:-1}"
QEMU_CPU="${QEMU_CPU:-pentium3}"
SERIAL_PORT="${SERIAL_PORT:-5555}"
HMP_PORT="${HMP_PORT:-4444}"
SHARE_TAG="${SHARE_TAG:-scripts}"
DISPLAY_MODE="${DISPLAY_MODE:-nographic}"

# KVM auto-detection
KVM_OPTS=()
if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    KVM_OPTS+=(-enable-kvm)
    ACCEL="KVM"
else
    ACCEL="TCG (software emulation)"
fi

# Display configuration
DISPLAY_OPTS=()
case "$DISPLAY_MODE" in
    vnc)
        DISPLAY_OPTS+=(-vnc :1)
        DISPLAY_MSG="VNC on :1 (port 5901)"
        ;;
    sdl)
        DISPLAY_OPTS+=(-display sdl)
        DISPLAY_MSG="SDL window"
        ;;
    gtk)
        DISPLAY_OPTS+=(-display gtk)
        DISPLAY_MSG="GTK window"
        ;;
    *)
        DISPLAY_OPTS+=(-nographic)
        DISPLAY_MSG="No graphics (serial console only)"
        ;;
esac

# 9p file sharing
SHARE_OPTS=()
if [ -d /share ]; then
    SHARE_OPTS+=(
        -virtfs local,path=/share,mount_tag="$SHARE_TAG",security_model=none,id=fsdev0
    )
    SHARE_MSG="9p export /share as '$SHARE_TAG'"
else
    SHARE_MSG="No file sharing (mkdir /share to enable)"
fi

# Print configuration banner
cat <<EOF

======================================================================
  GNU/Hurd Docker - LLM-Optimized Control Plane
======================================================================

Configuration:
  - Image: $QCOW2_IMAGE
  - Memory: $QEMU_RAM MB
  - CPU: $QEMU_CPU (i686)
  - SMP: $QEMU_SMP core(s)
  - Acceleration: $ACCEL

Control Channels (LLM-accessible):
  1. SSH:           localhost:2222 → guest:22
  2. Serial Console: telnet localhost:$SERIAL_PORT
  3. QMP Socket:    /qmp/qmp.sock (JSON automation)
  4. HMP Monitor:   telnet localhost:$HMP_PORT (human commands)
  5. File Sharing:  $SHARE_MSG
     Mount in guest: mount -t 9p -o trans=virtio $SHARE_TAG /mnt/host

Display: $DISPLAY_MSG

Automation Tools:
  - QMP: socat - UNIX-CONNECT:/qmp/qmp.sock
  - Serial: telnet localhost:$SERIAL_PORT
  - HMP: telnet localhost:$HMP_PORT
  - Press F12: Send boot menu key via QMP

Logs:
  - QEMU errors: /tmp/qemu.log
  - Container logs: docker-compose logs -f

======================================================================

EOF

# Wait for sockets directory
mkdir -p /qmp
sleep 0.5

# Launch QEMU with full control plane
exec qemu-system-i386 \
    "${KVM_OPTS[@]}" \
    -m "$QEMU_RAM" \
    -cpu "$QEMU_CPU" \
    -smp "$QEMU_SMP" \
    -machine pc-i440fx-7.2,usb=off \
    \
    -drive file="$QCOW2_IMAGE",format=qcow2,cache=writeback,aio=threads,if=ide \
    \
    -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:80,hostfwd=tcp::9999-:9999,hostfwd=udp::60000-:60000 \
    -device e1000,netdev=net0 \
    \
    -chardev socket,id=qmp0,path=/qmp/qmp.sock,server=on,wait=off \
    -qmp chardev:qmp0 \
    \
    -chardev socket,id=mon0,path=/qmp/monitor.sock,server=on,wait=off \
    -monitor chardev:mon0 \
    \
    -monitor telnet:0.0.0.0:"$HMP_PORT",server,nowait \
    \
    -serial telnet:0.0.0.0:"$SERIAL_PORT",server,nowait \
    \
    "${DISPLAY_OPTS[@]}" \
    "${SHARE_OPTS[@]}" \
    \
    -rtc base=utc,clock=host \
    -no-reboot \
    -d guest_errors \
    -D /tmp/qemu.log
```

---

## Phase 2: QMP Control Tool (qmp_ctl.py)

Create `scripts/qmp_ctl.py`:

```python
#!/usr/bin/env python3
"""
QMP Control Tool for GNU/Hurd Docker
Simplified JSON automation for LLM-friendly machine control
"""
import json, socket, sys, os

def qmp_command(sock_path, cmd_dict):
    """Execute a QMP command and return the response"""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(os.path.expanduser(sock_path))

    # QMP greeting
    greeting = json.loads(s.recv(4096).decode())
    print(f"# QMP version: {greeting['QMP']['version']['qemu']}", file=sys.stderr)

    # Capabilities negotiation
    s.sendall(b'{"execute":"qmp_capabilities"}\n')
    json.loads(s.recv(4096).decode())

    # Execute command
    s.sendall((json.dumps(cmd_dict) + "\n").encode())
    response = s.recv(65536).decode()
    s.close()

    return json.loads(response)

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: qmp_ctl.py <socket_path> '<json_command>'")
        print("\nExamples:")
        print('  qmp_ctl.py /qmp/qmp.sock \'{"execute":"query-status"}\'')
        print('  qmp_ctl.py /qmp/qmp.sock \'{"execute":"system_reset"}\'')
        print('  qmp_ctl.py /qmp/qmp.sock \'{"execute":"human-monitor-command","arguments":{"command-line":"sendkey f12"}}\'')
        sys.exit(1)

    sock_path = sys.argv[1]
    cmd_json = sys.argv[2]

    try:
        cmd = json.loads(cmd_json)
        result = qmp_command(sock_path, cmd)
        print(json.dumps(result, indent=2))
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
```

**Common operations:**

```bash
# Inside container
docker exec gnu-hurd-dev python3 /mnt/scripts/qmp_ctl.py /qmp/qmp.sock '{"execute":"query-status"}'

# Power control
docker exec gnu-hurd-dev python3 /mnt/scripts/qmp_ctl.py /qmp/qmp.sock '{"execute":"system_powerdown"}'
docker exec gnu-hurd-dev python3 /mnt/scripts/qmp_ctl.py /qmp/qmp.sock '{"execute":"system_reset"}'

# Send keys (boot menu, etc.)
docker exec gnu-hurd-dev python3 /mnt/scripts/qmp_ctl.py /qmp/qmp.sock \
  '{"execute":"human-monitor-command","arguments":{"command-line":"sendkey f12"}}'
```

---

## Phase 3: SSH Hardening with Key-Based Auth

### On Host: Generate SSH Key

```bash
# Generate ED25519 key (recommended for security)
ssh-keygen -t ed25519 -f ~/.ssh/hurd-dev -C "hurd-dev-llm"

# Add to SSH config for convenience
cat >> ~/.ssh/config << 'EOF'
Host hurd-local
    HostName 127.0.0.1
    Port 2222
    User root
    IdentityFile ~/.ssh/hurd-dev
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
```

### Inside Hurd Guest (manual first-time setup):

```bash
# Create SSH directory
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Add authorized key (copy from host)
echo "ssh-ed25519 AAAA...your_public_key...== hurd-dev-llm" > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# Harden SSH config
cat > /etc/ssh/sshd_config.d/10-llm-hardening.conf << 'EOF'
# LLM-friendly SSH hardening
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password
ClientAliveInterval 30
ClientAliveCountMax 6
MaxStartups 10:30:100
EOF

# Restart SSH
/etc/init.d/ssh restart
```

### Test from Host:

```bash
ssh hurd-local "uname -a"
# Should connect without password!
```

---

## Phase 4: mosh for Resilient Sessions

### Install mosh (inside Hurd):

```bash
apt-get update
apt-get install -y mosh
```

### Expose mosh ports (update docker-compose.yml):

```yaml
ports:
  - "2222:2222"     # SSH
  - "5555:5555"     # Serial
  - "4444:4444"     # HMP
  - "5901:5901"     # VNC
  - "60000-60010:60000-60010/udp"  # mosh (10 concurrent sessions)
```

### Connect from host:

```bash
mosh --ssh="ssh -p 2222" root@localhost
# Resilient to network changes, sleep/wake, etc.
```

---

## Phase 5: tmux Auto-Attach for LLM Sessions

### Inside Hurd:

```bash
# Install tmux
apt-get install -y tmux

# Auto-attach to main session on SSH login
cat > /root/.ssh/rc << 'EOF'
#!/bin/sh
# Auto-attach to tmux session "main" (create if doesn't exist)
exec tmux new-session -A -s main
EOF
chmod +x /root/.ssh/rc
```

**Result:** Every SSH/mosh connection automatically attaches to the same persistent tmux session. Perfect for LLM workflows that disconnect/reconnect!

---

## Phase 6: Systemd Service for Persistent VM

Create `~/.config/systemd/user/hurd-docker.service`:

```ini
[Unit]
Description=GNU/Hurd Docker Container (LLM-optimized)
After=docker.service
Requires=docker.service

[Service]
Type=simple
WorkingDirectory=%h/Playground/gnu-hurd-docker
ExecStart=/usr/bin/docker-compose up
ExecStop=/usr/bin/docker-compose down
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
```

**Enable and start:**

```bash
systemctl --user daemon-reload
systemctl --user enable --now hurd-docker.service
loginctl enable-linger "$USER"  # Keep running after logout
```

---

## Phase 7: Complete Provisioning Script

Create `scripts/provision-hurd.sh` (run once inside guest):

```bash
#!/bin/bash
set -e

echo "==================================================================="
echo "  GNU/Hurd LLM-Optimized Provisioning"
echo "==================================================================="

# 1. Update package lists
apt-get update

# 2. Install core utilities
apt-get install -y mosh tmux git curl wget vim

# 3. Install all dev tools
apt-get install -y \
    gcc g++ make cmake autoconf automake libtool \
    pkg-config flex bison texinfo \
    clang llvm lld binutils-dev libelf-dev \
    gnumach-dev hurd-dev mig hurd-doc \
    gdb strace ltrace sysstat \
    meson ninja-build \
    emacs-nox doxygen graphviz \
    netcat-openbsd

# 4. Setup SSH hardening (copy from /mnt/host if available)
if [ -f /mnt/host/hurd-dev.pub ]; then
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    cp /mnt/host/hurd-dev.pub /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys

    cat > /etc/ssh/sshd_config.d/10-llm-hardening.conf << 'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password
ClientAliveInterval 30
ClientAliveCountMax 6
EOF
    /etc/init.d/ssh restart
fi

# 5. Setup tmux auto-attach
cat > /root/.ssh/rc << 'EOF'
#!/bin/sh
exec tmux new-session -A -s main
EOF
chmod +x /root/.ssh/rc

# 6. Configure shell environment
cat >> /root/.bashrc << 'EOF'

# GNU/Hurd Development Environment
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"
export MACH_INCLUDE="/usr/include/mach"
export HURD_INCLUDE="/usr/include/hurd"
export PKG_CONFIG_PATH="/usr/lib/pkgconfig"

# Mach aliases
alias mig='mig'
alias mach-version='cat /proc/mach/version'

# Development aliases
alias ll='ls -lah'
alias la='ls -A'

# Prompt
export PS1='\[\033[01;32m\]\u@hurd\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
EOF

# 7. Verify Mach tools
echo ""
echo "==================================================================="
echo "  Verification"
echo "==================================================================="
echo "GCC: $(gcc --version | head -1)"
echo "MIG: $(which mig)"
echo "Mach headers: $(ls /usr/include/mach/ | wc -l) files"
echo "Hurd headers: $(ls /usr/include/hurd/ | wc -l) files"
echo ""
echo "Provisioning complete!"
echo "==================================================================="
```

---

## Implementation Checklist

### Infrastructure
- [ ] Update entrypoint.sh with full control plane (QMP, HMP, serial)
- [ ] Add HMP_PORT=4444 to docker-compose.yml
- [ ] Create qmp_ctl.py for automation
- [ ] Test QMP commands (query-status, system_reset)
- [ ] Test HMP via telnet (sendkey, info commands)

### SSH Hardening
- [ ] Generate ED25519 key on host
- [ ] Copy public key to shared directory
- [ ] Configure SSH hardening inside Hurd
- [ ] Test key-based authentication
- [ ] Disable password authentication

### Resilience
- [ ] Install mosh inside Hurd
- [ ] Expose mosh UDP ports (60000-60010)
- [ ] Test mosh connection from host
- [ ] Setup tmux auto-attach
- [ ] Verify persistent sessions

### Automation
- [ ] Create provision-hurd.sh script
- [ ] Run provisioning inside Hurd
- [ ] Create clean snapshot after provisioning
- [ ] Create systemd user service
- [ ] Test service persistence across reboots

### Verification
- [ ] SSH works with keys only
- [ ] mosh provides resilient connection
- [ ] tmux auto-attaches on connect
- [ ] All dev tools installed (gnumach-dev, hurd-dev, mig)
- [ ] QMP automation works from host
- [ ] Serial console accessible
- [ ] 9p file sharing bidirectional

---

## Next Actions

1. **Fix fsck error in running QEMU** (user needs to run `/sbin/fsck.ext2 -y /dev/hd0s2`)
2. **Complete manual provisioning** following LOCAL-TESTING-GUIDE.md
3. **Document exact working configuration** in LOCAL-TESTING-NOTES.txt
4. **Implement enhanced entrypoint.sh** with full control plane
5. **Create qmp_ctl.py** automation tool
6. **Test complete setup end-to-end**
7. **Create clean snapshot** of fully-provisioned system
8. **Update SIMPLE-START.md** with new workflow

---

**Status:** Design complete, awaiting fsck fix to proceed with implementation
**Goal:** Deterministic, LLM-friendly Hurd environment with four-channel control
**Date:** 2025-11-05
