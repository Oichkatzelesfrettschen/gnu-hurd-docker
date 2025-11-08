# GNU/Hurd Docker - Performance Monitoring Guide

**Last Updated**: 2025-11-07  
**Consolidated From**:
- scripts/monitor-qemu.sh (performance monitoring tool)
- QEMU performance monitoring documentation

**Purpose**: Complete guide to monitoring QEMU and GNU/Hurd guest performance

**Scope**: Debian GNU/Hurd x86_64 only (i386 deprecated 2025-11-07)

---

## Overview

Monitoring the GNU/Hurd QEMU environment involves tracking multiple layers:

1. **Host System** - Physical hardware resources
2. **Docker Container** - Container resource usage
3. **QEMU Process** - Emulator/hypervisor performance
4. **Guest System** - GNU/Hurd OS and applications

This guide covers all four layers with real-time monitoring tools and diagnostic techniques.

---

## Quick Start

### Using monitor-qemu.sh

The repository provides `scripts/monitor-qemu.sh` for comprehensive performance monitoring.

**Basic Usage:**

```bash
# From repository root
./scripts/monitor-qemu.sh

# Or make executable and run
chmod +x scripts/monitor-qemu.sh
./scripts/monitor-qemu.sh
```

**Output Example:**

```
==================== QEMU Performance Monitor ====================
Timestamp: 2025-11-07 14:32:15

--- QEMU Process ---
PID: 12345
CPU: 85.2%
RAM: 4250 MB / 4096 MB (allocated)
Threads: 4
Uptime: 3h 25m

--- Guest Performance ---
VCPUs: 2 (host CPU model)
vCPU 0: 42.3% usage
vCPU 1: 38.7% usage

--- Disk I/O ---
Device: ide0-hd0 (debian-hurd-amd64.qcow2)
Read:  123.4 MB (456 ops)
Write: 89.2 MB (234 ops)
Cache: writeback
AIO: threads

--- Network ---
Device: e1000 (net0)
RX: 12.5 MB (8,234 packets)
TX: 8.3 MB (5,678 packets)
Dropped: 0

--- Memory ---
Guest RAM: 4096 MB
Host RSS: 4250 MB
Swap: 0 MB

==================================================================
```

**Refresh Interval:**

```bash
# Update every 2 seconds (default: 5)
watch -n 2 ./scripts/monitor-qemu.sh

# Or use continuous mode (if implemented)
./scripts/monitor-qemu.sh --continuous
```

---

## Layer 1: Host System Monitoring

### CPU Usage

**Real-Time CPU:**

```bash
# Overall system CPU
top -b -n 1 | head -20

# QEMU process specifically
top -b -n 1 -p $(pgrep qemu-system-x86_64)

# Per-core breakdown
mpstat -P ALL 1
```

**CPU Statistics:**

```bash
# Average over 1 second
sar -u 1 1
# %user: Application CPU time
# %system: Kernel CPU time
# %iowait: Waiting for I/O
# %idle: Idle CPU

# Long-term averages
sar -u
```

**Expected Values**:
- **KVM (hardware acceleration)**: 20-40% CPU under load
- **TCG (software emulation)**: 80-100% CPU under load
- **Idle**: < 5% CPU

### Memory Usage

**System Memory:**

```bash
# Overall memory
free -h
#               total        used        free      shared  buff/cache   available
# Mem:           31Gi       8.2Gi       18Gi       1.2Gi       4.5Gi        21Gi
# Swap:         8.0Gi          0B       8.0Gi

# Detailed breakdown
cat /proc/meminfo | head -20
```

**QEMU Memory:**

```bash
# QEMU process memory (RSS = actual RAM usage)
ps aux | grep qemu-system-x86_64 | grep -v grep
# Expected RSS: ~4.2 GB for 4 GB guest

# Detailed memory map
cat /proc/$(pgrep qemu-system-x86_64)/status | grep -E "Vm|Rss"
```

**Expected Values**:
- **Guest RAM allocation**: 4 GB (default)
- **QEMU RSS (host)**: ~4.2 GB (guest RAM + overhead)
- **Swap usage**: 0 MB (swapping kills performance)

### Disk I/O

**I/O Statistics:**

```bash
# Real-time I/O
iostat -x 1
# Device            r/s     w/s     rkB/s    wkB/s  %util
# sda              12.3    45.6     123.4     456.7   8.2%

# Per-process I/O
iotop -p $(pgrep qemu-system-x86_64)
```

**Disk Queue:**

```bash
# Check queue depth
cat /sys/block/sda/queue/nr_requests
# Higher = more buffering (default: 128)
```

**Expected Values**:
- **Read throughput**: 50-500 MB/s (depends on workload)
- **Write throughput**: 50-300 MB/s
- **%util**: < 50% (not I/O bottlenecked)

### Network Monitoring

**Interface Statistics:**

```bash
# Real-time network
iftop -i docker0

# Statistics
ifstat -i docker0 1
#       docker0
#  KB/s in  KB/s out
#    125.3     89.2
```

**Connection Tracking:**

```bash
# Active connections
ss -tunap | grep qemu

# NAT translation (port forwarding)
iptables -t nat -L -n -v | grep 2222
```

---

## Layer 2: Docker Container Monitoring

### Container Resource Usage

**Real-Time Stats:**

```bash
# All containers
docker stats

# Specific container
docker stats hurd-x86_64-qemu

# Output:
# CONTAINER         CPU %   MEM USAGE / LIMIT     MEM %   NET I/O         BLOCK I/O
# hurd-x86_64-qemu  42%     4.2GiB / 31.3GiB      13.4%   12MB / 8MB      1.2GB / 890MB
```

**Container Logs:**

```bash
# Follow logs
docker-compose logs -f

# Last 100 lines
docker-compose logs --tail=100

# Specific time range
docker-compose logs --since 10m
```

**Container Inspection:**

```bash
# Full container details
docker inspect hurd-x86_64-qemu | less

# Resource limits
docker inspect hurd-x86_64-qemu | jq '.[].HostConfig.Memory'
docker inspect hurd-x86_64-qemu | jq '.[].HostConfig.CpuQuota'
```

### Container Resource Limits

**Current Limits** (docker-compose.yml):

```yaml
services:
  hurd-x86_64-qemu:
    deploy:
      resources:
        limits:
          cpus: '4'        # Max 4 CPU cores
          memory: 8G       # Max 8 GB RAM
        reservations:
          cpus: '2'        # Guaranteed 2 cores
          memory: 4G       # Guaranteed 4 GB
```

**Apply Limits:**

```bash
# Edit docker-compose.yml with limits above
docker-compose up -d --force-recreate
```

**Verify Limits:**

```bash
docker inspect hurd-x86_64-qemu | jq '.[].HostConfig.NanoCpus'
# Output: 4000000000 (4 CPUs = 4 * 10^9 nanoseconds)

docker inspect hurd-x86_64-qemu | jq '.[].HostConfig.Memory'
# Output: 8589934592 (8 GB in bytes)
```

---

## Layer 3: QEMU Process Monitoring

### QEMU Process Details

**Process Information:**

```bash
# Find QEMU PID
pgrep qemu-system-x86_64

# Or with details
ps aux | grep qemu-system-x86_64 | grep -v grep
# Output: qemu user, PID, %CPU, %MEM, command line

# Full command line
cat /proc/$(pgrep qemu-system-x86_64)/cmdline | tr '\0' '\n'
```

**Thread Information:**

```bash
# Threads (QEMU is multi-threaded)
ps -eLf | grep qemu-system-x86_64 | head -10

# Thread count
ps -o nlwp $(pgrep qemu-system-x86_64)
# Expected: 4-8 threads (depends on SMP config)
```

**CPU Affinity:**

```bash
# Check CPU affinity (which cores QEMU uses)
taskset -cp $(pgrep qemu-system-x86_64)
# Output: pid 12345's current affinity list: 0-7

# Pin to specific cores (optional optimization)
taskset -cp 0,1,2,3 $(pgrep qemu-system-x86_64)
```

### QEMU Monitor Interface

**Connect to Monitor:**

```bash
telnet localhost 9999
# Or: nc localhost 9999
```

**Performance Commands:**

```
(qemu) info status
VM status: running

(qemu) info cpus
* CPU #0: pc=0x00007f8b (halted)
  CPU #1: pc=0x00007f9c (running)

(qemu) info registers
# Shows CPU register state (advanced debugging)

(qemu) info mem
# Shows guest physical memory map

(qemu) info mtree
# Shows memory region tree (very detailed)

(qemu) info blockstats
# Shows disk I/O statistics

(qemu) info network
# Shows network device status
```

**Real-Time Metrics:**

```bash
# Loop to continuously query status
while true; do
    echo "info status" | nc localhost 9999 | grep "VM status"
    sleep 1
done
```

### QMP (Programmatic Monitoring)

**Query QEMU via QMP:**

```python
#!/usr/bin/env python3
import json, socket

def qmp_query(command):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect("/var/run/qemu-monitor.sock")
    
    # Read greeting
    greeting = s.recv(4096)
    
    # Negotiate capabilities
    s.sendall(b'{"execute":"qmp_capabilities"}\n')
    s.recv(4096)
    
    # Execute query
    s.sendall((json.dumps({"execute": command}) + "\n").encode())
    response = json.loads(s.recv(65536).decode())
    
    s.close()
    return response

# Example queries
print(qmp_query("query-status"))
print(qmp_query("query-cpus-fast"))
print(qmp_query("query-blockstats"))
print(qmp_query("query-migrate"))
```

---

## Layer 4: Guest System Monitoring

### Accessing Guest Metrics

**Via SSH:**

```bash
# Connect to guest
ssh -p 2222 root@localhost

# Run monitoring commands inside guest
top
vmstat 1
iostat -x 1
```

**Via Serial Console:**

```bash
# Connect to serial console
telnet localhost 5555

# Login and run commands
# (Limited by serial console capabilities)
```

### Guest CPU Usage

**Inside Guest:**

```bash
# Real-time CPU
top

# CPU statistics
mpstat 1

# Per-process CPU
ps aux --sort=-%cpu | head -20
```

**Expected Values**:
- **Idle system**: < 5% CPU
- **Boot process**: 40-80% CPU (first 5 minutes)
- **Compile job**: 80-100% CPU (normal)

### Guest Memory Usage

**Inside Guest:**

```bash
# Memory overview
free -h
#               total        used        free      shared  buff/cache   available
# Mem:          3.9Gi       450Mi       2.8Gi        12Mi       680Mi       3.3Gi
# Swap:            0B          0B          0B

# Detailed memory
cat /proc/meminfo | head -20

# Per-process memory
ps aux --sort=-%mem | head -20
```

**Expected Values**:
- **Total RAM**: 4 GB (matches QEMU -m 4096)
- **Used**: 400-800 MB (idle system)
- **Free**: 3-3.5 GB (idle)
- **Swap**: 0 MB (Hurd typically doesn't configure swap)

### Guest Disk I/O

**Inside Guest:**

```bash
# I/O statistics
iostat -x 1
# Device            r/s     w/s     rkB/s    wkB/s
# hd0              5.2     12.3     52.4     123.5

# Per-process I/O (if iotop available)
iotop

# Disk usage
df -h
# Filesystem      Size  Used Avail Use% Mounted on
# /dev/hd0s1       20G  3.2G   16G  17% /
```

### Guest Network Monitoring

**Inside Guest:**

```bash
# Network interfaces
ip addr show

# Network statistics
ip -s link show eth0
# RX: bytes  packets  errors  dropped
#     1.2M   8234     0       0
# TX: bytes  packets  errors  dropped
#     890K   5678     0       0

# Active connections
ss -tunap

# Bandwidth (if iftop available)
iftop -i eth0
```

---

## Performance Metrics and Baselines

### Boot Time Benchmarks

**Expected Boot Times**:

| Configuration | Boot Time | Notes |
|---------------|-----------|-------|
| KVM + SSD | 2-3 minutes | Hardware acceleration, fast disk |
| KVM + HDD | 4-6 minutes | Hardware acceleration, slow disk |
| TCG + SSD | 5-8 minutes | Software emulation, fast disk |
| TCG + HDD | 8-15 minutes | Software emulation, slow disk |

**Measuring Boot Time:**

```bash
# Start timer
START_TIME=$(date +%s)

# Start VM
docker-compose up -d

# Wait for SSH to be available
while ! nc -z localhost 2222; do
    sleep 1
done

# Calculate boot time
END_TIME=$(date +%s)
BOOT_TIME=$((END_TIME - START_TIME))
echo "Boot time: ${BOOT_TIME} seconds"
```

### CPU Performance Baselines

**Expected CPU Usage** (x86_64 guest):

| Scenario | KVM | TCG |
|----------|-----|-----|
| Idle | 2-5% | 5-10% |
| Boot | 30-50% | 80-100% |
| Compile (gcc) | 80-95% | 90-100% |
| Network I/O | 10-20% | 30-50% |
| Disk I/O | 15-25% | 40-60% |

**Benchmark Inside Guest:**

```bash
# CPU benchmark with sysbench (install first)
apt-get install -y sysbench

# Single-threaded
sysbench cpu --threads=1 run

# Multi-threaded (2 cores)
sysbench cpu --threads=2 run

# Expected (KVM): ~2000 events/sec per core
# Expected (TCG): ~200 events/sec per core
```

### Disk Performance Baselines

**Expected Disk Throughput** (QCOW2, cache=writeback):

| Operation | KVM | TCG | Notes |
|-----------|-----|-----|-------|
| Sequential Read | 400-800 MB/s | 100-300 MB/s | Host SSD |
| Sequential Write | 300-600 MB/s | 80-200 MB/s | Host SSD |
| Random Read | 100-200 MB/s | 30-80 MB/s | 4K blocks |
| Random Write | 80-150 MB/s | 20-60 MB/s | 4K blocks |

**Benchmark Inside Guest:**

```bash
# Install fio
apt-get install -y fio

# Sequential read
fio --name=seqread --rw=read --bs=1M --size=1G --numjobs=1

# Sequential write
fio --name=seqwrite --rw=write --bs=1M --size=1G --numjobs=1

# Random read (4K)
fio --name=randread --rw=randread --bs=4K --size=1G --numjobs=1

# Random write (4K)
fio --name=randwrite --rw=randwrite --bs=4K --size=1G --numjobs=1
```

### Network Performance Baselines

**Expected Network Throughput** (e1000 NIC, user-mode networking):

| Direction | Throughput | Notes |
|-----------|------------|-------|
| Guest → Host | 50-200 MB/s | Limited by user-mode NAT |
| Host → Guest | 50-200 MB/s | Limited by user-mode NAT |
| Guest → Internet | 10-50 MB/s | Depends on ISP |

**Benchmark:**

```bash
# Inside guest - install iperf3
apt-get install -y iperf3

# On host - run server
iperf3 -s

# Inside guest - test download (guest → host)
iperf3 -c <host-ip>

# Expected: 50-200 Mbits/sec
```

---

## Troubleshooting Performance Issues

### High CPU Usage (QEMU Process)

**Symptoms:**
- QEMU process consuming 100% CPU constantly
- Host system sluggish
- Fan noise / high temperature

**Diagnosis:**

```bash
# Check if KVM is enabled
docker-compose exec hurd-x86_64-qemu ps aux | grep qemu | grep -o "\-accel [^ ]*"
# Expected: -accel kvm
# If TCG only: performance will be poor

# Check CPU model
docker-compose exec hurd-x86_64-qemu ps aux | grep qemu | grep -o "\-cpu [^ ]*"
# KVM: -cpu host
# TCG: -cpu max

# Check vCPU count
docker-compose exec hurd-x86_64-qemu ps aux | grep qemu | grep -o "\-smp [^ ]*"
# Should match guest needs (2 recommended)
```

**Fix:**

```bash
# Enable KVM (Linux only)
# Uncomment in docker-compose.yml:
devices:
  - /dev/kvm:/dev/kvm:rw

# Restart
docker-compose down
docker-compose up -d

# Verify KVM is used
docker-compose logs | grep -i kvm
# Expected: "KVM acceleration enabled"
```

### High Memory Usage

**Symptoms:**
- QEMU RSS > guest RAM + 500 MB
- Host system swapping
- Performance degradation

**Diagnosis:**

```bash
# Check QEMU memory
ps aux | grep qemu-system-x86_64 | awk '{print $6/1024 " MB"}'
# Expected: ~4.2 GB for 4 GB guest

# Check for memory leaks
watch -n 1 'ps aux | grep qemu'
# RSS should stabilize, not grow continuously

# Check host swap usage
free -h | grep Swap
# Swap usage should be 0
```

**Fix:**

```bash
# Reduce guest RAM if host is constrained
# Edit docker-compose.yml:
environment:
  QEMU_RAM: 2048  # Reduce from 4096 to 2048 MB

# Restart
docker-compose down
docker-compose up -d

# Disable host swap (emergency)
swapoff -a
```

### Slow Disk I/O

**Symptoms:**
- Guest feels sluggish
- Long pauses during file operations
- High %iowait on host

**Diagnosis:**

```bash
# Check QCOW2 cache mode
docker-compose exec hurd-x86_64-qemu ps aux | grep qemu | grep -o "cache=[^ ]*"
# Expected: cache=writeback (fastest)

# Check AIO mode
docker-compose exec hurd-x86_64-qemu ps aux | grep qemu | grep -o "aio=[^ ]*"
# Expected: aio=threads or aio=native

# Check host disk I/O
iostat -x 1
# %util > 80% = disk bottleneck
```

**Fix:**

```bash
# Option 1: Enable writeback cache (default in project)
# Already configured in entrypoint.sh:
# cache=writeback,aio=threads

# Option 2: Use native AIO (if available)
# Edit entrypoint.sh, change:
# cache=writeback,aio=threads
# to:
# cache=writeback,aio=native

# Option 3: Move QCOW2 to faster disk (SSD)
mv debian-hurd-amd64.qcow2 /path/to/ssd/
ln -s /path/to/ssd/debian-hurd-amd64.qcow2 .

# Restart
docker-compose restart
```

### Network Slowness

**Symptoms:**
- Slow SSH response time
- Poor throughput to/from guest
- Packet loss

**Diagnosis:**

```bash
# Check NIC model
docker-compose exec hurd-x86_64-qemu ps aux | grep qemu | grep -o "e1000"
# Expected: e1000 (compatible with Hurd)

# Check for packet drops (inside guest)
ssh -p 2222 root@localhost 'ip -s link show eth0'
# RX dropped: should be 0
# TX dropped: should be 0

# Test latency
ping -c 10 localhost
# RTT should be < 1 ms (loopback)

ssh -p 2222 root@localhost 'ping -c 10 8.8.8.8'
# RTT depends on ISP
```

**Fix:**

```bash
# Option 1: Use e1000 (already default)
# Configured in entrypoint.sh

# Option 2: Increase network buffer (if dropping packets)
# Inside guest:
ethtool -G eth0 rx 4096 tx 4096

# Option 3: Check Docker network (if issues persist)
docker network inspect gnu-hurd-docker_default
```

---

## Automated Monitoring Setup

### Continuous Monitoring Script

**monitor-continuous.sh:**

```bash
#!/bin/bash
# Continuous monitoring with logging

LOG_FILE="monitor-$(date +%Y%m%d-%H%M%S).log"
INTERVAL=5  # seconds

echo "Starting continuous monitoring (Ctrl-C to stop)"
echo "Logging to: $LOG_FILE"

while true; do
    echo "========== $(date) ==========" | tee -a "$LOG_FILE"
    ./scripts/monitor-qemu.sh | tee -a "$LOG_FILE"
    sleep "$INTERVAL"
done
```

### Prometheus Integration (Advanced)

**Export QEMU Metrics to Prometheus:**

```python
#!/usr/bin/env python3
# qemu-exporter.py - Prometheus exporter for QEMU

from prometheus_client import start_http_server, Gauge
import time, subprocess, re

# Define metrics
cpu_usage = Gauge('qemu_cpu_percent', 'QEMU CPU usage percentage')
mem_usage = Gauge('qemu_memory_bytes', 'QEMU memory usage in bytes')
disk_read = Gauge('qemu_disk_read_bytes', 'QEMU disk read bytes')
disk_write = Gauge('qemu_disk_write_bytes', 'QEMU disk write bytes')

def get_qemu_pid():
    result = subprocess.run(['pgrep', 'qemu-system-x86_64'], 
                          capture_output=True, text=True)
    return result.stdout.strip()

def update_metrics():
    pid = get_qemu_pid()
    if not pid:
        return
    
    # CPU usage
    ps_output = subprocess.run(['ps', '-p', pid, '-o', '%cpu='], 
                             capture_output=True, text=True).stdout.strip()
    cpu_usage.set(float(ps_output))
    
    # Memory usage
    ps_mem = subprocess.run(['ps', '-p', pid, '-o', 'rss='], 
                          capture_output=True, text=True).stdout.strip()
    mem_usage.set(int(ps_mem) * 1024)  # Convert KB to bytes
    
    # Disk I/O (from /proc/<pid>/io)
    with open(f'/proc/{pid}/io') as f:
        io_stats = f.read()
        read_bytes = re.search(r'read_bytes: (\d+)', io_stats)
        write_bytes = re.search(r'write_bytes: (\d+)', io_stats)
        if read_bytes:
            disk_read.set(int(read_bytes.group(1)))
        if write_bytes:
            disk_write.set(int(write_bytes.group(1)))

if __name__ == '__main__':
    # Start HTTP server for Prometheus
    start_http_server(9100)
    print("QEMU metrics exposed on :9100/metrics")
    
    while True:
        update_metrics()
        time.sleep(5)
```

**Run Exporter:**

```bash
python3 qemu-exporter.py &

# Check metrics
curl http://localhost:9100/metrics
```

### Alerting on Performance Issues

**Simple Alert Script:**

```bash
#!/bin/bash
# alert-performance.sh - Alert on high resource usage

CPU_THRESHOLD=90
MEM_THRESHOLD=95
ALERT_EMAIL="admin@example.com"

PID=$(pgrep qemu-system-x86_64)
if [ -z "$PID" ]; then
    echo "ALERT: QEMU process not found!" | mail -s "QEMU Down" "$ALERT_EMAIL"
    exit 1
fi

# Check CPU
CPU=$(ps -p "$PID" -o %cpu= | awk '{print int($1)}')
if [ "$CPU" -gt "$CPU_THRESHOLD" ]; then
    echo "ALERT: QEMU CPU usage at ${CPU}%" | mail -s "High CPU" "$ALERT_EMAIL"
fi

# Check Memory
MEM=$(ps -p "$PID" -o %mem= | awk '{print int($1)}')
if [ "$MEM" -gt "$MEM_THRESHOLD" ]; then
    echo "ALERT: QEMU memory usage at ${MEM}%" | mail -s "High Memory" "$ALERT_EMAIL"
fi
```

**Add to Crontab:**

```bash
# Run every 5 minutes
*/5 * * * * /path/to/alert-performance.sh
```

---

## Reference

### Monitoring Command Summary

```bash
# Host layer
top                          # Overall CPU/memory
iostat -x 1                  # Disk I/O
iftop -i docker0             # Network traffic
sar -u 1 1                   # CPU statistics

# Container layer
docker stats                 # Real-time container stats
docker-compose logs -f       # Container logs
docker inspect <container>   # Container details

# QEMU layer
./scripts/monitor-qemu.sh    # Comprehensive QEMU monitoring
telnet localhost 9999        # QEMU Monitor (HMP)
# (qemu) info status         # VM status
# (qemu) info cpus           # vCPU status
# (qemu) info blockstats     # Disk I/O stats

# Guest layer
ssh -p 2222 root@localhost   # SSH into guest
# top                        # Guest CPU/memory
# iostat -x 1                # Guest disk I/O
# ip -s link                 # Guest network stats
```

### Performance Metrics Quick Reference

**Good Performance Indicators**:
- ✅ QEMU CPU < 50% (KVM) or < 100% (TCG)
- ✅ Boot time < 5 minutes (KVM) or < 10 minutes (TCG)
- ✅ SSH response time < 100 ms
- ✅ Disk I/O %util < 50%
- ✅ Network packet loss = 0%
- ✅ Host swap usage = 0 MB

**Poor Performance Indicators**:
- ❌ QEMU CPU = 100% constantly (check KVM)
- ❌ Boot time > 15 minutes (investigate)
- ❌ SSH response time > 1 second
- ❌ Disk I/O %util > 80% (disk bottleneck)
- ❌ Network packet loss > 1%
- ❌ Host swap usage > 100 MB (add RAM)

### File Paths

**Host:**
- Monitor script: `./scripts/monitor-qemu.sh`
- Log files: `./monitor-*.log` (if logging enabled)

**Container:**
- QEMU Monitor: `telnet:0.0.0.0:9999`
- QMP Socket: `/var/run/qemu-monitor.sock`

**Guest:**
- Monitoring tools: `/usr/bin/top`, `/usr/bin/iostat`, etc.

### Environment Variables

```bash
# Override monitor interval
export MONITOR_INTERVAL=2
watch -n "$MONITOR_INTERVAL" ./scripts/monitor-qemu.sh

# Override QEMU PID (if multiple instances)
export QEMU_PID=12345
./scripts/monitor-qemu.sh
```

---

**Status**: Production Ready (x86_64-only)  
**Last Updated**: 2025-11-07  
**Architecture**: Pure x86_64  
**Monitoring Layers**: 4 (Host, Container, QEMU, Guest)
