# GNU/Hurd Docker - CI/CD Guide

**Last Updated:** 2025-11-06  
**Version:** 2.0  
**Purpose:** Comprehensive guide for QEMU-based CI/CD automation

---

## Table of Contents

1. [Overview](#overview)
2. [GitHub-Hosted Runners (TCG)](#github-hosted-runners-tcg)
3. [Self-Hosted Runners (KVM)](#self-hosted-runners-kvm)
4. [QMP Automation](#qmp-automation)
5. [Serial Console Control](#serial-console-control)
6. [Cloud-Init Configuration](#cloud-init-configuration)
7. [Workflow Examples](#workflow-examples)
8. [Troubleshooting](#troubleshooting)

---

## Overview

This guide covers two production-grade approaches for running GNU/Hurd in QEMU within GitHub Actions CI/CD:

### Approach A: GitHub-Hosted Runners (TCG Mode)
- **Acceleration:** None (TCG software emulation)
- **Performance:** Slower (~10-20% of native)
- **Availability:** Always available
- **Cost:** Free for public repositories
- **Use Case:** Automated testing, validation, builds

### Approach B: Self-Hosted Runners (KVM Mode)
- **Acceleration:** KVM (hardware virtualization)
- **Performance:** Fast (~80-90% of native)
- **Availability:** Requires setup
- **Cost:** Infrastructure cost
- **Use Case:** Performance testing, production builds

---

## GitHub-Hosted Runners (TCG)

### Architecture

```
GitHub Runner (ubuntu-latest)
  └── QEMU (TCG emulation)
      └── GNU/Hurd (i386)
          ├── Serial Console (logs)
          ├── QMP Socket (control)
          └── SSH (commands)
```

### Key Features

1. **Headless Operation:** `-nographic` mode
2. **Serial Logging:** Captures boot and console output
3. **QMP Control:** JSON-based VM management
4. **SSH Access:** Command execution post-boot
5. **Artifact Collection:** Logs and test results

### Workflow Configuration

The workflow is implemented in `.github/workflows/qemu-ci-tcg.yml`:

**Key Components:**
- QEMU system emulator (qemu-system-i386)
- Cloud-init for automated configuration
- QMP helper for VM control
- Serial and SSH for guest interaction
- Artifact upload for debugging

### Performance Characteristics

| Metric | Value | Notes |
|--------|-------|-------|
| Boot Time | 3-5 minutes | TCG emulation |
| CPU Speed | 10-20% native | Software emulation |
| Memory | 2 GB guest | Adequate for testing |
| I/O Speed | Moderate | Cached writes |
| Reliability | High | Fully deterministic |

---

## Self-Hosted Runners (KVM)

### Requirements

**Hardware:**
- CPU with VT-x (Intel) or AMD-V (AMD)
- 8 GB+ RAM
- 50 GB+ disk space
- Linux host OS

**Software:**
- KVM kernel modules loaded
- `/dev/kvm` accessible to runner user
- Docker and QEMU installed

### Runner Setup

**1. Install GitHub Runner:**
```bash
# Create runner user
sudo useradd -m -s /bin/bash github-runner
sudo usermod -aG kvm,docker github-runner

# Download and configure runner
cd /home/github-runner
curl -o actions-runner-linux-x64.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz
tar xzf actions-runner-linux-x64.tar.gz

# Configure (requires repo token)
./config.sh --url https://github.com/OWNER/REPO --token TOKEN --labels self-hosted,linux,x64,kvm

# Install as service
sudo ./svc.sh install github-runner
sudo ./svc.sh start
```

**2. Verify KVM Access:**
```bash
sudo -u github-runner ls -l /dev/kvm
# Should show: crw-rw-rw- ... /dev/kvm

sudo -u github-runner groups
# Should include: kvm docker
```

**3. Configure Docker:**
```bash
# Ensure runner can use Docker
sudo usermod -aG docker github-runner
sudo systemctl restart docker
```

### Workflow Configuration

The workflow is implemented in `.github/workflows/qemu-ci-kvm.yml`:

**Differences from TCG:**
- Uses `runs-on: [self-hosted, linux, x64, kvm]`
- Adds `-enable-kvm -cpu host` to QEMU command
- Allocates more resources (4 GB RAM, 4 CPUs)
- Faster execution times

### Performance Characteristics

| Metric | Value | Notes |
|--------|-------|-------|
| Boot Time | 30-60 seconds | KVM acceleration |
| CPU Speed | 80-90% native | Hardware virtualization |
| Memory | 4 GB guest | More resources available |
| I/O Speed | Fast | Direct disk access |
| Reliability | High | Requires stable host |

---

## QMP Automation

### QMP (QEMU Machine Protocol)

QMP is a JSON-based protocol for controlling QEMU programmatically.

**Socket Location:** `vm/qmp/qmp.sock`

**Protocol Flow:**
1. Connect to Unix socket
2. Receive greeting: `{"QMP": {...}}`
3. Send capabilities: `{"execute": "qmp_capabilities"}`
4. Send commands and receive responses

### QMP Helper Script

**Location:** `scripts/qmp-helper.py`

**Basic Usage:**
```bash
# Query VM status
echo '{"execute":"query-status"}' | python3 scripts/qmp-helper.py

# Stop VM
echo '{"execute":"stop"}' | python3 scripts/qmp-helper.py

# Resume VM
echo '{"execute":"cont"}' | python3 scripts/qmp-helper.py

# Send keyboard input (for boot menus)
echo '{"execute":"human-monitor-command","arguments":{"command-line":"sendkey esc"}}' \
  | python3 scripts/qmp-helper.py
```

### Common QMP Commands

**Query Information:**
```json
{"execute":"query-status"}
{"execute":"query-cpus"}
{"execute":"query-block"}
{"execute":"query-vnc"}
```

**Control VM:**
```json
{"execute":"stop"}
{"execute":"cont"}
{"execute":"system_reset"}
{"execute":"system_powerdown"}
```

**Send Keys (via HMP):**
```json
{"execute":"human-monitor-command","arguments":{"command-line":"sendkey ctrl-alt-delete"}}
{"execute":"human-monitor-command","arguments":{"command-line":"sendkey f12"}}
{"execute":"human-monitor-command","arguments":{"command-line":"sendkey ret"}}
```

**Screenshot (if VNC enabled):**
```json
{"execute":"screendump","arguments":{"filename":"/tmp/screen.ppm"}}
```

---

## Serial Console Control

### Serial Configuration

**QEMU Setup:**
```bash
-serial file:vm/serial.log        # Serial 0: Log file
-serial telnet:127.0.0.1:5555,server,nowait  # Serial 1: Interactive
```

**Access Methods:**

**1. Telnet (Interactive):**
```bash
telnet localhost 5555
# Or
./scripts/connect-console.sh
```

**2. Log File (Monitoring):**
```bash
tail -f vm/serial.log
```

**3. Socat (Scripting):**
```bash
# Send commands
echo "ls -la" | socat - TCP:localhost:5555

# Read output
socat - TCP:localhost:5555,readbytes=1024
```

### Console Automation

**Wait for Boot Prompt:**
```bash
#!/bin/bash
while ! grep -q "login:" vm/serial.log; do
  echo "Waiting for login prompt..."
  sleep 5
done
echo "System booted!"
```

**Send Console Commands:**
```bash
# Using expect (requires expect package)
expect <<EOF
spawn telnet localhost 5555
expect "login:"
send "root\r"
expect "Password:"
send "root\r"
expect "#"
send "uname -a\r"
expect "#"
send "exit\r"
EOF
```

---

## Cloud-Init Configuration

### Overview

Cloud-init automates guest OS configuration on first boot.

**Components:**
1. **user-data.yaml:** User accounts, packages, commands
2. **meta-data.yaml:** Instance metadata
3. **seed.iso:** ISO image containing above files

### User Data Example

**File:** `vm/seed/user-data.yaml`

```yaml
#cloud-config
users:
  - name: ci
    gecos: CI User
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    lock_passwd: false
    passwd: $6$rounds=4096$saltsalt$hashedpassword
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3... ci@github-runner

package_update: true
package_upgrade: false

packages:
  - build-essential
  - git
  - python3

runcmd:
  - systemctl enable ssh
  - systemctl start ssh
  - echo "Setup complete" > /var/log/cloud-init-done
```

### Meta Data Example

**File:** `vm/seed/meta-data.yaml`

```yaml
instance-id: github-ci-$(date +%s)
local-hostname: hurd-ci
```

### Creating Seed ISO

```bash
# Install cloud-image-utils
sudo apt-get install cloud-image-utils

# Create seed ISO
cloud-localds vm/seed/seed.iso vm/seed/user-data.yaml vm/seed/meta-data.yaml

# Attach to QEMU
qemu-system-i386 \
  ... \
  -drive if=virtio,media=cdrom,file=vm/seed/seed.iso
```

### SSH Key Management

**Generate Key Pair:**
```bash
ssh-keygen -t ed25519 -f ci-key -N "" -C "ci@github-runner"
```

**Add to GitHub Secrets:**
- `CI_SSH_PRIVKEY`: Content of `ci-key`
- `CI_SSH_PUBKEY`: Content of `ci-key.pub`

**Use in Workflow:**
```yaml
- name: Setup SSH key
  run: |
    mkdir -p ~/.ssh
    echo "${{ secrets.CI_SSH_PRIVKEY }}" > ~/.ssh/ci-key
    chmod 600 ~/.ssh/ci-key
```

---

## Workflow Examples

### Example 1: Basic Build Test

```yaml
name: QEMU Build Test
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      
      - name: Install QEMU
        run: |
          sudo apt-get update
          sudo apt-get install -y qemu-system-i386 qemu-utils cloud-image-utils socat
      
      - name: Prepare VM
        run: |
          mkdir -p vm/{images,seed,qmp}
          # Use pre-built image or build one
          
      - name: Launch QEMU
        run: |
          nohup qemu-system-i386 \
            -machine q35,accel=tcg -cpu qemu64 -smp 2 -m 2048 \
            -drive if=virtio,file=vm/images/disk.qcow2,format=qcow2 \
            -netdev user,id=net0,hostfwd=tcp::2222-:22 \
            -device virtio-net-pci,netdev=net0 \
            -nographic \
            -serial file:vm/serial.log \
            -qmp unix:vm/qmp/qmp.sock,server=on,wait=off \
            &> vm/qemu.log &
          echo $! > vm/qemu.pid
      
      - name: Wait for SSH
        run: |
          for i in {1..60}; do
            if ssh -o StrictHostKeyChecking=no -p 2222 ci@localhost true 2>/dev/null; then
              echo "SSH ready"; exit 0
            fi
            sleep 5
          done
          echo "SSH timeout"; exit 1
      
      - name: Run Tests
        run: |
          ssh -o StrictHostKeyChecking=no -p 2222 ci@localhost 'uname -a'
      
      - name: Cleanup
        if: always()
        run: |
          kill $(cat vm/qemu.pid) || true
      
      - name: Upload Logs
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: qemu-logs
          path: vm/*.log
```

### Example 2: Performance Benchmark

```yaml
name: Performance Benchmark
on: [workflow_dispatch]

jobs:
  benchmark:
    runs-on: [self-hosted, linux, x64, kvm]
    steps:
      - uses: actions/checkout@v4
      
      - name: Launch QEMU with KVM
        run: |
          # Similar setup with -enable-kvm
          
      - name: Run Benchmarks
        run: |
          ssh -p 2222 ci@localhost 'bash -s' < ./scripts/benchmark.sh
      
      - name: Collect Results
        run: |
          ssh -p 2222 ci@localhost 'cat /tmp/benchmark-results.json' > results.json
      
      - name: Upload Results
        uses: actions/upload-artifact@v4
        with:
          name: benchmark-results
          path: results.json
```

### Example 3: Multi-Stage Build

```yaml
name: Multi-Stage Build
on: [push]

jobs:
  build-base:
    runs-on: ubuntu-latest
    steps:
      - name: Build base image
        run: |
          # Create base QCOW2 with cloud-init
          
      - name: Upload base image
        uses: actions/upload-artifact@v4
        with:
          name: base-image
          path: vm/images/base.qcow2
  
  test-integration:
    needs: build-base
    runs-on: ubuntu-latest
    steps:
      - name: Download base image
        uses: actions/download-artifact@v4
        with:
          name: base-image
          
      - name: Run integration tests
        run: |
          # Test with downloaded image
```

---

## Troubleshooting

### Common Issues

#### 1. QEMU Won't Start

**Symptoms:**
- Process exits immediately
- No output in logs

**Solutions:**
```bash
# Check QEMU syntax
qemu-system-i386 --help

# Verify image exists
ls -lh vm/images/disk.qcow2

# Check image integrity
qemu-img check vm/images/disk.qcow2

# Run with verbose output
qemu-system-i386 ... -d guest_errors -D /tmp/qemu-debug.log
```

#### 2. SSH Won't Connect

**Symptoms:**
- Connection refused
- Connection timeout

**Solutions:**
```bash
# Check if QEMU is running
ps aux | grep qemu

# Verify port forwarding
netstat -tlnp | grep 2222

# Check serial log for SSH service
grep -i "sshd" vm/serial.log

# Test from within VM (via console)
telnet localhost 5555
# Then: systemctl status ssh
```

#### 3. QMP Socket Errors

**Symptoms:**
- "No such file or directory"
- "Connection refused"

**Solutions:**
```bash
# Verify socket exists
ls -l vm/qmp/qmp.sock

# Check QEMU is running
ps aux | grep qemu

# Test socket manually
socat - UNIX-CONNECT:vm/qmp/qmp.sock
# Should receive QMP greeting

# Recreate socket directory
rm -rf vm/qmp && mkdir -p vm/qmp
```

#### 4. Boot Timeout

**Symptoms:**
- VM doesn't reach login prompt
- Hangs at boot

**Solutions:**
```bash
# Check serial log
tail -f vm/serial.log

# Look for errors
grep -i "error\|fail\|panic" vm/serial.log

# Increase timeout
# Modify wait loop from 60 to 120 iterations

# Check available memory
free -h

# Reduce VM memory if host constrained
# -m 1024 instead of -m 2048
```

#### 5. Performance Issues

**Symptoms:**
- Very slow boot
- Timeouts in CI

**Solutions:**
```bash
# Enable KVM if available
ls -l /dev/kvm
# Add -enable-kvm to QEMU command

# Reduce memory/CPU if constrained
-m 1024 -smp 1

# Use writeback cache
-drive ...,cache=writeback

# Disable unnecessary features
-vga none -display none
```

---

## Best Practices

### 1. Timeout Management

```yaml
jobs:
  test:
    timeout-minutes: 30  # Job-level timeout
    steps:
      - name: Wait for boot
        timeout-minutes: 10  # Step-level timeout
        run: |
          # Wait logic with max iterations
```

### 2. Resource Cleanup

```yaml
- name: Cleanup QEMU
  if: always()  # Always run, even on failure
  run: |
    if [ -f vm/qemu.pid ]; then
      kill -TERM $(cat vm/qemu.pid) || true
      sleep 2
      kill -KILL $(cat vm/qemu.pid) 2>/dev/null || true
    fi
```

### 3. Artifact Collection

```yaml
- name: Collect logs
  if: always()
  run: |
    tar czf logs.tar.gz vm/*.log vm/qmp/*.sock

- name: Upload artifacts
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: debug-logs
    path: logs.tar.gz
    retention-days: 7
```

### 4. Caching

```yaml
- name: Cache QEMU images
  uses: actions/cache@v3
  with:
    path: vm/images
    key: hurd-image-${{ hashFiles('scripts/download-image.sh') }}
```

### 5. Matrix Testing

```yaml
strategy:
  matrix:
    memory: [1024, 2048, 4096]
    cpu: [1, 2, 4]
steps:
  - name: Test with ${{ matrix.memory }}MB RAM
    run: |
      qemu-system-i386 -m ${{ matrix.memory }} -smp ${{ matrix.cpu }} ...
```

---

## Security Considerations

### 1. SSH Keys

- Generate unique keys per repository
- Store private keys in GitHub Secrets
- Rotate keys periodically
- Use ED25519 for better security

### 2. Secrets Management

```yaml
# Never expose secrets in logs
- name: Setup secrets
  run: |
    echo "${{ secrets.PASSWORD }}" | base64 > /tmp/creds
    # Don't echo secrets
```

### 3. Network Isolation

- Use user-mode networking (no root required)
- Restrict port forwarding to necessary ports only
- Consider firewall rules on self-hosted runners

### 4. Image Integrity

```bash
# Verify checksums
sha256sum vm/images/disk.qcow2
echo "expected_hash  vm/images/disk.qcow2" | sha256sum -c

# Sign images
gpg --sign vm/images/disk.qcow2

# Verify signatures
gpg --verify vm/images/disk.qcow2.sig
```

---

## Performance Optimization

### TCG Mode (GitHub-Hosted)

**Optimize for speed:**
```bash
qemu-system-i386 \
  -cpu qemu64,+sse,+sse2,+sse3  # Enable CPU features \
  -smp 2  # Use all available cores \
  -m 2048  # Maximum reasonable memory \
  -drive ...,cache=unsafe,aio=threads  # Fast but less safe \
  -net user,restrict=off  # No network restrictions
```

**Trade-offs:**
- `cache=unsafe`: Faster but data loss on crash
- More memory: Faster but may OOM on constrained runners
- More CPUs: Marginal benefit in TCG mode

### KVM Mode (Self-Hosted)

**Optimize for maximum performance:**
```bash
qemu-system-i386 \
  -enable-kvm \
  -cpu host  # Pass through host CPU features \
  -smp 4  # More cores for parallel builds \
  -m 4096  # More memory for caching \
  -drive ...,cache=writeback,aio=native  # Native AIO \
  -net tap,ifname=tap0  # Better network performance
```

**Additional optimizations:**
- Use huge pages for memory
- Pin CPU cores
- Use virtio devices
- Enable multi-queue virtio-net

---

## Monitoring and Observability

### Metrics to Track

```bash
# Boot time
start_time=$(date +%s)
# ... wait for boot ...
end_time=$(date +%s)
echo "Boot took $((end_time - start_time)) seconds"

# Resource usage
docker stats gnu-hurd-dev --no-stream

# QEMU process stats
ps aux | grep qemu
top -p $(pgrep qemu)

# Disk usage
qemu-img info vm/images/disk.qcow2
```

### Logging

```yaml
- name: Structured logging
  run: |
    echo "::group::QEMU Logs"
    cat vm/qemu.log
    echo "::endgroup::"
    
    echo "::group::Serial Console"
    cat vm/serial.log
    echo "::endgroup::"
```

---

## References

- [QEMU Documentation](https://www.qemu.org/docs/master/)
- [QMP Protocol](https://wiki.qemu.org/Documentation/QMP)
- [Cloud-Init](https://cloudinit.readthedocs.io/)
- [GitHub Actions](https://docs.github.com/en/actions)
- [Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)

---

**Status:** Production Ready  
**Last Updated:** 2025-11-06  
**Maintainer:** Oichkatzelesfrettschen
