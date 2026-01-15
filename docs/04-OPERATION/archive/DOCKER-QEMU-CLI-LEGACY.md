# Docker and QEMU CLI Interaction Guide

**Last Updated**: 2025-11-16
**Purpose**: Comprehensive guide to CLI interactions with Hurd Docker/QEMU environment
**Audience**: Developers, system administrators, automation engineers
**Tools**: Docker CLI, QEMU Monitor, socat, netcat, telnet, VNC

---

## Table of Contents

1. [Overview](#overview)
2. [Docker CLI Interactions](#docker-cli-interactions)
3. [QEMU Monitor Access](#qemu-monitor-access)
4. [Serial Console Access](#serial-console-access)
5. [VNC Access](#vnc-access)
6. [MCP (Model Context Protocol) Tools](#mcp-model-context-protocol-tools)
7. [Automation and Scripting](#automation-and-scripting)
8. [Troubleshooting](#troubleshooting)
9. [References](#references)

---

## Overview

The GNU/Hurd Docker environment provides multiple CLI interfaces for interaction:

| Interface | Purpose | Access Method | Port |
|-----------|---------|---------------|------|
| **SSH** | Primary access to Hurd | `ssh -p 2222 root@localhost` | 2222 |
| **Serial Console** | Emergency/debugging access | `telnet localhost 5555` | 5555 |
| **QEMU Monitor** | VM control and debugging | `telnet localhost 9999` | 9999 |
| **VNC** | Graphical console | VNC client to `localhost:5900` | 5900 |
| **Docker Exec** | Container shell access | `docker exec -it hurd-x86_64-qemu bash` | N/A |

---

## Docker CLI Interactions

### Basic Container Management

```bash
# Start the Hurd environment
docker compose up -d

# Stop gracefully
ssh -p 2222 root@localhost "shutdown -h now"
docker compose down

# Force stop (NOT recommended - may corrupt filesystem)
docker compose down --timeout 60

# View logs
docker compose logs -f
docker compose logs --tail=100 hurd-x86_64

# Check status
docker compose ps
docker ps -a | grep hurd
```

### Container Inspection

```bash
# Inspect container configuration
docker inspect hurd-x86_64-qemu | jq .

# View resource usage
docker stats hurd-x86_64-qemu

# Check network
docker network inspect gnu-hurd_hurd-net

# View volumes
docker volume ls | grep hurd
docker volume inspect gnu-hurd_hurd-disk
```

### Execute Commands in Container

```bash
# Open shell in container (NOT Hurd, the container hosting QEMU)
docker exec -it hurd-x86_64-qemu bash

# Run one-off commands
docker exec hurd-x86_64-qemu ps aux | grep qemu
docker exec hurd-x86_64-qemu cat /var/log/qemu/qemu.log

# Check QEMU process
docker exec hurd-x86_64-qemu pgrep -a qemu-system-x86_64
```

### File Operations

```bash
# Copy files from host to container
docker cp ./myfile.txt hurd-x86_64-qemu:/tmp/

# Copy from container to host
docker cp hurd-x86_64-qemu:/var/log/qemu/qemu.log ./

# Copy to Hurd VM (via SSH)
scp -P 2222 ./myfile.txt root@localhost:/tmp/

# Copy from Hurd VM
scp -P 2222 root@localhost:/var/log/messages ./
```

---

## QEMU Monitor Access

The QEMU monitor provides powerful control over the VM.

### Access via Telnet

```bash
# Connect to QEMU monitor
telnet localhost 9999

# Or using netcat
nc localhost 9999
```

### Common Monitor Commands

```
# QEMU Monitor Commands

# System Control
system_powerdown          # Send ACPI powerdown event
system_reset              # Hard reset VM
quit                      # Terminate QEMU (emergency only!)

# Info Commands
info status               # VM running state
info registers            # CPU registers
info cpus                 # CPU information
info mem                  # Memory mapping
info block                # Block devices (disks)
info network              # Network devices
info snapshots            # List snapshots

# Snapshot Management
savevm <name>             # Create snapshot
loadvm <name>             # Restore snapshot
delvm <name>              # Delete snapshot

# Device Control
device_add                # Hot-add device
device_del                # Hot-remove device
balloon <size>            # Change RAM allocation

# Debug
log <category>            # Enable logging
trace-event <event>       # Enable tracing
gdbserver <port>          # Start GDB server
```

### Example Monitor Sessions

#### Create VM Snapshot

```bash
# Connect to monitor
telnet localhost 9999

# Commands in monitor:
(qemu) info status
VM status: running
(qemu) savevm backup-20251116
(qemu) info snapshots
List of snapshots present on all disks:
ID        TAG                  VM SIZE                DATE       VM CLOCK
--        backup-20251116      256M                   2025-11-16 12:34:56   00:05:23.456
(qemu) quit
```

#### Inspect VM State

```bash
telnet localhost 9999

(qemu) info cpus
* CPU #0: pc=0x00007f1234567890 thread_id=12345
  CPU #1: pc=0x00007f1234567891 thread_id=12346 (halted)

(qemu) info mem
0000000000000000-0000000040000000 0000000040000000 -rw

(qemu) info block
hurd-disk (#block142): /opt/hurd-image/debian-hurd-amd64.qcow2 (qcow2)
    Attached to:      ide0-hd0
    Cache mode:       writeback
```

### Scripted Monitor Access

```bash
#!/bin/bash
# monitor-cmd.sh - Send commands to QEMU monitor

MONITOR_PORT=9999
COMMAND="$1"

if [ -z "$COMMAND" ]; then
    echo "Usage: $0 <command>"
    exit 1
fi

# Send command and get response
echo "$COMMAND" | nc localhost $MONITOR_PORT
```

Usage:

```bash
./monitor-cmd.sh "info status"
./monitor-cmd.sh "savevm test-snapshot"
```

### Using socat for Monitor Access

```bash
# Better interactive monitor (with readline support)
socat -,echo=0,icanon=0 TCP:localhost:9999

# Or if using UNIX socket (configure in docker-compose.yml)
socat -,echo=0,icanon=0 UNIX-CONNECT:/var/run/qemu-monitor.sock
```

---

## Serial Console Access

The serial console provides direct access to Hurd's console output and Mach kernel messages.

### Access Methods

```bash
# Method 1: Telnet
telnet localhost 5555

# Method 2: Netcat
nc localhost 5555

# Method 3: socat (better terminal handling)
socat -,raw,echo=0,escape=0x1d TCP:localhost:5555
```

### Serial Console Commands

```bash
# Boot messages
# Watch boot process
telnet localhost 5555
# (observe Mach kernel boot messages)

# Emergency login
# If SSH fails, use serial console
telnet localhost 5555
# Login: root
# Password: root

# Kernel debugging
# View kernel messages
dmesg
cat /var/log/dmesg

# Interact with GRUB (on boot)
# Connect before VM starts to interact with GRUB menu
```

### Serial Console Tips

```bash
# Escape character: Ctrl+]
# To close telnet: Ctrl+] then type "quit"

# Save console output to file
telnet localhost 5555 | tee hurd-console.log

# Watch boot in real-time
watch -n 1 "docker compose logs hurd-x86_64 | tail -20"
```

---

## VNC Access

VNC provides graphical console access to Hurd's display.

### Enable VNC in docker-compose.yml

```yaml
services:
  hurd-x86_64:
    environment:
      ENABLE_VNC: 1  # Enable VNC on port 5900
```

### VNC Client Connection

```bash
# Method 1: TigerVNC
vncviewer localhost:5900

# Method 2: RealVNC
# Connect to: localhost:5900

# Method 3: Web-based (noVNC)
# Setup noVNC container (see below)

# Method 4: macOS Screen Sharing
open vnc://localhost:5900
```

### noVNC Web Interface

Add noVNC service to docker-compose.yml:

```yaml
services:
  # ... existing hurd-x86_64 service ...

  novnc:
    image: theasp/novnc:latest
    environment:
      - DISPLAY_WIDTH=1024
      - DISPLAY_HEIGHT=768
      - RUN_XTERM=no
    ports:
      - "6080:8080"  # Web interface
    depends_on:
      - hurd-x86_64
    networks:
      - hurd-net
    command: --vnc hurd-x86_64:5900
```

Access via browser:

```
http://localhost:6080/vnc.html?autoconnect=true
```

### VNC Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Send Ctrl+Alt+Delete | Via VNC menu |
| Fullscreen | F11 (TigerVNC) |
| Grab keyboard | Ctrl+Alt (click VNC window) |
| Release keyboard | Ctrl+Alt |

---

## MCP (Model Context Protocol) Tools

Docker announced MCP Catalog and Toolkit in 2025 for AI agent integration.

### Docker MCP Overview

The Model Context Protocol (MCP) standardizes how AI agents interact with tools and data sources. Docker provides:

- **MCP Catalog**: 60+ pre-built MCP servers
- **MCP Toolkit**: Easy deployment and management
- **Docker Desktop Integration**: One-click MCP server deployment

### Installing Docker MCP Toolkit

```bash
# Install Docker MCP CLI (if available)
docker mcp install

# List available MCP servers
docker mcp catalog list

# Install an MCP server
docker mcp catalog install <server-name>

# Example: Install filesystem MCP server
docker mcp catalog install filesystem
```

### Available MCP Servers

Relevant to Hurd development:

- **Filesystem**: File operations
- **Database**: SQLite, PostgreSQL access
- **Git**: Repository operations
- **SSH**: Remote server access
- **Docker**: Container management
- **Terminal**: Command execution

### Using MCP with Hurd Environment

```yaml
# docker-compose.yml - Add MCP server
services:
  hurd-x86_64:
    # ... existing configuration ...

  mcp-filesystem:
    image: docker.io/mcp/filesystem:latest
    volumes:
      - ./share:/workspace
    environment:
      - MCP_ALLOWED_PATHS=/workspace
    ports:
      - "3000:3000"  # MCP server port
```

### MCP Client Integration

```bash
# Connect Claude Desktop to Hurd environment
# In Claude Desktop settings:
{
  "mcpServers": {
    "hurd-files": {
      "url": "http://localhost:3000",
      "type": "filesystem"
    }
  }
}
```

---

## Automation and Scripting

### Health Check Script

```bash
#!/bin/bash
# health-check.sh

# Check if container is running
if ! docker ps | grep -q hurd-x86_64-qemu; then
    echo "ERROR: Container not running"
    exit 1
fi

# Check if QEMU process is alive
if ! docker exec hurd-x86_64-qemu pgrep -x qemu-system-x86_64 > /dev/null; then
    echo "ERROR: QEMU not running"
    exit 1
fi

# Check SSH accessibility
if ! timeout 5 ssh -p 2222 -o StrictHostKeyChecking=no root@localhost "echo test" > /dev/null 2>&1; then
    echo "WARN: SSH not accessible yet"
    exit 2
fi

echo "OK: Hurd environment healthy"
exit 0
```

### Automated Snapshot Script

```bash
#!/bin/bash
# snapshot.sh - Create QEMU snapshot via monitor

SNAPSHOT_NAME="${1:-auto-$(date +%Y%m%d-%H%M%S)}"

echo "Creating snapshot: $SNAPSHOT_NAME"

# Send savevm command to monitor
echo "savevm $SNAPSHOT_NAME" | nc localhost 9999

# Verify
echo "info snapshots" | nc localhost 9999 | grep "$SNAPSHOT_NAME"

if [ $? -eq 0 ]; then
    echo "Snapshot created successfully"
else
    echo "Snapshot creation failed"
    exit 1
fi
```

### Batch Command Execution

```bash
#!/bin/bash
# batch-exec.sh - Execute multiple commands in Hurd

COMMANDS=(
    "apt update"
    "apt install -y vim"
    "uname -a"
    "df -h"
)

for cmd in "${COMMANDS[@]}"; do
    echo "Executing: $cmd"
    ssh -p 2222 root@localhost "$cmd"
    if [ $? -ne 0 ]; then
        echo "ERROR: Command failed: $cmd"
        exit 1
    fi
done

echo "All commands executed successfully"
```

### Wait for Boot Script

```bash
#!/bin/bash
# wait-for-boot.sh - Wait for Hurd to finish booting

MAX_WAIT=300  # 5 minutes
INTERVAL=5

echo "Waiting for Hurd to boot..."

for ((i=0; i<$MAX_WAIT; i+=$INTERVAL)); do
    if ssh -p 2222 -o StrictHostKeyChecking=no -o ConnectTimeout=2 root@localhost "echo ready" > /dev/null 2>&1; then
        echo "Hurd is ready (took ${i}s)"
        exit 0
    fi
    sleep $INTERVAL
done

echo "ERROR: Hurd did not boot within ${MAX_WAIT}s"
exit 1
```

---

## Troubleshooting

### Cannot Connect to Monitor

```bash
# Check if monitor port is exposed
docker compose port hurd-x86_64 9999

# Check if port is accessible
nc -zv localhost 9999

# View QEMU command line
docker exec hurd-x86_64-qemu ps aux | grep qemu

# Check for monitor socket in container
docker exec hurd-x86_64-qemu ls -la /var/run/ | grep qemu
```

### Serial Console No Output

```bash
# Check if serial port is configured
docker exec hurd-x86_64-qemu ps aux | grep qemu | grep serial

# Verify port mapping
docker compose port hurd-x86_64 5555

# Check container logs
docker compose logs hurd-x86_64 | grep -i serial
```

### VNC Connection Refused

```bash
# Check if VNC is enabled
docker exec hurd-x86_64-qemu printenv ENABLE_VNC

# Check QEMU VNC settings
docker exec hurd-x86_64-qemu ps aux | grep qemu | grep vnc

# Test VNC port
nc -zv localhost 5900

# View VNC logs
docker compose logs hurd-x86_64 | grep -i vnc
```

### SSH Connection Hangs

```bash
# Check if SSH is running in Hurd
telnet localhost 5555
# Login and run: ps aux | grep sshd

# Check network connectivity
docker exec hurd-x86_64-qemu ping -c 3 10.0.2.15  # Default QEMU guest IP

# Verify port forwarding
docker compose port hurd-x86_64 2222

# Test with verbose SSH
ssh -vvv -p 2222 root@localhost
```

---

## Advanced Techniques

### QEMU QMP (QEMU Machine Protocol)

QMP provides JSON-based monitor interface for programmatic control:

```bash
# Enable QMP in entrypoint.sh
-qmp tcp:localhost:4444,server,nowait

# Query QMP
echo '{ "execute": "qmp_capabilities" }' | nc localhost 4444
echo '{ "execute": "query-status" }' | nc localhost 4444
echo '{ "execute": "query-cpus-fast" }' | nc localhost 4444
```

### Remote Access via SSH Tunnel

```bash
# Forward QEMU monitor through SSH
ssh -L 9999:localhost:9999 user@remote-host

# Now connect locally
telnet localhost 9999

# Forward VNC
ssh -L 5900:localhost:5900 user@remote-host
vncviewer localhost:5900
```

### Docker SDK for Python

```python
#!/usr/bin/env python3
import docker

client = docker.from_env()
container = client.containers.get('hurd-x86_64-qemu')

# Execute command
result = container.exec_run('ps aux | grep qemu')
print(result.output.decode())

# Get logs
logs = container.logs(tail=100)
print(logs.decode())

# Stats
stats = container.stats(stream=False)
print(f"CPU: {stats['cpu_stats']}")
print(f"Memory: {stats['memory_stats']}")
```

---

## Quick Reference

### Connection Quick Reference

```bash
# SSH to Hurd
ssh -p 2222 root@localhost

# Serial console
telnet localhost 5555

# QEMU monitor
telnet localhost 9999

# VNC (if enabled)
vncviewer localhost:5900

# Container shell
docker exec -it hurd-x86_64-qemu bash

# Copy file to Hurd
scp -P 2222 file.txt root@localhost:/tmp/

# QEMU snapshot
echo "savevm backup" | nc localhost 9999

# Check health
ssh -p 2222 root@localhost "uptime"
```

### Port Reference

| Port | Service | Protocol | Access |
|------|---------|----------|--------|
| 2222 | SSH | TCP | `ssh -p 2222 root@localhost` |
| 5555 | Serial Console | TCP | `telnet localhost 5555` |
| 9999 | QEMU Monitor | TCP | `telnet localhost 9999` |
| 5900 | VNC | TCP | `vncviewer localhost:5900` |
| 8080 | HTTP (guest) | TCP | `curl http://localhost:8080` |

---

## References

### Official Documentation

- **Docker CLI**: https://docs.docker.com/engine/reference/commandline/cli/
- **QEMU Monitor**: https://qemu-project.gitlab.io/qemu/system/monitor.html
- **QEMU QMP**: https://qemu-project.gitlab.io/qemu/interop/qemu-qmp-ref.html
- **Docker MCP**: https://docs.docker.com/ai/mcp-catalog-and-toolkit/

### Tools

- **socat**: http://www.dest-unreach.org/socat/
- **TigerVNC**: https://tigervnc.org/
- **noVNC**: https://novnc.com/

### Related Guides

- [INTERACTIVE-ACCESS.md](INTERACTIVE-ACCESS.md) - SSH and console access
- [SNAPSHOTS.md](SNAPSHOTS.md) - Snapshot management
- [MONITORING.md](MONITORING.md) - Performance monitoring
- [../06-TROUBLESHOOTING/COMMON-ISSUES.md](../06-TROUBLESHOOTING/COMMON-ISSUES.md) - Troubleshooting

---

**Pro Tip**: Use `tmux` or `screen` to multiplex multiple connections (SSH, serial, monitor) in one terminal window!
