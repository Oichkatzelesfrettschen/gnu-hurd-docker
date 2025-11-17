# CLI Orchestration Guide for Debian GNU/Hurd

> **Complete guide to Docker and QEMU CLI orchestration with full debugging**
>
> Demonstrates programmatic control, automation, and debugging of GNU/Hurd instances

## Table of Contents

1. [Overview](#overview)
2. [Docker CLI Orchestration](#docker-cli-orchestration)
3. [QEMU CLI Control](#qemu-cli-control)
4. [MCP Tools Integration](#mcp-tools-integration)
5. [Automation Examples](#automation-examples)
6. [Debugging and Troubleshooting](#debugging-and-troubleshooting)

---

## Overview

This guide demonstrates three levels of CLI orchestration:

1. **Docker CLI**: Container lifecycle management and execution
2. **QEMU CLI**: Virtual machine control via QMP (QEMU Machine Protocol)
3. **MCP Tools**: Model Context Protocol integration for AI-assisted operations

### Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Docker Host                        │
│  ┌───────────────────────────────────────────────┐  │
│  │           Docker Container                    │  │
│  │  ┌─────────────────────────────────────────┐  │  │
│  │  │         QEMU Process                    │  │  │
│  │  │  ┌───────────────────────────────────┐  │  │  │
│  │  │  │   Debian GNU/Hurd                 │  │  │  │
│  │  │  │   (Guest OS)                      │  │  │  │
│  │  │  └───────────────────────────────────┘  │  │  │
│  │  │                                         │  │  │
│  │  │  Access Points:                         │  │  │
│  │  │  - QEMU Monitor (port 9999)            │  │  │
│  │  │  - Serial Console (port 5555)          │  │  │
│  │  │  - VNC Display (port 5900)             │  │  │
│  │  │  - SSH (port 22 → 2222)                │  │  │
│  │  └─────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  Control via:                                       │
│  - docker exec / attach / logs                      │
│  - Direct port access (telnet/ssh/vnc)             │
│  - MCP protocol integration                         │
└─────────────────────────────────────────────────────┘
```

---

## Docker CLI Orchestration

### Using the Orchestration Script

The repository includes `scripts/docker-orchestration.sh` for comprehensive container management:

```bash
# Container Lifecycle
./scripts/docker-orchestration.sh build          # Build image
./scripts/docker-orchestration.sh start          # Start container
./scripts/docker-orchestration.sh stop           # Stop container
./scripts/docker-orchestration.sh restart        # Restart container
./scripts/docker-orchestration.sh remove         # Remove container

# Interaction
./scripts/docker-orchestration.sh exec "command" # Run command
./scripts/docker-orchestration.sh shell          # Interactive shell
./scripts/docker-orchestration.sh logs           # View logs
./scripts/docker-orchestration.sh follow-logs    # Tail logs

# QEMU Access via Docker
./scripts/docker-orchestration.sh qemu-monitor   # QEMU monitor
./scripts/docker-orchestration.sh qemu-serial    # Serial console
./scripts/docker-orchestration.sh qemu-ssh       # SSH to Hurd

# Debugging
./scripts/docker-orchestration.sh stats          # Resource usage
./scripts/docker-orchestration.sh top            # Process list
./scripts/docker-orchestration.sh network        # Network info
./scripts/docker-orchestration.sh ports          # Port mappings
```

### Docker CLI Best Practices

#### 1. Container Execution

**Use `docker exec` for one-off commands** (preferred for automation):

```bash
# Execute single command
docker exec hurd-x86_64 ps aux

# Interactive shell
docker exec -it hurd-x86_64 /bin/bash

# Run as different user
docker exec -u root hurd-x86_64 whoami

# Run with environment variables
docker exec -e DEBUG=1 hurd-x86_64 ./script.sh
```

**Use `docker attach` sparingly** (connects to PID 1):

```bash
# Attach to main process (use Ctrl+P, Ctrl+Q to detach)
docker attach hurd-x86_64

# Attach read-only
docker attach --no-stdin hurd-x86_64
```

#### 2. Log Management

```bash
# View all logs
docker logs hurd-x86_64

# Follow logs (tail -f style)
docker logs -f hurd-x86_64

# Last N lines
docker logs --tail 100 hurd-x86_64

# Since timestamp
docker logs --since 2025-11-17T00:00:00 hurd-x86_64

# Until timestamp
docker logs --until 2025-11-17T23:59:59 hurd-x86_64

# Combine options
docker logs -f --tail 50 --since 10m hurd-x86_64
```

#### 3. Resource Monitoring

```bash
# Real-time stats
docker stats hurd-x86_64

# Process list
docker top hurd-x86_64

# Detailed inspection
docker inspect hurd-x86_64

# Network details
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' hurd-x86_64

# Port mappings
docker port hurd-x86_64
```

#### 4. Advanced Usage

**Parallel Operations:**

```bash
# Start multiple instances
for i in {1..3}; do
    docker run -d --name "hurd-instance-$i" hurd-x86_64
done

# Execute command in all instances
for container in $(docker ps -q --filter "name=hurd-instance"); do
    docker exec "$container" echo "Hello from $(hostname)"
done
```

**Resource Constraints:**

```bash
docker run -d \
    --name hurd-x86_64 \
    --cpus="2.0" \
    --memory="2g" \
    --memory-swap="4g" \
    --pids-limit=500 \
    hurd-x86_64:latest
```

---

## QEMU CLI Control

### Using the QEMU Control Script

The repository includes `scripts/qemu-cli-control.sh` for VM management:

```bash
# VM Status
./scripts/qemu-cli-control.sh status          # VM status
./scripts/qemu-cli-control.sh info            # Detailed info

# Snapshot Management
./scripts/qemu-cli-control.sh snapshot-list   # List snapshots
./scripts/qemu-cli-control.sh snapshot-create NAME
./scripts/qemu-cli-control.sh snapshot-load NAME
./scripts/qemu-cli-control.sh snapshot-delete NAME

# VM Control
./scripts/qemu-cli-control.sh pause           # Pause execution
./scripts/qemu-cli-control.sh resume          # Resume execution
./scripts/qemu-cli-control.sh reset           # Reset VM
./scripts/qemu-cli-control.sh powerdown       # Graceful shutdown
./scripts/qemu-cli-control.sh quit            # Force quit

# Access
./scripts/qemu-cli-control.sh console         # Serial console
./scripts/qemu-cli-control.sh monitor         # QEMU monitor

# Custom Commands
./scripts/qemu-cli-control.sh send "info registers"
```

### Direct QEMU Monitor Access

**Via Telnet:**

```bash
# Connect to QEMU monitor
telnet localhost 9999

# Common commands
(qemu) info status                 # VM status
(qemu) info version                # QEMU version
(qemu) info cpus                   # CPU information
(qemu) info block                  # Block devices
(qemu) info network                # Network devices
(qemu) info snapshots              # List snapshots
(qemu) info registers              # CPU registers
(qemu) info mem                    # Memory mapping
(qemu) info mtree                  # Memory tree

# Snapshot commands
(qemu) savevm snapshot-name        # Create snapshot
(qemu) loadvm snapshot-name        # Load snapshot
(qemu) delvm snapshot-name         # Delete snapshot

# Control commands
(qemu) stop                        # Pause VM
(qemu) cont                        # Resume VM
(qemu) system_reset                # Reset VM
(qemu) system_powerdown            # Shutdown VM
(qemu) quit                        # Quit QEMU
```

**Via Netcat (for automation):**

```bash
# Single command
echo "info status" | nc -q 1 localhost 9999

# Multiple commands
{
    echo "info status"
    echo "info snapshots"
    echo "info block"
} | nc -q 1 localhost 9999

# Save output
echo "info status" | nc -q 1 localhost 9999 > vm-status.txt
```

**Via Socat (bidirectional):**

```bash
# Interactive session
socat - TCP:localhost:9999

# Send commands from file
socat FILE:commands.txt TCP:localhost:9999
```

### Serial Console Access

**Via Telnet:**

```bash
# Connect to serial console
telnet localhost 5555

# View boot messages in real-time
telnet localhost 5555 | tee boot.log

# Send commands (after boot)
telnet localhost 5555
(login) root
(password) root
# uname -a
```

**Via Netcat:**

```bash
# Read-only monitoring
nc localhost 5555

# Send commands
echo -e "root\nroot\nuname -a\n" | nc localhost 5555
```

### Launching with Full Debugging

Use the included launch script:

```bash
./scripts/launch-hurd-debug.sh
```

This script launches QEMU with:
- ✅ QEMU Monitor on port 9999
- ✅ Serial Console on port 5555
- ✅ VNC on port 5900
- ✅ SSH forwarding to port 2222
- ✅ Debug logging to `/tmp/qemu-hurd-debug.log`
- ✅ Automatic snapshot creation

**Configuration via environment variables:**

```bash
# Custom configuration
MEMORY=4096 \
CPUS=4 \
MONITOR_PORT=19999 \
SERIAL_PORT=15555 \
./scripts/launch-hurd-debug.sh
```

### QMP (QEMU Machine Protocol)

For programmatic JSON-based control:

```bash
# Start QEMU with QMP socket
qemu-system-x86_64 \
    ... \
    -qmp unix:/tmp/qmp-socket,server,nowait

# Send QMP commands
echo '{ "execute": "qmp_capabilities" }' | socat - UNIX-CONNECT:/tmp/qmp-socket
echo '{ "execute": "query-status" }' | socat - UNIX-CONNECT:/tmp/qmp-socket
echo '{ "execute": "query-cpus-fast" }' | socat - UNIX-CONNECT:/tmp/qmp-socket
```

---

## MCP Tools Integration

### Docker MCP Overview

**Docker MCP (Model Context Protocol)** is Docker's 2025 initiative for AI agent integration.

Key components:
1. **MCP Gateway**: Orchestrates MCP servers as Docker containers
2. **MCP Catalog**: Docker Hub registry of containerized MCP servers
3. **docker mcp CLI**: Manage servers and tools from terminal

### MCP Gateway Setup

**Installation:**

```bash
# Docker Desktop includes MCP Toolkit (as of 2025)
# Enable in: Settings → Features → MCP Toolkit

# Verify installation
docker mcp --version

# List available tools
docker mcp list
```

**Architecture:**

```
┌─────────────────────────────────────────────────┐
│              MCP Client (AI App)                │
└──────────────────┬──────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│            MCP Gateway (Proxy)                  │
│  - Routes requests to MCP servers               │
│  - Manages credentials & access control         │
│  - Logs all tool activity                       │
└──────────────────┬──────────────────────────────┘
                   │
        ┌──────────┼──────────┐
        │          │          │
┌───────▼────┐ ┌──▼─────┐ ┌──▼─────┐
│ MCP Server │ │ MCP    │ │ MCP    │
│ (Docker    │ │ Server │ │ Server │
│ Container) │ │ ...    │ │ ...    │
└────────────┘ └────────┘ └────────┘
```

### Using MCP with GNU/Hurd

**Example: Filesystem MCP Server**

```bash
# Start filesystem MCP server
docker mcp run --name fs-server \
    -v /home/user/gnu-hurd-docker:/workspace \
    mcp/filesystem

# Use in AI application
# The AI can now read/write files in the workspace
```

**Example: Custom Hurd MCP Server**

Create `mcp-server/Dockerfile`:

```dockerfile
FROM node:20-slim
WORKDIR /app
COPY package.json .
RUN npm install @modelcontextprotocol/sdk
COPY server.js .
CMD ["node", "server.js"]
```

Create `mcp-server/server.js`:

```javascript
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';

const server = new Server({
  name: 'hurd-control',
  version: '1.0.0',
}, {
  capabilities: {
    tools: {},
  },
});

// Define tools
server.setRequestHandler('tools/list', async () => ({
  tools: [
    {
      name: 'qemu_status',
      description: 'Get QEMU VM status',
      inputSchema: {
        type: 'object',
        properties: {},
      },
    },
    {
      name: 'qemu_snapshot',
      description: 'Create QEMU snapshot',
      inputSchema: {
        type: 'object',
        properties: {
          name: { type: 'string', description: 'Snapshot name' },
        },
        required: ['name'],
      },
    },
  ],
}));

// Implement tools
server.setRequestHandler('tools/call', async (request) => {
  if (request.params.name === 'qemu_status') {
    const { exec } = await import('child_process');
    return new Promise((resolve) => {
      exec('echo "info status" | nc -q 1 localhost 9999', (error, stdout) => {
        resolve({
          content: [{ type: 'text', text: stdout || error?.message }],
        });
      });
    });
  }

  if (request.params.name === 'qemu_snapshot') {
    const { exec } = await import('child_process');
    const name = request.params.arguments.name;
    return new Promise((resolve) => {
      exec(`echo "savevm ${name}" | nc -q 1 localhost 9999`, (error, stdout) => {
        resolve({
          content: [{ type: 'text', text: `Snapshot '${name}' created` }],
        });
      });
    });
  }
});

// Start server
const transport = new StdioServerTransport();
await server.connect(transport);
```

**Build and run:**

```bash
cd mcp-server
docker build -t mcp-hurd-control .
docker mcp run --name hurd-control mcp-hurd-control
```

### MCP Best Practices

1. **Isolation**: Run each MCP server in its own container
2. **Credentials**: Use MCP Gateway for credential management
3. **Logging**: Enable call-tracing for debugging
4. **Access Control**: Restrict tools to necessary operations only
5. **Versioning**: Tag MCP server images with semantic versions

---

## Automation Examples

### 1. Automated Testing Pipeline

```bash
#!/bin/bash
# Automated Hurd test pipeline

set -euo pipefail

echo "1. Starting Hurd instance..."
./scripts/launch-hurd-debug.sh &
sleep 30  # Wait for boot

echo "2. Creating pre-test snapshot..."
./scripts/qemu-cli-control.sh snapshot-create "pre-test-$(date +%s)"

echo "3. Running tests..."
ssh -p 2222 root@localhost << 'EOF'
    # Install test dependencies
    apt-get update
    apt-get install -y build-essential

    # Run tests
    cd /tests
    make all
    make test
EOF

if [ $? -eq 0 ]; then
    echo "4. Tests passed! Creating success snapshot..."
    ./scripts/qemu-cli-control.sh snapshot-create "test-success-$(date +%s)"
else
    echo "4. Tests failed! Rolling back..."
    ./scripts/qemu-cli-control.sh snapshot-load "pre-test"
    exit 1
fi

echo "5. Cleaning up..."
./scripts/qemu-cli-control.sh powerdown
```

### 2. Continuous Integration

```yaml
# .github/workflows/hurd-ci.yml
name: Hurd CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build Docker image
        run: docker build -t hurd-x86_64 .

      - name: Start Hurd container
        run: |
          docker run -d --name hurd \
            --privileged \
            -p 2222:22 \
            -p 9999:9999 \
            hurd-x86_64

      - name: Wait for boot
        run: |
          timeout 120 bash -c 'until echo "info status" | nc -q 1 localhost 9999 | grep running; do sleep 5; done'

      - name: Run tests
        run: |
          docker exec hurd bash -c "cd /tests && make test"

      - name: Save logs
        if: always()
        run: |
          docker logs hurd > hurd.log
          docker exec hurd cat /tmp/qemu-hurd-debug.log > qemu.log

      - name: Upload artifacts
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: logs
          path: |
            hurd.log
            qemu.log
```

### 3. Snapshot-Based Workflow

```bash
#!/bin/bash
# Development workflow with snapshots

# Function to create timestamped snapshot
snapshot() {
    local name="dev-$(date +%Y%m%d-%H%M%S)"
    ./scripts/qemu-cli-control.sh snapshot-create "$name"
    echo "$name"
}

# Function to list recent snapshots
recent_snapshots() {
    echo "info snapshots" | nc -q 1 localhost 9999 | tail -n +3
}

# Function to rollback
rollback() {
    local name="${1:-}"
    if [ -z "$name" ]; then
        echo "Recent snapshots:"
        recent_snapshots
        read -p "Enter snapshot name: " name
    fi
    ./scripts/qemu-cli-control.sh snapshot-load "$name"
}

# Interactive menu
while true; do
    echo ""
    echo "1) Create snapshot"
    echo "2) List snapshots"
    echo "3) Rollback"
    echo "4) Exit"
    read -p "Choice: " choice

    case $choice in
        1) snapshot ;;
        2) recent_snapshots ;;
        3) rollback ;;
        4) exit 0 ;;
    esac
done
```

### 4. Health Monitoring

```bash
#!/bin/bash
# Health monitoring script

MONITOR_PORT=9999
SERIAL_PORT=5555
LOG_FILE="/tmp/hurd-health.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

check_qemu() {
    local status=$(echo "info status" | nc -w 1 localhost $MONITOR_PORT 2>/dev/null | grep "VM status")
    if echo "$status" | grep -q "running"; then
        log "✓ QEMU is running"
        return 0
    else
        log "✗ QEMU is not running or not responding"
        return 1
    fi
}

check_ssh() {
    if nc -z localhost 2222 2>/dev/null; then
        log "✓ SSH port is accessible"
        return 0
    else
        log "✗ SSH port is not accessible"
        return 1
    fi
}

check_memory() {
    local mem_info=$(echo "info balloon" | nc -w 1 localhost $MONITOR_PORT 2>/dev/null)
    log "Memory: $mem_info"
}

# Main monitoring loop
while true; do
    log "=== Health Check ==="
    check_qemu && check_ssh && check_memory
    sleep 60
done
```

---

## Debugging and Troubleshooting

### 1. QEMU Debug Log Analysis

```bash
# Real-time log monitoring
tail -f /tmp/qemu-hurd-debug.log

# Search for errors
grep -i "error\|fail\|warn" /tmp/qemu-hurd-debug.log

# Count specific events
grep -c "IRQ" /tmp/qemu-hurd-debug.log

# Analyze boot sequence
grep "Loading\|Starting" /tmp/qemu-hurd-debug.log
```

### 2. Docker Container Debugging

```bash
# Inspect container state
docker inspect hurd-x86_64 | jq .

# Check resource usage
docker stats --no-stream hurd-x86_64

# View recent logs
docker logs --tail 100 hurd-x86_64

# Check exit code (if stopped)
docker inspect -f '{{.State.ExitCode}}' hurd-x86_64

# Check restart count
docker inspect -f '{{.RestartCount}}' hurd-x86_64
```

### 3. Network Debugging

```bash
# Check port bindings
docker port hurd-x86_64

# Test port connectivity
nc -zv localhost 9999   # QEMU monitor
nc -zv localhost 5555   # Serial console
nc -zv localhost 2222   # SSH
nc -zv localhost 5900   # VNC

# Capture traffic
tcpdump -i lo port 2222 -w ssh.pcap
```

### 4. Common Issues

**Issue: QEMU monitor not responding**

```bash
# Check if QEMU is running
ps aux | grep qemu

# Check port binding
netstat -tlnp | grep 9999

# Restart with verbose logging
QEMU_EXTRA_ARGS="-d all" ./scripts/launch-hurd-debug.sh
```

**Issue: SSH connection refused**

```bash
# Check if Hurd booted successfully
telnet localhost 5555

# Verify SSH server is running (via serial console)
# Login and run:
systemctl status ssh

# Check port forwarding
echo "info network" | nc -q 1 localhost 9999
```

**Issue: Snapshot creation fails**

```bash
# Check disk space
df -h images/

# Verify image format
qemu-img info images/debian-hurd-amd64.qcow2

# Check QEMU version
qemu-system-x86_64 --version
```

**Issue: High CPU usage**

```bash
# Check VM status
echo "info status" | nc -q 1 localhost 9999

# Pause VM temporarily
./scripts/qemu-cli-control.sh pause

# Resume with throttling
echo "cpu-throttle-increment 20" | nc -q 1 localhost 9999
./scripts/qemu-cli-control.sh resume
```

---

## Advanced Topics

### 1. Automated Snapshot Management

```bash
#!/bin/bash
# Automatic snapshot rotation

MAX_SNAPSHOTS=10

create_snapshot() {
    local name="auto-$(date +%Y%m%d-%H%M%S)"
    echo "savevm $name" | nc -q 1 localhost 9999
    echo "Created snapshot: $name"
}

cleanup_old_snapshots() {
    local snapshots=$(echo "info snapshots" | nc -q 1 localhost 9999 | tail -n +3 | grep "auto-" | awk '{print $2}')
    local count=$(echo "$snapshots" | wc -l)

    if [ "$count" -gt "$MAX_SNAPSHOTS" ]; then
        local to_delete=$((count - MAX_SNAPSHOTS))
        echo "$snapshots" | head -n "$to_delete" | while read snap; do
            echo "delvm $snap" | nc -q 1 localhost 9999
            echo "Deleted old snapshot: $snap"
        done
    fi
}

# Create snapshot and cleanup
create_snapshot
cleanup_old_snapshots
```

### 2. Performance Profiling

```bash
#!/bin/bash
# Profile QEMU performance

# Start profiling
echo "info profile on" | nc -q 1 localhost 9999

# Run workload
ssh -p 2222 root@localhost 'make -j4'

# Stop profiling
echo "info profile off" | nc -q 1 localhost 9999

# Analyze results
docker exec hurd-x86_64 cat /tmp/qemu-profile.log
```

### 3. Multi-Instance Orchestration

```bash
#!/bin/bash
# Manage multiple Hurd instances

INSTANCES=("dev" "test" "staging")
BASE_PORT=10000

for i in "${!INSTANCES[@]}"; do
    name="${INSTANCES[$i]}"
    monitor_port=$((BASE_PORT + i * 10))
    serial_port=$((BASE_PORT + i * 10 + 1))
    ssh_port=$((BASE_PORT + i * 10 + 2))

    echo "Starting instance: $name"
    docker run -d \
        --name "hurd-$name" \
        -p "$ssh_port:22" \
        -p "$monitor_port:9999" \
        -p "$serial_port:5555" \
        hurd-x86_64

    echo "  Monitor: telnet localhost $monitor_port"
    echo "  Serial:  telnet localhost $serial_port"
    echo "  SSH:     ssh -p $ssh_port root@localhost"
done
```

---

## Summary

This guide demonstrated three levels of CLI orchestration:

1. **Docker CLI**: Container management, logs, exec, stats
2. **QEMU CLI**: VM control via monitor, snapshots, debugging
3. **MCP Tools**: AI-assisted operations via Model Context Protocol

### Key Scripts

- `scripts/launch-hurd-debug.sh` - Launch with full debugging
- `scripts/qemu-cli-control.sh` - QEMU VM management
- `scripts/docker-orchestration.sh` - Docker container orchestration

### Access Methods

| Method | Port | Purpose |
|--------|------|---------|
| QEMU Monitor | 9999 | VM control (QMP) |
| Serial Console | 5555 | Boot messages, login |
| SSH | 2222 | Remote shell access |
| VNC | 5900 | Graphical console |

### Next Steps

- Explore advanced QEMU debugging with GDB integration
- Implement custom MCP servers for your workflow
- Automate testing with GitHub Actions
- Create snapshot-based development workflows

---

**Last Updated**: 2025-11-17
**Version**: 1.0.0
