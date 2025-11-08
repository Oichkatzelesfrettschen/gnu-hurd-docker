# GNU/Hurd Docker - Control Plane Architecture

**Last Updated**: 2025-11-07
**Consolidated From**:
- CONTROL-PLANE-IMPLEMENTATION.md (2025-11-05 design)
- entrypoint.sh (current implementation)

**Purpose**: LLM-optimized control plane for deterministic, automated Hurd environment management

**Scope**: Debian GNU/Hurd x86_64 only (i386 deprecated 2025-11-07)

---

## Overview

The GNU/Hurd Docker control plane provides **five independent channels** for accessing and controlling the virtualized environment. This multi-channel architecture enables:

- **Automation**: QMP (QEMU Machine Protocol) for JSON-based machine control
- **Interactive Access**: SSH with key-based authentication for secure shell access
- **Boot Debugging**: Serial console for firmware, kernel, and early boot messages
- **Manual Inspection**: HMP (Human Monitor Protocol) for ad-hoc device queries
- **File Exchange**: 9p/VirtIO filesystem for bidirectional host↔guest file sharing

**Design Goal**: Create a reproducible, deterministic environment optimized for CLI access from Claude Code and other LLM-based development tools.

---

## Architecture: Five-Channel Control Plane

```
┌─────────────────────────────────────────────────────────────┐
│                      Docker Container                        │
│                   (hurd-x86_64-qemu)                         │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                    QEMU Process                        │  │
│  │              (qemu-system-x86_64)                      │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │        GNU/Hurd x86_64 Guest System             │  │  │
│  │  │        (debian-hurd-amd64)                      │  │  │
│  │  │                                                 │  │  │
│  │  │  ┌──────────────────────────────────────────┐  │  │  │
│  │  │  │  1. SSH (port 2222)                      │  │  │  │
│  │  │  │     ✓ Key-based authentication only      │  │  │  │
│  │  │  │     ✓ tmux auto-attach on connect        │  │  │  │
│  │  │  │     ✓ mosh for resilient sessions        │  │  │  │
│  │  │  │     ✓ Persistent across reconnections    │  │  │  │
│  │  │  └──────────────────────────────────────────┘  │  │  │
│  │  │  ┌──────────────────────────────────────────┐  │  │  │
│  │  │  │  2. Serial Console (telnet :5555)        │  │  │  │
│  │  │  │     ✓ GRUB boot menu                     │  │  │  │
│  │  │  │     ✓ Kernel boot messages               │  │  │  │
│  │  │  │     ✓ Early boot debugging               │  │  │  │
│  │  │  │     ✓ Direct tty0 access                 │  │  │  │
│  │  │  └──────────────────────────────────────────┘  │  │  │
│  │  │  ┌──────────────────────────────────────────┐  │  │  │
│  │  │  │  3. 9p Filesystem (virtio transport)     │  │  │  │
│  │  │  │     ✓ Host /share ↔ Guest /mnt/host     │  │  │  │
│  │  │  │     ✓ Bidirectional file access          │  │  │  │
│  │  │  │     ✓ No network overhead                │  │  │  │
│  │  │  │     ✓ Shared scripts and data            │  │  │  │
│  │  │  └──────────────────────────────────────────┘  │  │  │
│  │  └─────────────────────────────────────────────┘  │  │  │
│  │                                                     │  │  │
│  │  4. QMP Socket (unix:/qmp/qmp.sock)               │  │  │
│  │     ✓ JSON-based automation interface             │  │  │
│  │     ✓ Machine control (power, reset, snapshot)    │  │  │
│  │     ✓ sendkey injection for boot menu             │  │  │
│  │     ✓ Device hot-plug/unplug                      │  │  │
│  │     ✓ Query VM status                             │  │  │
│  │                                                     │  │  │
│  │  5. HMP Monitor (telnet :9999)                    │  │  │
│  │     ✓ Human-readable monitor commands             │  │  │
│  │     ✓ Device inspection and debugging             │  │  │
│  │     ✓ Real-time state queries                     │  │  │
│  │     ✓ Ad-hoc system control                       │  │  │
│  └─────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Channel Summary

| Channel | Port/Path | Protocol | Purpose | Primary Use |
|---------|-----------|----------|---------|-------------|
| **SSH** | localhost:2222 | SSH (TCP) | Secure shell access | Interactive development, command execution |
| **Serial** | localhost:5555 | Telnet (TCP) | Console output | Boot debugging, kernel messages, GRUB |
| **9p** | mount_tag=scripts | VirtIO | File sharing | Scripts, configs, build artifacts |
| **QMP** | /qmp/qmp.sock | UNIX socket (JSON) | Automation | Power control, snapshots, key injection |
| **HMP** | localhost:9999 | Telnet (TCP) | Human monitor | Device inspection, debugging |

---

## Channel 1: SSH Access

### Configuration

**Host → Container → Guest Port Forwarding**:
```
Host: localhost:2222
  ↓
Container: 2222 (exposed in docker-compose.yml)
  ↓
QEMU: hostfwd=tcp::2222-:22
  ↓
Guest: port 22 (sshd)
```

### Key-Based Authentication Setup

**On Host** (generate ED25519 key):
```bash
# Generate key pair
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

# Set correct permissions
chmod 600 ~/.ssh/hurd-dev
chmod 644 ~/.ssh/hurd-dev.pub
```

**Inside Hurd Guest** (first-time setup):
```bash
# Create SSH directory
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Add authorized key (copy public key from host)
# Option 1: Via serial console if SSH not yet working
# Option 2: Via 9p mount if already available
cat /mnt/host/hurd-dev.pub > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# Harden SSH configuration
cat > /etc/ssh/sshd_config.d/10-llm-hardening.conf << 'EOF'
# LLM-optimized SSH hardening
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password
ClientAliveInterval 30
ClientAliveCountMax 6
MaxStartups 10:30:100
EOF

# Restart SSH service
systemctl restart ssh
# or (if systemd not available)
/etc/init.d/ssh restart
```

**Test from Host**:
```bash
# Connect without password
ssh hurd-local "uname -a"

# Expected output:
# GNU hurd 0.9 GNU-Mach 1.8+git20230625/Hurd-0.9 x86_64 GNU
```

### Security Benefits

- ✅ **No password exposure**: Key-based only, passwords disabled
- ✅ **Non-interactive authentication**: Suitable for automation
- ✅ **Session persistence**: ClientAliveInterval prevents timeouts
- ✅ **Known host bypass**: For ephemeral container IPs

---

## Channel 2: Serial Console

### Configuration

**QEMU Serial Console Setup** (from entrypoint.sh):
```bash
-serial telnet:0.0.0.0:5555,server,nowait
```

**Access from Host**:
```bash
# Connect to serial console
telnet localhost 5555

# Exit telnet: Ctrl+], then type "quit"
```

### Use Cases

#### 1. GRUB Boot Menu Access
```
# Watch boot process
telnet localhost 5555

# When GRUB menu appears, press 'e' to edit
# Or wait for auto-boot (5 second timeout)
```

#### 2. Kernel Boot Messages
```
# Kernel output before SSH is available
[    0.000000] Linux version 6.1.0-18-amd64 ...
[    0.000000] Command line: BOOT_IMAGE=/boot/gnumach.gz root=device:hd0s1
[    1.234567] ACPI: Core revision 20221020
...
```

#### 3. Early Boot Debugging
```
# If SSH fails to start, serial console remains accessible
# Check service status, view logs, manually start sshd
```

#### 4. Emergency Access
```
# If network configuration breaks, serial provides fallback
# Can reconfigure network from serial console
```

### Serial Console Commands

**Inside Guest** (after boot):
```bash
# Check current console
tty
# Output: /dev/console or /dev/hvc0

# View kernel ring buffer
dmesg | less

# Monitor logs in real-time
tail -f /var/log/syslog
```

---

## Channel 3: 9p File Sharing

### Configuration

**QEMU 9p Export** (from entrypoint.sh):
```bash
-virtfs local,path=/share,mount_tag=scripts,security_model=none,id=fsdev0
```

**Docker Volume Mount** (docker-compose.yml):
```yaml
volumes:
  - ./share:/share:rw
```

### Mounting in Guest

**First-Time Mount**:
```bash
# Create mount point
mkdir -p /mnt/host

# Mount 9p filesystem
mount -t 9p -o trans=virtio scripts /mnt/host

# Verify
ls -la /mnt/host

# Expected: Files from host ./share/ directory
```

**Persistent Mount** (add to /etc/fstab):
```bash
# Add to /etc/fstab
echo "scripts /mnt/host 9p trans=virtio,version=9p2000.L,rw 0 0" >> /etc/fstab

# Test mount
mount -a
```

**Automatic Mount at Boot** (systemd):
```bash
# Create systemd mount unit
cat > /etc/systemd/system/mnt-host.mount << 'EOF'
[Unit]
Description=9p Host File Sharing
After=network.target

[Mount]
What=scripts
Where=/mnt/host
Type=9p
Options=trans=virtio,version=9p2000.L,rw

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
systemctl daemon-reload
systemctl enable --now mnt-host.mount
```

### Use Cases

#### 1. Provisioning Scripts
```bash
# Host: Place scripts in ./share/
cp provision-hurd.sh ./share/

# Guest: Execute from /mnt/host
bash /mnt/host/provision-hurd.sh
```

#### 2. Build Artifacts
```bash
# Guest: Build software
cd /tmp/myproject
make
cp myproject.bin /mnt/host/

# Host: Artifact now in ./share/myproject.bin
ls -lh ./share/myproject.bin
```

#### 3. Configuration Files
```bash
# Host: Provide SSH public key
cp ~/.ssh/hurd-dev.pub ./share/

# Guest: Install key
cat /mnt/host/hurd-dev.pub >> /root/.ssh/authorized_keys
```

#### 4. Log Collection
```bash
# Guest: Export logs for analysis
cp /var/log/syslog /mnt/host/syslog-$(date +%Y%m%d).log

# Host: Analyze logs
less ./share/syslog-20251107.log
```

### Performance Notes

- **Protocol**: 9p2000.L (Linux extensions enabled)
- **Transport**: VirtIO (no network overhead)
- **Security**: security_model=none (no permission mapping, full access)
- **Latency**: Low (direct memory mapping)
- **Throughput**: ~500-800 MB/s (depending on host filesystem)

**Not Recommended For**:
- High-frequency small writes (use RAM disk, then copy)
- Database files (use guest disk, export periodically)
- Large file transfers (consider scp for better performance)

---

## Channel 4: QMP (QEMU Machine Protocol)

### Configuration

**QEMU QMP Socket** (from entrypoint.sh):
```bash
-chardev socket,id=qmp0,path=/qmp/qmp.sock,server=on,wait=off
-qmp chardev:qmp0
```

**Docker Volume Mount**:
```yaml
volumes:
  - qmp-socket:/qmp:rw
```

### QMP Control Tool

**scripts/qmp_ctl.py** (Python automation wrapper):
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

### Common QMP Operations

#### 1. Query VM Status
```bash
docker exec hurd-x86_64-qemu python3 /scripts/qmp_ctl.py /qmp/qmp.sock \
  '{"execute":"query-status"}'

# Response:
{
  "return": {
    "status": "running",
    "singlestep": false,
    "running": true
  }
}
```

#### 2. Power Control
```bash
# Graceful shutdown (ACPI power button)
docker exec hurd-x86_64-qemu python3 /scripts/qmp_ctl.py /qmp/qmp.sock \
  '{"execute":"system_powerdown"}'

# Hard reset
docker exec hurd-x86_64-qemu python3 /scripts/qmp_ctl.py /qmp/qmp.sock \
  '{"execute":"system_reset"}'

# Pause VM
docker exec hurd-x86_64-qemu python3 /scripts/qmp_ctl.py /qmp/qmp.sock \
  '{"execute":"stop"}'

# Resume VM
docker exec hurd-x86_64-qemu python3 /scripts/qmp_ctl.py /qmp/qmp.sock \
  '{"execute":"cont"}'
```

#### 3. Send Keyboard Keys (Boot Menu)
```bash
# Send F12 key (GRUB boot menu)
docker exec hurd-x86_64-qemu python3 /scripts/qmp_ctl.py /qmp/qmp.sock \
  '{"execute":"human-monitor-command","arguments":{"command-line":"sendkey f12"}}'

# Send Enter key
docker exec hurd-x86_64-qemu python3 /scripts/qmp_ctl.py /qmp/qmp.sock \
  '{"execute":"human-monitor-command","arguments":{"command-line":"sendkey ret"}}'

# Type text (automation)
for key in h e l l o; do
  docker exec hurd-x86_64-qemu python3 /scripts/qmp_ctl.py /qmp/qmp.sock \
    "{\"execute\":\"human-monitor-command\",\"arguments\":{\"command-line\":\"sendkey $key\"}}"
  sleep 0.1
done
```

#### 4. Snapshot Management
```bash
# Create snapshot
docker exec hurd-x86_64-qemu python3 /scripts/qmp_ctl.py /qmp/qmp.sock \
  '{"execute":"human-monitor-command","arguments":{"command-line":"savevm snapshot1"}}'

# List snapshots
docker exec hurd-x86_64-qemu python3 /scripts/qmp_ctl.py /qmp/qmp.sock \
  '{"execute":"human-monitor-command","arguments":{"command-line":"info snapshots"}}'

# Load snapshot
docker exec hurd-x86_64-qemu python3 /scripts/qmp_ctl.py /qmp/qmp.sock \
  '{"execute":"human-monitor-command","arguments":{"command-line":"loadvm snapshot1"}}'
```

#### 5. Device Hot-Plug (Advanced)
```bash
# Add USB device
docker exec hurd-x86_64-qemu python3 /scripts/qmp_ctl.py /qmp/qmp.sock \
  '{"execute":"device_add","arguments":{"driver":"usb-host","id":"usb1"}}'

# Remove device
docker exec hurd-x86_64-qemu python3 /scripts/qmp_ctl.py /qmp/qmp.sock \
  '{"execute":"device_del","arguments":{"id":"usb1"}}'
```

### Direct QMP Access (socat)

**Without Python Wrapper**:
```bash
# Connect to QMP socket
docker exec -it hurd-x86_64-qemu socat - UNIX-CONNECT:/qmp/qmp.sock

# QMP greeting (JSON)
{"QMP": {"version": {...}, "capabilities": [...]}}

# Send capabilities negotiation
{"execute":"qmp_capabilities"}

# Send command
{"execute":"query-status"}

# Response
{"return": {"status": "running", "singlestep": false, "running": true}}
```

---

## Channel 5: HMP (Human Monitor Protocol)

### Configuration

**QEMU HMP Monitor** (from entrypoint.sh):
```bash
-monitor telnet:0.0.0.0:9999,server,nowait
```

**Access from Host**:
```bash
# Connect to HMP monitor
telnet localhost 9999

# QEMU monitor prompt appears:
QEMU 8.0.0 monitor - type 'help' for more information
(qemu)
```

### Common HMP Commands

#### 1. System Information
```
(qemu) info version
8.0.0

(qemu) info status
VM status: running

(qemu) info registers
CPU#0
RAX=0000000000000000 RBX=0000000000000000 RCX=0000000000000000 RDX=0000000000000000
...

(qemu) info cpus
* CPU #0: thread_id=12345
```

#### 2. Device Inspection
```
(qemu) info block
ide0-hd0 (#block123): /opt/hurd-image/debian-hurd-amd64.qcow2 (qcow2)
    Cache mode:       writeback

(qemu) info network
net0: index=0,type=user,ifname=tap0
  hostfwd=tcp::2222-:22
  hostfwd=tcp::8080-:80

(qemu) info usb
  Device 0.0, Port 1, Speed 12 Mb/s, Product QEMU USB Tablet

(qemu) info pci
  Bus  0, device   0, function 0:
    Host bridge: PCI device 8086:1237
  Bus  0, device   1, function 0:
    IDE controller: PCI device 8086:7010
```

#### 3. Memory and Storage
```
(qemu) info mem
0000000000000000-00000000000a0000 0000000000000000 -rw
00000000000a0000-00000000000b0000 00000000000a0000 -rw
...

(qemu) info snapshots
ID        TAG                 VM SIZE                DATE       VM CLOCK
1         snapshot1                4.3G 2025-11-07 14:30:00   00:00:45.123
```

#### 4. Keyboard Injection
```
(qemu) sendkey f12
OK

(qemu) sendkey ctrl-alt-delete
OK

(qemu) sendkey ret
OK
```

#### 5. Power Control
```
(qemu) system_powerdown
(initiates ACPI shutdown)

(qemu) system_reset
(hard reset)

(qemu) stop
(pause VM)

(qemu) cont
(resume VM)

(qemu) quit
(terminate QEMU - will stop container)
```

#### 6. Snapshot Management
```
(qemu) savevm snapshot1
OK

(qemu) loadvm snapshot1
OK

(qemu) delvm snapshot1
OK

(qemu) info snapshots
(lists all snapshots)
```

### HMP vs QMP

| Feature | HMP | QMP |
|---------|-----|-----|
| **Interface** | Human-readable text | JSON |
| **Automation** | Difficult (parsing text) | Easy (structured JSON) |
| **Interactive** | Yes (telnet) | No (requires wrapper) |
| **Scripting** | Limited | Full support |
| **Error Handling** | Text messages | JSON error codes |
| **Use Case** | Manual debugging | Automation, LLM tools |

**Recommendation**: Use **HMP** for manual inspection, **QMP** for automation and scripting.

---

## mosh: Resilient Sessions

### Why mosh?

Traditional SSH disconnects on:
- Network changes (WiFi roaming)
- Laptop sleep/wake
- IP address changes
- Temporary packet loss

**mosh** (mobile shell) provides:
- ✅ Persistent sessions across network changes
- ✅ Instant keystroke response (predictive typing)
- ✅ Automatic reconnection
- ✅ UDP-based transport (tolerates packet loss)

### Installation

**Inside Hurd Guest**:
```bash
apt-get update
apt-get install -y mosh
```

**On Host** (if not already installed):
```bash
# CachyOS/Arch
pacman -S mosh

# Ubuntu/Debian
apt-get install -y mosh

# macOS
brew install mosh
```

### Port Configuration

**Update docker-compose.yml** (expose mosh UDP ports):
```yaml
ports:
  - "2222:2222"                     # SSH
  - "8080:8080"                     # HTTP
  - "5555:5555"                     # Serial console
  - "9999:9999"                     # HMP monitor
  - "60000-60010:60000-60010/udp"   # mosh (10 concurrent sessions)
```

**Update entrypoint.sh** (QEMU port forwarding):
```bash
-netdev user,id=net0,\
hostfwd=tcp::2222-:22,\
hostfwd=tcp::8080-:80,\
hostfwd=udp::60000-:60000,\
hostfwd=udp::60001-:60001,\
...
hostfwd=udp::60010-:60010
```

### Usage

**Connect from Host**:
```bash
# Basic mosh connection
mosh --ssh="ssh -p 2222" root@localhost

# Specify mosh port range
mosh --ssh="ssh -p 2222" -p 60000:60010 root@localhost

# With SSH config alias (from earlier)
mosh --ssh="ssh hurd-local" localhost
```

**Expected Behavior**:
- Initial connection via SSH (port 2222)
- Upgrade to mosh UDP (port 60000-60010)
- Persistent session even if laptop sleeps or network changes

---

## tmux: Auto-Attach for Persistent Sessions

### Why tmux Auto-Attach?

**Problem**: LLM workflows involve frequent connect/disconnect cycles:
- Claude Code disconnects after inactivity
- Multiple terminal sessions lose state
- Screen session management overhead

**Solution**: tmux auto-attach on SSH login:
- Every connection joins the same persistent session
- Session state preserved across reconnections
- Scrollback history available
- Multiple windows/panes supported

### Configuration

**Inside Hurd Guest** (create SSH RC script):
```bash
# Install tmux
apt-get install -y tmux

# Create auto-attach script
cat > /root/.ssh/rc << 'EOF'
#!/bin/sh
# Auto-attach to tmux session "main" (create if doesn't exist)
exec tmux new-session -A -s main
EOF

chmod +x /root/.ssh/rc
```

### Behavior

**First Connection**:
```bash
ssh hurd-local

# Creates new tmux session "main"
# You are now in tmux
```

**Second Connection** (from different terminal):
```bash
ssh hurd-local

# Attaches to existing "main" session
# You see the same state as first connection
```

**After Disconnect**:
```bash
# Close SSH session (Ctrl+D or network disconnect)
# Session persists on Hurd guest

# Reconnect
ssh hurd-local

# Session restored with scrollback, running processes, etc.
```

### tmux Commands

**Inside Session**:
```bash
# Detach from session (leave running)
Ctrl+b d

# Create new window
Ctrl+b c

# Switch windows
Ctrl+b 0-9

# Split pane horizontally
Ctrl+b "

# Split pane vertically
Ctrl+b %

# Navigate panes
Ctrl+b arrow keys
```

**From Outside**:
```bash
# List sessions
tmux list-sessions

# Attach to specific session
tmux attach -t main

# Kill session
tmux kill-session -t main
```

---

## Complete Provisioning Script

**scripts/provision-hurd.sh** (run once inside guest for full setup):

```bash
#!/bin/bash
set -e

echo "==================================================================="
echo "  GNU/Hurd x86_64 LLM-Optimized Provisioning"
echo "==================================================================="

# 1. Update package lists
echo "[1/7] Updating package lists..."
apt-get update

# 2. Install resilience tools (mosh, tmux)
echo "[2/7] Installing mosh and tmux..."
apt-get install -y mosh tmux

# 3. Install core utilities
echo "[3/7] Installing core utilities..."
apt-get install -y git curl wget vim emacs-nox netcat-openbsd

# 4. Install all development tools
echo "[4/7] Installing development tools..."
apt-get install -y \
    gcc g++ make cmake autoconf automake libtool \
    pkg-config flex bison texinfo \
    clang llvm lld binutils-dev libelf-dev \
    gnumach-dev hurd-dev mig hurd-doc \
    gdb strace ltrace sysstat \
    meson ninja-build \
    doxygen graphviz

# 5. Setup SSH key-based authentication
echo "[5/7] Configuring SSH hardening..."
if [ -f /mnt/host/hurd-dev.pub ]; then
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    cp /mnt/host/hurd-dev.pub /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys

    cat > /etc/ssh/sshd_config.d/10-llm-hardening.conf << 'EOF'
# LLM-optimized SSH hardening
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password
ClientAliveInterval 30
ClientAliveCountMax 6
MaxStartups 10:30:100
EOF

    systemctl restart ssh || /etc/init.d/ssh restart
    echo "✓ SSH hardening enabled (key-based auth only)"
else
    echo "⚠ SSH key not found at /mnt/host/hurd-dev.pub"
    echo "  Run on host: cp ~/.ssh/hurd-dev.pub ./share/"
fi

# 6. Setup tmux auto-attach
echo "[6/7] Configuring tmux auto-attach..."
cat > /root/.ssh/rc << 'EOF'
#!/bin/sh
# Auto-attach to tmux session "main" on SSH login
exec tmux new-session -A -s main
EOF
chmod +x /root/.ssh/rc

# 7. Configure shell environment
echo "[7/7] Configuring shell environment..."
cat >> /root/.bashrc << 'EOF'

# GNU/Hurd x86_64 Development Environment
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

# Custom prompt
export PS1='\[\033[01;32m\]\u@hurd-x86_64\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
EOF

# Verification
echo ""
echo "==================================================================="
echo "  Verification"
echo "==================================================================="
echo "GCC:          $(gcc --version | head -1)"
echo "MIG:          $(which mig)"
echo "Mach headers: $(ls /usr/include/mach/ 2>/dev/null | wc -l) files"
echo "Hurd headers: $(ls /usr/include/hurd/ 2>/dev/null | wc -l) files"
echo "mosh:         $(which mosh)"
echo "tmux:         $(which tmux)"
echo ""
echo "✓ Provisioning complete!"
echo "==================================================================="
echo ""
echo "Next Steps:"
echo "  1. Exit SSH session"
echo "  2. Reconnect: ssh hurd-local"
echo "  3. tmux session will auto-attach"
echo "  4. Or use: mosh --ssh='ssh hurd-local' localhost"
echo ""
```

### Usage

**From Host** (prepare):
```bash
# Copy SSH public key to shared directory
cp ~/.ssh/hurd-dev.pub ./share/

# Copy provisioning script
cp scripts/provision-hurd.sh ./share/
```

**From Guest** (via serial console or initial SSH):
```bash
# Mount shared directory
mkdir -p /mnt/host
mount -t 9p -o trans=virtio scripts /mnt/host

# Run provisioning
bash /mnt/host/provision-hurd.sh

# Wait for completion (~5-10 minutes)
```

**After Provisioning**:
```bash
# Exit and reconnect
exit

# Reconnect with mosh (resilient)
mosh --ssh="ssh hurd-local" localhost

# Or standard SSH
ssh hurd-local

# tmux auto-attaches, persistent session ready!
```

---

## Systemd User Service (Persistent Container)

**Purpose**: Keep Hurd container running across host reboots

**~/.config/systemd/user/hurd-docker.service**:
```ini
[Unit]
Description=GNU/Hurd Docker Container (x86_64 LLM-optimized)
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

**Enable and Start**:
```bash
# Reload systemd user daemon
systemctl --user daemon-reload

# Enable service (start at login)
systemctl --user enable hurd-docker.service

# Start immediately
systemctl --user start hurd-docker.service

# Keep running after logout
loginctl enable-linger "$USER"

# Check status
systemctl --user status hurd-docker.service
```

**Behavior**:
- Container starts automatically on user login
- Container restarts if crashes
- Container persists after logout (with linger enabled)
- Container stops cleanly on shutdown

---

## Implementation Checklist

### Infrastructure ✓
- [x] entrypoint.sh with full control plane (QMP, HMP, serial, 9p)
- [x] HMP monitor exposed on port 9999
- [x] QMP socket available at /qmp/qmp.sock
- [x] Serial console on port 5555
- [x] 9p file sharing configured

### Automation
- [ ] Create qmp_ctl.py automation tool
- [ ] Test QMP commands (query-status, system_reset, sendkey)
- [ ] Test HMP commands (info, sendkey, snapshot)
- [ ] Document common automation patterns

### SSH Hardening
- [ ] Generate ED25519 key on host
- [ ] Copy public key to ./share/ directory
- [ ] Configure SSH hardening inside Hurd
- [ ] Test key-based authentication
- [ ] Disable password authentication

### Resilience
- [ ] Install mosh inside Hurd guest
- [ ] Expose mosh UDP ports (60000-60010) in docker-compose.yml
- [ ] Add QEMU port forwarding for mosh
- [ ] Test mosh connection from host
- [ ] Setup tmux auto-attach
- [ ] Verify persistent sessions across reconnections

### Automation Scripts
- [ ] Create provision-hurd.sh script
- [ ] Test provisioning on fresh Hurd install
- [ ] Create clean snapshot after provisioning
- [ ] Document snapshot management

### Service Management
- [ ] Create systemd user service
- [ ] Test service start/stop/restart
- [ ] Enable linger for persistent operation
- [ ] Verify service persistence across reboots

### Verification (Post-Provisioning)
- [ ] SSH works with keys only (no passwords)
- [ ] mosh provides resilient connection
- [ ] tmux auto-attaches on connect
- [ ] All dev tools installed (gnumach-dev, hurd-dev, mig, gcc, etc.)
- [ ] QMP automation functional from host
- [ ] HMP monitor accessible via telnet
- [ ] Serial console accessible for boot debugging
- [ ] 9p file sharing bidirectional

---

## Troubleshooting

### SSH Connection Refused

**Symptom**: `ssh -p 2222 localhost` fails with "Connection refused"

**Diagnosis**:
```bash
# Check if VM is running
docker ps | grep hurd-x86_64-qemu

# Check container logs
docker logs hurd-x86_64-qemu | tail -50

# Check if SSH is listening inside guest (via serial console)
telnet localhost 5555
# Inside guest:
netstat -tlnp | grep :22
```

**Fixes**:
1. Wait for boot to complete (x86_64 can take 5-10 minutes)
2. Start SSH manually: `systemctl start ssh` or `/etc/init.d/ssh start`
3. Check SSH config: `sshd -t` (test configuration)
4. Verify port forwarding in QEMU command line

### QMP Socket Not Found

**Symptom**: `python3 qmp_ctl.py /qmp/qmp.sock` fails with "No such file or directory"

**Diagnosis**:
```bash
# Check if socket directory exists
docker exec hurd-x86_64-qemu ls -la /qmp/

# Check QEMU process command line
docker exec hurd-x86_64-qemu ps aux | grep qemu
```

**Fixes**:
1. Ensure `/qmp` directory created in entrypoint.sh: `mkdir -p /qmp`
2. Check QEMU command includes: `-chardev socket,id=qmp0,path=/qmp/qmp.sock,server=on,wait=off`
3. Verify volume mount in docker-compose.yml
4. Restart container: `docker-compose restart`

### 9p Mount Fails

**Symptom**: `mount -t 9p -o trans=virtio scripts /mnt/host` fails

**Diagnosis**:
```bash
# Check if mount_tag is correct
docker logs hurd-x86_64-qemu | grep virtfs

# Check kernel module loaded
lsmod | grep 9p

# Check QEMU command line
docker exec hurd-x86_64-qemu ps aux | grep virtfs
```

**Fixes**:
1. Load 9p modules: `modprobe 9pnet 9pnet_virtio 9p`
2. Verify mount_tag matches: `-virtfs ... mount_tag=scripts`
3. Check filesystem type: `mount -t 9p` (not `9pfs`)
4. Try with version: `mount -t 9p -o trans=virtio,version=9p2000.L scripts /mnt/host`

### Serial Console Blank

**Symptom**: `telnet localhost 5555` connects but shows no output

**Diagnosis**:
```bash
# Check if QEMU is running
docker ps

# Check entrypoint.sh QEMU command
docker exec hurd-x86_64-qemu cat /proc/1/cmdline | tr '\0' ' '
```

**Fixes**:
1. Wait for boot (GRUB menu may have auto-selected)
2. Press Enter to wake console
3. Verify QEMU includes: `-serial telnet:0.0.0.0:5555,server,nowait`
4. Check for `-nographic` flag (required for serial console to be primary)

### mosh Connection Fails

**Symptom**: `mosh --ssh="ssh -p 2222" root@localhost` hangs or fails

**Diagnosis**:
```bash
# Check if mosh is installed inside guest
ssh hurd-local "which mosh"

# Check UDP ports exposed
docker port hurd-x86_64-qemu | grep udp

# Test SSH connection first
ssh hurd-local "echo OK"
```

**Fixes**:
1. Install mosh inside guest: `apt-get install -y mosh`
2. Expose UDP ports in docker-compose.yml: `60000-60010:60000-60010/udp`
3. Add QEMU port forwarding for UDP: `hostfwd=udp::60000-:60000,...`
4. Check firewall: `iptables -L -n -v | grep 60000`
5. Try explicit port range: `mosh -p 60000:60010 --ssh="ssh hurd-local" localhost`

---

## Performance Notes

### Channel Latency Comparison

| Channel | Typical Latency | Use Case |
|---------|----------------|----------|
| **SSH** | 1-5 ms | Interactive shell, command execution |
| **mosh** | 0.1-1 ms (predictive) | Resilient interactive sessions |
| **Serial** | 5-10 ms | Boot debugging, kernel messages |
| **9p** | 0.5-2 ms (read), 2-10 ms (write) | File sharing, scripts |
| **QMP** | 1-3 ms | Automation, snapshot control |
| **HMP** | 5-15 ms | Manual inspection |

### Throughput Comparison

| Channel | Read Throughput | Write Throughput |
|---------|----------------|------------------|
| **SSH** | ~50-100 MB/s | ~50-100 MB/s |
| **9p** | ~500-800 MB/s | ~300-600 MB/s |

**Recommendation**: Use 9p for bulk file transfers, SSH for interactive work.

---

## Security Considerations

### SSH Hardening

✅ **Enabled**:
- Key-based authentication only
- Root login with keys only (no password)
- Connection timeout prevention (ClientAlive)

❌ **Disabled**:
- Password authentication
- Interactive keyboard authentication
- Empty password login

### Network Isolation

**User-Mode NAT**:
- Guest cannot access host network directly
- Guest only sees forwarded ports (22, 80, 9999)
- No raw socket access from guest

**Port Forwarding**:
- SSH: localhost:2222 → guest:22 (authenticated)
- HTTP: localhost:8080 → guest:80 (unauthenticated)
- HMP: localhost:9999 → QEMU monitor (localhost-only)
- Serial: localhost:5555 → QEMU serial (localhost-only)

### 9p File Sharing

**Security Model**: `security_model=none`
- No user/group ID mapping
- Guest has full access to shared directory
- **Risk**: Guest compromise = shared directory compromise
- **Mitigation**: Only share necessary files, not entire home directory

**Recommendation**: Use dedicated `./share/` directory, not `~/` or `/`

---

## Reference: Complete entrypoint.sh

**Enhanced entrypoint.sh with Full Control Plane**:

```bash
#!/bin/bash
# GNU/Hurd Docker - x86_64-only entrypoint with full control plane
set -e

# Configuration
QCOW2_IMAGE="${QEMU_DRIVE:-/opt/hurd-image/debian-hurd-amd64.qcow2}"
QEMU_RAM="${QEMU_RAM:-4096}"
QEMU_SMP="${QEMU_SMP:-2}"
SERIAL_PORT="${SERIAL_PORT:-5555}"
MONITOR_PORT="${MONITOR_PORT:-9999}"
SHARE_TAG="${SHARE_TAG:-scripts}"
DISPLAY_MODE="${DISPLAY_MODE:-nographic}"

# Logging
log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

# KVM auto-detection
detect_acceleration() {
    if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        echo "kvm"
        log_info "KVM hardware acceleration detected"
    else
        echo "tcg"
        log_warn "KVM not available, using TCG software emulation"
    fi
}

ACCEL=$(detect_acceleration)
if [ "$ACCEL" = "kvm" ]; then
    KVM_OPTS=(-accel kvm -accel tcg,thread=multi -cpu host)
else
    KVM_OPTS=(-accel kvm -accel tcg,thread=multi -cpu max)
fi

# Display configuration
DISPLAY_OPTS=(-nographic)
case "$DISPLAY_MODE" in
    vnc)
        DISPLAY_OPTS=(-vnc :0)
        DISPLAY_MSG="VNC on :0 (port 5900)"
        ;;
    sdl)
        DISPLAY_OPTS=(-display sdl)
        DISPLAY_MSG="SDL window"
        ;;
    gtk)
        DISPLAY_OPTS=(-display gtk)
        DISPLAY_MSG="GTK window"
        ;;
    *)
        DISPLAY_MSG="No graphics (serial console only)"
        ;;
esac

# 9p file sharing
SHARE_OPTS=()
if [ -d /share ]; then
    SHARE_OPTS=(
        -virtfs local,path=/share,mount_tag="$SHARE_TAG",security_model=none,id=fsdev0
    )
    SHARE_MSG="9p export /share as '$SHARE_TAG'"
else
    SHARE_MSG="No file sharing (mkdir /share to enable)"
fi

# Print configuration banner
cat <<EOF

======================================================================
  GNU/Hurd Docker - x86_64 LLM-Optimized Control Plane
======================================================================

Configuration:
  - Image: $QCOW2_IMAGE
  - Memory: $QEMU_RAM MB
  - CPU: host (if KVM) or max (if TCG)
  - SMP: $QEMU_SMP core(s)
  - Acceleration: $ACCEL

Control Channels (LLM-accessible):
  1. SSH:           localhost:2222 → guest:22
  2. Serial Console: telnet localhost:$SERIAL_PORT
  3. QMP Socket:    /qmp/qmp.sock (JSON automation)
  4. HMP Monitor:   telnet localhost:$MONITOR_PORT
  5. File Sharing:  $SHARE_MSG
     Mount in guest: mount -t 9p -o trans=virtio $SHARE_TAG /mnt/host

Display: $DISPLAY_MSG

Automation Tools:
  - QMP: python3 /scripts/qmp_ctl.py /qmp/qmp.sock '<json>'
  - Serial: telnet localhost:$SERIAL_PORT
  - HMP: telnet localhost:$MONITOR_PORT

Logs:
  - QEMU errors: /var/log/qemu/guest-errors.log
  - Container logs: docker logs hurd-x86_64-qemu

======================================================================

EOF

# Wait for sockets directory
mkdir -p /qmp
sleep 0.5

# Launch QEMU with full control plane
exec /usr/bin/qemu-system-x86_64 \
    "${KVM_OPTS[@]}" \
    -m "$QEMU_RAM" \
    -smp "$QEMU_SMP" \
    -machine pc \
    \
    -drive file="$QCOW2_IMAGE",format=qcow2,cache=writeback,aio=threads,if=ide \
    \
    -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:80,hostfwd=udp::60000-:60000,hostfwd=udp::60001-:60001,hostfwd=udp::60002-:60002,hostfwd=udp::60003-:60003,hostfwd=udp::60004-:60004,hostfwd=udp::60005-:60005,hostfwd=udp::60006-:60006,hostfwd=udp::60007-:60007,hostfwd=udp::60008-:60008,hostfwd=udp::60009-:60009,hostfwd=udp::60010-:60010 \
    -device e1000,netdev=net0 \
    \
    -chardev socket,id=qmp0,path=/qmp/qmp.sock,server=on,wait=off \
    -qmp chardev:qmp0 \
    \
    -monitor telnet:0.0.0.0:"$MONITOR_PORT",server,nowait \
    \
    -serial telnet:0.0.0.0:"$SERIAL_PORT",server,nowait \
    \
    "${DISPLAY_OPTS[@]}" \
    "${SHARE_OPTS[@]}" \
    \
    -rtc base=utc,clock=host \
    -no-reboot \
    -d guest_errors \
    -D /var/log/qemu/guest-errors.log
```

---

## Summary

This control plane architecture provides **five independent, LLM-optimized channels** for managing the GNU/Hurd x86_64 environment:

1. **SSH (port 2222)**: Secure, key-based authenticated shell access
2. **Serial Console (telnet :5555)**: Boot debugging, kernel messages, GRUB menu
3. **9p Filesystem (virtio)**: Fast host↔guest file sharing
4. **QMP Socket (/qmp/qmp.sock)**: JSON automation for power, snapshots, device control
5. **HMP Monitor (telnet :9999)**: Human-readable device inspection

**Additional Features**:
- **mosh**: Resilient sessions across network changes
- **tmux auto-attach**: Persistent sessions across SSH reconnections
- **Systemd service**: Container persistence across host reboots

**Result**: A deterministic, reproducible, LLM-friendly development environment for GNU/Hurd x86_64 microkernel research and development.

---

**Status**: Production Ready (x86_64-only)
**Last Updated**: 2025-11-07
**Maintainer**: Oichkatzelesfrettschen
**Architecture**: Pure x86_64
