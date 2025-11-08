# GNU/Hurd Docker - Interactive Access Guide

**Last Updated**: 2025-11-07  
**Consolidated From**:
- INTERACTIVE-ACCESS-GUIDE.md (original guide)
- Control plane implementation details
- Serial console configuration

**Purpose**: Complete guide to accessing and controlling the GNU/Hurd guest system

**Scope**: Debian GNU/Hurd x86_64 only (i386 deprecated 2025-11-07)

---

## Overview

The GNU/Hurd Docker environment provides **five independent access channels** for interacting with the guest system:

1. **SSH** (Port 2222) - Primary access method
2. **Serial Console** (Port 5555) - Boot debugging and low-level access
3. **QEMU Monitor (HMP)** (Port 9999) - VM control and inspection
4. **QEMU Machine Protocol (QMP)** (Unix socket) - Programmatic automation
5. **9p/VirtIO File Sharing** - Host-guest file exchange

Each channel serves different purposes and has different requirements. This guide covers all five methods.

---

## Access Method Comparison

| Method | Port/Interface | Use Case | Requires Guest Boot | Network Needed |
|--------|----------------|----------|---------------------|----------------|
| SSH | 2222 | Primary shell access | Yes | Yes |
| Serial Console | 5555 | Boot debugging, early access | No | Yes |
| QEMU Monitor (HMP) | 9999 | VM control, inspection | No | Yes |
| QMP | Unix socket | Automation, scripting | No | No (local) |
| 9p VirtFS | Mount point | File transfer | Yes | No |

**Decision Tree**:
- **Need shell access after boot?** → SSH
- **Need to debug boot process?** → Serial Console
- **Need to control VM (pause, snapshot)?** → QEMU Monitor or QMP
- **Need to transfer files?** → 9p VirtFS
- **Need programmatic control?** → QMP

---

## Method 1: SSH Access (Primary Method)

**Purpose**: Standard remote shell access for development and administration

**Prerequisites**:
- Guest has fully booted (5-10 minutes)
- SSH server installed and running in guest
- Port 2222 accessible on host

### Quick Start

```bash
# Connect with default credentials
ssh -p 2222 root@localhost
# Password: root (or empty - try pressing Enter)
```

### Port Forwarding Architecture

```
Host: localhost:2222
  ↓ (Docker port mapping from docker-compose.yml)
Container: 2222
  ↓ (QEMU hostfwd=tcp::2222-:22 in entrypoint.sh)
Guest: port 22 (sshd)
```

### Checking SSH Readiness

```bash
# Method 1: Check if port is listening
nc -zv localhost 2222
# Expected: Connection succeeded

# Method 2: Check Docker logs
docker-compose logs -f | grep -i ssh
# Look for: "Server listening on 0.0.0.0 port 22"

# Method 3: Check via serial console
telnet localhost 5555
# Inside guest:
systemctl status ssh
# Expected: active (running)
```

### Installing SSH Server (if not present)

If SSH connection is refused, install openssh-server inside the guest:

```bash
# Connect via serial console first
telnet localhost 5555
# Press Enter for login prompt
# Username: root
# Password: root (or empty)

# Install SSH server
apt-get update
apt-get install -y openssh-server

# Enable and start SSH
systemctl enable ssh
systemctl start ssh

# Verify listening
ss -tlnp | grep :22
# Expected: LISTEN on 0.0.0.0:22

# Exit serial console
# Ctrl-] then type "quit"
```

### SSH Key-Based Authentication

For secure, passwordless access:

**On Host:**

```bash
# Generate ED25519 key (recommended)
ssh-keygen -t ed25519 -f ~/.ssh/hurd_dev -C "developer@gnu-hurd"

# Or generate RSA key (fallback)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/hurd_dev -C "developer@gnu-hurd"

# Create SSH config entry
cat >> ~/.ssh/config <<'EOF'
Host gnu-hurd
    HostName localhost
    Port 2222
    User root
    IdentityFile ~/.ssh/hurd_dev
    StrictHostKeyChecking accept-new
    ServerAliveInterval 60
    ServerAliveCountMax 3
EOF

chmod 600 ~/.ssh/config
```

**Transfer Public Key to Guest:**

```bash
# Method 1: Via 9p shared directory
cp ~/.ssh/hurd_dev.pub share/

# Inside guest (via serial console or existing SSH):
mkdir -p /root/.ssh
chmod 700 /root/.ssh
cat /mnt/host/hurd_dev.pub >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# Method 2: Via ssh-copy-id (if password auth works)
ssh-copy-id -i ~/.ssh/hurd_dev.pub -p 2222 root@localhost
```

**Test Key-Based Login:**

```bash
# Using config entry
ssh gnu-hurd

# Or explicitly
ssh -i ~/.ssh/hurd_dev -p 2222 root@localhost
```

### SSH Hardening (Optional)

**Inside Guest** (`/etc/ssh/sshd_config`):

```bash
# Disable password authentication (keys only)
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

# Disable root login with password
PermitRootLogin prohibit-password

# Disable empty passwords
PermitEmptyPasswords no

# Enable strict mode checking
StrictModes yes

# Restart SSH
systemctl restart ssh
```

**Verify Configuration:**

```bash
# Test from host (should succeed with key)
ssh -i ~/.ssh/hurd_dev -p 2222 root@localhost

# Test without key (should fail)
ssh -p 2222 root@localhost
# Expected: Permission denied (publickey)
```

### Advanced SSH Features

#### Port Forwarding

Forward guest services to host:

```bash
# Forward guest HTTP (port 80) to host port 8080
ssh -L 8080:localhost:80 -p 2222 root@localhost

# Access guest HTTP server from host browser
firefox http://localhost:8080
```

#### SOCKS Proxy

Use guest as SOCKS proxy:

```bash
# Create SOCKS proxy on host port 1080
ssh -D 1080 -p 2222 root@localhost

# Configure browser to use localhost:1080 as SOCKS5 proxy
```

#### Persistent Sessions with tmux

**Inside Guest:**

```bash
# Install tmux
apt-get install -y tmux

# Create persistent session
tmux new-session -s dev

# Detach from session: Ctrl-B, then D
# Reattach: tmux attach-session -t dev
```

**On Host (auto-attach on SSH):**

```bash
# Add to guest /root/.bashrc
if command -v tmux &>/dev/null && [ -z "$TMUX" ]; then
    tmux attach-session -t dev || tmux new-session -s dev
fi
```

#### Resilient Sessions with mosh

mosh provides resilient SSH sessions that survive network interruptions:

**Inside Guest:**

```bash
# Install mosh
apt-get install -y mosh

# Open UDP ports 60000-61000 for mosh
# Add to docker-compose.yml:
# ports:
#   - "60000-61000:60000-61000/udp"
```

**On Host:**

```bash
# Install mosh
pacman -S mosh  # CachyOS/Arch
# or: apt-get install mosh  # Debian/Ubuntu

# Connect via mosh
mosh --ssh="ssh -p 2222" root@localhost

# mosh will maintain connection even if network changes
```

---

## Method 2: Serial Console (Boot Debugging)

**Purpose**: Low-level access for boot debugging, when SSH is unavailable

**Advantages**:
- Available immediately (no guest boot required)
- Sees kernel messages and boot process
- Works even if network fails
- Direct console access (like physical terminal)

**Disadvantages**:
- No copy/paste
- No terminal features (colors, scrollback)
- Line-based (not full-screen)

### Connecting to Serial Console

```bash
# Using telnet
telnet localhost 5555

# Using nc (netcat)
nc localhost 5555

# Using socat (advanced)
socat -,raw,echo=0 tcp:localhost:5555
```

### Serial Console Configuration

**QEMU Parameters** (in entrypoint.sh):

```bash
-serial telnet:0.0.0.0:5555,server,nowait
```

- `telnet:0.0.0.0:5555` - Listen on all interfaces, port 5555
- `server` - QEMU acts as server (waits for client connection)
- `nowait` - Boot immediately, don't wait for telnet client

**Port Forwarding** (docker-compose.yml):

```yaml
ports:
  - "5555:5555"
```

### Using Serial Console

**Boot Messages:**

```bash
telnet localhost 5555
# You'll see:
# GNU Mach 2.x
# Booting...
# [kernel messages]
# Login:
```

**Login:**

```bash
# Press Enter to get login prompt
Login: root
Password: root
# (or empty password - press Enter)

# You're now in a shell
uname -a
# Expected: GNU/Hurd ... x86_64
```

**Exiting Serial Console:**

```bash
# Telnet escape sequence
Ctrl-]
telnet> quit

# Or close terminal window
```

### Serial Console Troubleshooting

**Problem: No output on serial console**

```bash
# Check QEMU is running
docker-compose ps
# Expected: hurd-x86_64-qemu running

# Check port is listening
nc -zv localhost 5555
# Expected: Connection succeeded

# Check Docker logs
docker-compose logs -f | grep serial
# Look for: "-serial telnet:0.0.0.0:5555"
```

**Problem: Connection refused**

```bash
# Verify port mapping in docker-compose.yml
grep 5555 docker-compose.yml
# Expected: - "5555:5555"

# Restart container
docker-compose restart
```

**Problem: Garbled output**

```bash
# Try different terminal emulator
# Or use raw mode with socat:
socat -,raw,echo=0 tcp:localhost:5555
```

---

## Method 3: QEMU Monitor (HMP) - VM Control

**Purpose**: Human-friendly monitor interface for VM control and inspection

**Use Cases**:
- Pause/resume VM
- Take snapshots
- Inspect memory and CPU state
- Change removable media
- Debug VM issues

### Connecting to QEMU Monitor

```bash
# Using telnet
telnet localhost 9999

# Using nc
nc localhost 9999

# Expected prompt:
# QEMU 8.x monitor - type 'help' for more information
# (qemu)
```

### Common Monitor Commands

#### VM Control

```bash
# Pause VM execution
(qemu) stop

# Resume VM execution
(qemu) cont

# Graceful shutdown (ACPI)
(qemu) system_powerdown

# Hard reset (like power button)
(qemu) system_reset

# Quit QEMU (stop VM)
(qemu) quit
```

#### System Information

```bash
# Show VM info
(qemu) info status
# Expected: VM status: running

# Show memory statistics
(qemu) info mem

# Show CPU registers
(qemu) info registers

# Show block devices
(qemu) info block
# Expected: ide0-hd0: debian-hurd-amd64.qcow2

# Show network devices
(qemu) info network
# Expected: net0 (e1000)

# Show PCI devices
(qemu) info pci
```

#### Snapshot Management

```bash
# List snapshots
(qemu) info snapshots

# Create snapshot
(qemu) savevm snapshot-name

# Load snapshot
(qemu) loadvm snapshot-name

# Delete snapshot
(qemu) delvm snapshot-name
```

#### Performance Monitoring

```bash
# Show CPU usage
(qemu) info cpus

# Show memory usage
(qemu) info balloon

# Show I/O statistics
(qemu) info blockstats
```

### Monitor Configuration

**QEMU Parameters** (in entrypoint.sh):

```bash
-monitor telnet:0.0.0.0:9999,server,nowait
```

**Port Forwarding** (docker-compose.yml):

```yaml
ports:
  - "9999:9999"
```

### Advanced Monitor Features

#### Memory Inspection

```bash
# Dump memory region
(qemu) x/100x 0x100000
# Shows 100 hex bytes starting at address 0x100000

# Physical memory map
(qemu) info mtree
```

#### CPU Debugging

```bash
# Show CPU state
(qemu) info registers

# Show CPU model
(qemu) info cpus
# Expected: CPU #0: pc=0x... (halted) or (running)
```

#### Device Management

```bash
# Change CD-ROM
(qemu) change ide1-cd0 /path/to/new.iso

# Eject CD-ROM
(qemu) eject ide1-cd0
```

### Exiting Monitor

```bash
# Disconnect (VM continues running)
Ctrl-]
telnet> quit

# Or type at monitor prompt:
(qemu) quit
# WARNING: This stops the VM entirely
```

---

## Method 4: QMP (Programmatic Automation)

**Purpose**: JSON-based machine protocol for automated VM control

**Advantages**:
- Machine-readable (JSON)
- Suitable for scripts and automation
- Full QEMU feature access
- Event-driven (supports subscriptions)

**Disadvantages**:
- More complex than HMP
- Requires JSON parsing

### QMP Socket Configuration

**QEMU Parameters** (in entrypoint.sh):

```bash
-qmp unix:/var/run/qemu-monitor.sock,server,nowait
```

**Docker Volume Mount**:

```yaml
volumes:
  - qemu-sockets:/var/run
```

### Connecting to QMP

```bash
# Using socat
socat - UNIX-CONNECT:/var/run/qemu-monitor.sock

# Expected greeting:
# {"QMP": {"version": {...}, "capabilities": [...]}}
```

### QMP Command Format

All commands are JSON objects:

```json
{"execute": "command-name", "arguments": {...}}
```

Response format:

```json
{"return": {...}}
```

Or error:

```json
{"error": {"class": "...", "desc": "..."}}
```

### Capabilities Negotiation

**Required first command:**

```json
{"execute": "qmp_capabilities"}
```

**Response:**

```json
{"return": {}}
```

### Common QMP Commands

#### Query VM Status

```json
{"execute": "query-status"}
```

**Response:**

```json
{"return": {"running": true, "singlestep": false, "status": "running"}}
```

#### Query CPU Information

```json
{"execute": "query-cpus-fast"}
```

#### Query Memory

```json
{"execute": "query-memory-size-summary"}
```

#### Pause/Resume VM

```json
{"execute": "stop"}
{"execute": "cont"}
```

#### System Powerdown

```json
{"execute": "system_powerdown"}
```

#### Query Block Devices

```json
{"execute": "query-block"}
```

#### Create Snapshot

```json
{
  "execute": "blockdev-snapshot-internal-sync",
  "arguments": {
    "device": "ide0-hd0",
    "name": "snapshot-name"
  }
}
```

### QMP Automation Script

**Python QMP Client** (qmp-control.py):

```python
#!/usr/bin/env python3
"""
QMP control script for GNU/Hurd QEMU guest
Usage: python3 qmp-control.py <command>
"""

import json
import socket
import sys
import os

def qmp_connect(sock_path):
    """Connect to QMP socket and negotiate capabilities"""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sock_path)
    
    # Read QMP greeting
    greeting = json.loads(s.recv(4096).decode())
    print(f"Connected: {greeting['QMP']['version']}", file=sys.stderr)
    
    # Negotiate capabilities
    s.sendall(b'{"execute":"qmp_capabilities"}\n')
    response = json.loads(s.recv(4096).decode())
    
    if 'return' not in response:
        raise RuntimeError(f"Capability negotiation failed: {response}")
    
    return s

def qmp_command(sock, cmd_dict):
    """Execute QMP command and return response"""
    sock.sendall((json.dumps(cmd_dict) + "\n").encode())
    response = s.recv(65536).decode()
    return json.loads(response)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: qmp-control.py <status|pause|resume|powerdown>")
        sys.exit(1)
    
    command = sys.argv[1]
    sock_path = os.getenv("QMP_SOCKET", "/var/run/qemu-monitor.sock")
    
    s = qmp_connect(sock_path)
    
    if command == "status":
        result = qmp_command(s, {"execute": "query-status"})
        print(json.dumps(result, indent=2))
    
    elif command == "pause":
        result = qmp_command(s, {"execute": "stop"})
        print("VM paused")
    
    elif command == "resume":
        result = qmp_command(s, {"execute": "cont"})
        print("VM resumed")
    
    elif command == "powerdown":
        result = qmp_command(s, {"execute": "system_powerdown"})
        print("Powerdown signal sent")
    
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)
    
    s.close()
```

**Usage:**

```bash
# Query status
python3 qmp-control.py status

# Pause VM
python3 qmp-control.py pause

# Resume VM
python3 qmp-control.py resume

# Graceful shutdown
python3 qmp-control.py powerdown
```

### QMP Events

QMP supports event subscriptions:

```json
{"execute": "query-events"}
```

**Common Events**:
- `POWERDOWN` - Guest initiated shutdown
- `RESET` - Guest reset
- `STOP` - VM paused
- `RESUME` - VM resumed
- `BLOCK_JOB_COMPLETED` - Disk operation finished

---

## Method 5: 9p/VirtIO File Sharing

**Purpose**: Bidirectional file transfer between host and guest

**Use Cases**:
- Transfer scripts to guest
- Extract logs from guest
- Share configuration files
- Persistent storage across rebuilds

### 9p Configuration

**QEMU Parameters** (in entrypoint.sh):

```bash
-virtfs local,path=/share,mount_tag=scripts,security_model=none,id=fsdev0
```

- `path=/share` - Host directory (Docker container path)
- `mount_tag=scripts` - Guest mount identifier
- `security_model=none` - No permission mapping (simple mode)

**Docker Volume Mount** (docker-compose.yml):

```yaml
volumes:
  - ./share:/share:rw
```

### Mounting 9p in Guest

**Manual Mount:**

```bash
# Inside guest
mkdir -p /mnt/host
mount -t 9p -o trans=virtio scripts /mnt/host

# Verify
ls -la /mnt/host
# Should show contents of ./share/ from host
```

**Persistent Mount** (/etc/fstab):

```bash
# Inside guest
cat >> /etc/fstab <<'EOF'
scripts /mnt/host 9p trans=virtio,version=9p2000.L,rw 0 0
EOF

# Test mount
mount /mnt/host

# Verify
df -h | grep /mnt/host
```

**Auto-Mount on Boot** (systemd):

```bash
# Inside guest
cat > /etc/systemd/system/mnt-host.mount <<'EOF'
[Unit]
Description=9p Host Share
After=network.target

[Mount]
What=scripts
Where=/mnt/host
Type=9p
Options=trans=virtio,version=9p2000.L,rw

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mnt-host.mount
systemctl start mnt-host.mount

# Verify
systemctl status mnt-host.mount
```

### Using 9p File Sharing

**Host → Guest (Transfer Files):**

```bash
# On host
cp my-script.sh share/

# Inside guest
ls /mnt/host/
# Expected: my-script.sh

# Run script
bash /mnt/host/my-script.sh
```

**Guest → Host (Extract Files):**

```bash
# Inside guest
cp /var/log/syslog /mnt/host/

# On host
cat share/syslog
```

**Bidirectional Editing:**

```bash
# On host
vim share/config.txt

# Inside guest (changes visible immediately)
cat /mnt/host/config.txt
```

### 9p Performance Considerations

**Limitations**:
- Slower than local filesystem (9p protocol overhead)
- Not suitable for databases or high-IOPS workloads
- Best for configuration files and scripts

**Optimization**:
- Use `cache=loose` for better performance (less safe):
  ```bash
  mount -t 9p -o trans=virtio,cache=loose scripts /mnt/host
  ```
- Avoid frequent small writes
- Batch file operations when possible

### 9p Troubleshooting

**Problem: Mount fails with "No such device"**

```bash
# Check 9p kernel module loaded
lsmod | grep 9p
# Expected: 9pnet_virtio, 9p, 9pnet

# Load module if missing
modprobe 9pnet_virtio
```

**Problem: Permission denied**

```bash
# Check security_model in QEMU command
# Use security_model=none for simplest setup

# Or map to specific user:
# -virtfs local,path=/share,mount_tag=scripts,security_model=mapped-file,id=fsdev0
```

**Problem: Changes not visible**

```bash
# Remount to refresh
umount /mnt/host
mount -t 9p -o trans=virtio scripts /mnt/host
```

---

## Access Method Decision Matrix

### Use SSH When:
- ✅ Guest is fully booted
- ✅ Need full-featured shell
- ✅ Need copy/paste support
- ✅ Need secure authentication
- ✅ Normal development workflow

### Use Serial Console When:
- ✅ Debugging boot process
- ✅ SSH is not responding
- ✅ Network configuration issues
- ✅ Emergency access needed
- ✅ Want to see kernel messages

### Use QEMU Monitor (HMP) When:
- ✅ Need to pause/resume VM
- ✅ Want to inspect hardware state
- ✅ Need to manage snapshots interactively
- ✅ Debugging VM-level issues
- ✅ Want human-readable output

### Use QMP When:
- ✅ Automating VM operations
- ✅ Writing scripts or tools
- ✅ Need programmatic control
- ✅ Building CI/CD pipelines
- ✅ Want structured (JSON) output

### Use 9p File Sharing When:
- ✅ Transferring files to/from guest
- ✅ Sharing scripts or configs
- ✅ Extracting logs or data
- ✅ Need persistent file access
- ✅ Want bidirectional sync

---

## Multi-Channel Workflow Examples

### Example 1: Boot Debugging

```bash
# Terminal 1: Serial console (watch boot)
telnet localhost 5555

# Terminal 2: QEMU Monitor (control VM)
telnet localhost 9999
(qemu) info status

# Terminal 3: Docker logs
docker-compose logs -f
```

### Example 2: Development Setup

```bash
# Terminal 1: SSH session (primary work)
ssh -p 2222 root@localhost

# Terminal 2: File sharing (transfer scripts)
# On host:
cp build-script.sh share/
# In SSH session:
bash /mnt/host/build-script.sh

# Terminal 3: Monitor performance
telnet localhost 9999
(qemu) info blockstats
```

### Example 3: CI/CD Automation

```bash
# Script: ci-test.sh
#!/bin/bash

# Start VM via docker-compose
docker-compose up -d

# Wait for boot via QMP
python3 qmp-control.py status

# Transfer test files via 9p
cp tests/* share/

# Run tests via SSH
ssh -p 2222 root@localhost 'bash /mnt/host/run-tests.sh'

# Extract results via 9p
cp share/test-results.xml ./

# Snapshot state via QMP
python3 qmp-control.py snapshot test-passed

# Shutdown via QMP
python3 qmp-control.py powerdown
```

---

## Troubleshooting Access Issues

### SSH Connection Refused

**Diagnosis:**

```bash
# Check Docker container running
docker-compose ps
# Expected: hurd-x86_64-qemu Up

# Check port forwarding
docker-compose port hurd-x86_64-qemu 2222
# Expected: 0.0.0.0:2222

# Check guest SSH service (via serial console)
telnet localhost 5555
systemctl status ssh
# Expected: active (running)
```

**Fix:**

```bash
# Inside guest (via serial console)
apt-get update
apt-get install -y openssh-server
systemctl enable ssh
systemctl start ssh
```

### Serial Console Not Responding

**Diagnosis:**

```bash
# Check port listening
nc -zv localhost 5555
# Expected: Connection succeeded

# Check QEMU process
docker-compose exec hurd-x86_64-qemu ps aux | grep qemu
# Expected: /usr/bin/qemu-system-x86_64 ... -serial telnet:0.0.0.0:5555
```

**Fix:**

```bash
# Restart container
docker-compose restart

# Reconnect
telnet localhost 5555
```

### QEMU Monitor Connection Refused

**Diagnosis:**

```bash
# Check port listening
nc -zv localhost 9999
# Expected: Connection succeeded

# Check entrypoint.sh has monitor config
docker-compose exec hurd-x86_64-qemu cat /entrypoint.sh | grep monitor
# Expected: -monitor telnet:0.0.0.0:9999,server,nowait
```

**Fix:**

```bash
# Verify docker-compose.yml port mapping
grep 9999 docker-compose.yml
# Expected: - "9999:9999"

# Restart if changed
docker-compose restart
```

### 9p Mount Fails

**Diagnosis:**

```bash
# Check QEMU virtfs parameter
docker-compose exec hurd-x86_64-qemu ps aux | grep virtfs
# Expected: -virtfs local,path=/share,mount_tag=scripts

# Check host share directory exists
ls -la share/
# Expected: directory listing

# Check guest kernel module
lsmod | grep 9p
# Expected: 9pnet_virtio loaded
```

**Fix:**

```bash
# Load kernel module
modprobe 9pnet_virtio

# Retry mount
mount -t 9p -o trans=virtio scripts /mnt/host
```

### QMP Socket Not Found

**Diagnosis:**

```bash
# Check QEMU process has QMP socket
docker-compose exec hurd-x86_64-qemu ps aux | grep qmp
# Expected: -qmp unix:/var/run/qemu-monitor.sock

# Check socket exists
docker-compose exec hurd-x86_64-qemu ls -la /var/run/
# Expected: qemu-monitor.sock
```

**Fix:**

```bash
# Verify entrypoint.sh QMP configuration
# Add if missing:
# -qmp unix:/var/run/qemu-monitor.sock,server,nowait

# Restart container
docker-compose restart
```

---

## Security Considerations

### SSH Security

**Recommended Configuration**:
- ✅ Key-based authentication only
- ✅ Disable password authentication
- ✅ Disable root login with password
- ✅ Use strong key types (ED25519, RSA 4096)
- ✅ Enable StrictHostKeyChecking

**Avoid**:
- ❌ Password-only authentication in production
- ❌ Weak passwords
- ❌ Shared keys across multiple systems
- ❌ Unprotected private keys

### Monitor Access

**Security**:
- Monitor interface has **full VM control**
- Can pause, reset, snapshot, inspect memory
- Should be firewalled in production

**Recommendations**:
- Bind to 127.0.0.1 only in production
- Use firewall rules to restrict access
- Consider authentication proxy for HMP/QMP
- Audit monitor commands in logs

### 9p File Sharing

**Security Model**:
- `security_model=none` - No permission mapping (default)
- `security_model=passthrough` - Direct UID/GID mapping
- `security_model=mapped-file` - Separate permission files

**Recommendations**:
- Use `mapped-file` for multi-user environments
- Restrict host directory permissions
- Avoid sharing sensitive files
- Consider read-only mounts for configs

---

## Performance Optimization

### SSH Performance

**Compression** (for slow networks):

```bash
# Enable compression
ssh -C -p 2222 root@localhost

# Or in ~/.ssh/config:
Host gnu-hurd
    Compression yes
    CompressionLevel 6
```

**Multiplexing** (reuse connections):

```bash
# In ~/.ssh/config:
Host gnu-hurd
    ControlMaster auto
    ControlPath ~/.ssh/controlmasters/%r@%h:%p
    ControlPersist 10m

# Create directory
mkdir -p ~/.ssh/controlmasters
```

### Serial Console Performance

**Limitations**:
- Text-only, no graphics
- Limited scrollback
- No copy/paste in basic telnet

**Improvements**:
- Use socat with raw mode for better performance
- Use screen/tmux inside guest for scrollback
- Use SSH for copy/paste needs

### 9p Performance

**Optimization**:

```bash
# Use cache=loose for better performance
mount -t 9p -o trans=virtio,cache=loose scripts /mnt/host

# Use version 9p2000.L for better POSIX compliance
mount -t 9p -o trans=virtio,version=9p2000.L scripts /mnt/host

# Increase msize (message size) for better throughput
mount -t 9p -o trans=virtio,msize=524288 scripts /mnt/host
```

---

## Reference

### Port Summary

| Port | Service | Protocol | Purpose |
|------|---------|----------|---------|
| 2222 | SSH | TCP | Primary shell access |
| 5555 | Serial Console | TCP (telnet) | Boot debugging |
| 8080 | HTTP | TCP | Guest web services |
| 9999 | QEMU Monitor | TCP (telnet) | VM control (HMP) |
| N/A | QMP | Unix socket | VM automation (JSON) |

### File Paths

**Host:**
- SSH config: `~/.ssh/config`
- Shared directory: `./share/`
- Docker Compose: `./docker-compose.yml`

**Container:**
- Entrypoint: `/entrypoint.sh`
- Shared directory: `/share/`
- QMP socket: `/var/run/qemu-monitor.sock`

**Guest:**
- SSH config: `/etc/ssh/sshd_config`
- Authorized keys: `/root/.ssh/authorized_keys`
- 9p mount: `/mnt/host/`
- fstab: `/etc/fstab`

### Common Commands Reference

```bash
# SSH
ssh -p 2222 root@localhost
ssh-keygen -t ed25519 -f ~/.ssh/hurd_dev
ssh-copy-id -p 2222 root@localhost

# Serial Console
telnet localhost 5555
nc localhost 5555

# QEMU Monitor
telnet localhost 9999
# Commands: stop, cont, info status, savevm, loadvm

# 9p Mount
mount -t 9p -o trans=virtio scripts /mnt/host
umount /mnt/host

# QMP
socat - UNIX-CONNECT:/var/run/qemu-monitor.sock
# Send: {"execute":"qmp_capabilities"}
# Send: {"execute":"query-status"}
```

---

**Status**: Production Ready (x86_64-only)  
**Last Updated**: 2025-11-07  
**Architecture**: Pure x86_64  
**Access Methods**: 5 channels (SSH, Serial, HMP, QMP, 9p)
