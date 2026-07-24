# GNU Hurd Docker - Testing Roadmap & Backend Control Documentation

## Executive Summary

This roadmap outlines the remaining testing phases and comprehensive documentation of backend control mechanisms for Docker, QEMU, Podman, and Libvirt.

---

## Phase 1: Podman Backend Testing (Using Docker Methodology)

### Objectives
- Apply same multi-layer diagnostic approach as Docker testing
- Identify Podman-specific issues or improvements
- Test rootless Podman compatibility
- Document performance differences

### Testing Methodology (4-Layer Stack)

```
Host (CachyOS)
  ↓ Podman 5.7.1
    ↓ QEMU 10.1.2 (KVM)
      ↓ Guest kernel verification
        ↓ SSH or alternative access
```

### Steps

1. **Layer 1: Podman Orchestration**
   - Start container: `podman-compose up -d`
   - Verify container health: `podman ps`
   - Check volume mounts: `podman run -it ... mount`

2. **Layer 2: QEMU Process**
   - Verify QEMU launched: `podman exec ... ps aux | grep qemu`
   - Check CPU usage: `podman stats`
   - Inspect port forwarding: `podman inspect ... | grep -A 20 PortBindings`

3. **Layer 3: Guest Kernel**
   - Query QEMU monitor: Connect to port 9999
   - Check CPU state: `info registers`
   - Verify block I/O: `info blockstats`

4. **Layer 4: Access Method**
   - Attempt SSH (if guest configured)
   - Alternative: Serial console telnet to port 5555
   - Check /dev/kvm passthrough

### Expected Outcomes

| Component | Docker | Podman | Notes |
|-----------|--------|--------|-------|
| Container start | ✓ | ? | Test podman-compose |
| QEMU launch | ✓ | ? | Check rootless permissions |
| KVM passthrough | ✓ | ? | Rootless access to /dev/kvm |
| Guest boot | ✓ | ? | Same image, different engine |
| Performance | baseline | ? | Compare boot times |

### Known Podman Issues from Earlier Work
- Network creation failures (from initial attempts)
- Possible rootless permission issues with /dev/kvm
- Difference in volume mount handling vs Docker

---

## Phase 2: Libvirt Backend Testing

### Objectives
- Test libvirt/KVM management layer
- Compare with direct QEMU approach
- Document domain XML configuration
- Evaluate virsh command-line control

### Testing Methodology

```
Host (CachyOS)
  ↓ Libvirt 11.10.0
    ↓ QEMU 10.1.2 via libvirt domain
      ↓ Guest kernel (same diagnostics)
        ↓ SSH or serial console access
```

### Steps

1. **Libvirt Setup**
   - Start libvirtd: `sudo systemctl start libvirtd`
   - Define domain: `virsh define config/libvirt/gnu-hurd.xml`
   - Start VM: `virsh start gnu-hurd`

2. **Domain Management**
   - List domains: `virsh list --all`
   - Get domain info: `virsh dominfo gnu-hurd`
   - Monitor CPU: `virsh vcpuinfo gnu-hurd`

3. **Multi-Layer Diagnostics**
   - Query QEMU monitor through libvirt: `virsh qemu-monitor-command gnu-hurd 'info status'`
   - Check block devices: `virsh domblklist gnu-hurd`
   - Verify networking: `virsh domiflist gnu-hurd`

4. **Performance Comparison**
   - Boot time: libvirt vs direct QEMU vs Docker
   - Memory usage: virsh dommemstat
   - CPU overhead: compare to baseline

### Libvirt Advantages/Disadvantages

**Advantages**
- Persistent domain definitions
- Automatic network management
- Snapshot capabilities
- Live migration potential

**Disadvantages**
- Extra abstraction layer
- Potential performance overhead
- More complex troubleshooting

---

## Phase 3: Backend Control Methods Documentation

### 3A: SSH (Primary Access Method)

**Advantages**
- Standard remote access
- Scriptable automation
- Works across all platforms
- File transfer via SCP

**Disadvantages**
- Requires SSH daemon in guest
- Network latency
- Key management overhead

**Implementation**
```bash
# Docker
ssh -p 2222 root@127.0.0.1

# Podman  
ssh -p 2223 root@127.0.0.1

# Libvirt (via serial)
virsh console gnu-hurd
```

### 3B: Serial Console (Fallback Access)

**Advantages**
- Always available (no daemon required)
- Direct kernel boot output
- Useful for debugging hangs/crashes
- No network required

**Disadvantages**
- Character-by-character interaction
- No terminal features
- Slow for complex operations
- Requires telnet/socat

**Implementation**
```bash
# Direct telnet
telnet localhost 5555

# Via socat
socat - TCP:localhost:5555

# Send commands
echo "commands" | nc -q 1 localhost 5555
```

### 3C: QEMU Monitor (Hypervisor Control)

**Advantages**
- Direct QEMU control
- Query guest state without agent
- CPU/memory diagnostics
- Disk I/O monitoring

**Disadvantages**
- Not for guest interaction
- Requires understanding of QEMU semantics
- Limited debugging capability

**Implementation**
```bash
# Connect to monitor
nc localhost 9999

# Common commands
info status      # VM running state
info registers   # CPU state
info blockstats  # Disk activity
info network     # Network status
```

### 3D: QEMU Guest Agent (If Available for Hurd)

**Advantages**
- Structured communication
- File operations
- Exec capability
- Clean shutdown

**Disadvantages**
- Requires agent in guest
- Hurd may not support qemu-guest-agent
- Additional guest software

**Implementation**
```bash
# Via qga protocol
qemu-ga --version  # Check availability
```

### 3E: Docker Exec (Docker-Specific)

**Advantages**
- Fast container interaction
- Direct command execution
- No network latency
- Can access container shell

**Limitations**
- Only works with running QEMU container
- Not actual guest access (container level)
- Host-specific

**Implementation**
```bash
docker exec gnu-hurd-dev /bin/bash -c "command"
```

### 3F: Podman Exec (Podman-Specific)

**Advantages**
- Same as Docker exec
- Works with rootless Podman
- No daemon required

**Implementation**
```bash
podman exec gnu-hurd-dev command
```

### 3G: Libvirt Console/Spice

**Advantages**
- Integrated with libvirt
- Persistent connection
- VNC/Spice for graphical access

**Implementation**
```bash
virsh console gnu-hurd
virsh viewer gnu-hurd  # For graphical
```

### 3H: VBoxManage Equivalent Analysis

**Direct QEMU Control (No VBoxManage Equivalent)**
- QEMU doesn't have VBoxManage-style CLI
- Closest equivalents:
  - `qemu-system-x86_64` direct invocation
  - QEMU monitor commands (via telnet/socat)
  - Libvirt's `virsh` (higher-level abstraction)

**Comparison Matrix**

| Operation | VirtualBox | QEMU Direct | Libvirt/virsh |
|-----------|-----------|------------|---------------|
| Start VM | VBoxManage startvm | qemu-system-x86_64 | virsh start |
| Stop VM | VBoxManage controlvm ... poweroff | Kill process | virsh destroy |
| Pause | VBoxManage controlvm ... pause | QEMU monitor | virsh suspend |
| Snapshot | VBoxManage snapshot | QEMU snapshots | virsh snapshot-create |
| Query state | VBoxManage showvminfo | QEMU monitor | virsh dominfo |
| Serial access | VBoxManage list | Direct serial | virsh console |

---

## Phase 4: LLM-Specific Control Mechanisms

### Concept: Automated Testing Without SSH

**Challenge**: Standard SSH fails for Hurd image → need LLM-controlled alternatives

### 4A: Serial Console Automation (Most Viable)

**Mechanism**
```
LLM sends commands → socat/telnet to serial → guest receives input
Guest executes → socat/telnet receives output → LLM parses response
```

**Implementation**
```bash
# Send test command to serial console
echo "id" | nc -q 2 localhost 5555

# Capture output (with delays for processing)
{
    sleep 0.5
    echo "id"
    sleep 2
    echo "uname -a"
    sleep 2
} | socat - TCP:localhost:5555 > guest_output.log
```

**Challenges**
- No echo/feedback by default
- Timing-sensitive (must wait for guest processing)
- No terminal features (arrows, backspace)
- Hard to distinguish prompts

**Workarounds**
1. Send markers before/after commands
2. Implement expect-style pattern matching
3. Use `strace -e write` to monitor serial output
4. Pre-configure guest with simple response format

### 4B: HTTP/API Interface (Alternative Approach)

**Concept**: Start simple HTTP server in guest, control via REST API

**Implementation in Guest**
```bash
# Start Python HTTP server
python3 -m http.server 8080

# Or custom API endpoint
curl http://localhost:8080/api/execute?cmd=id
```

**Host-Side Control**
```bash
curl -X POST http://127.0.0.1:8080/api/execute \
  -H "Content-Type: application/json" \
  -d '{"command": "id"}'
```

**Advantages**
- Clean structured communication
- JSON request/response
- Easy error handling
- Can return formatted output

**Disadvantages**
- Requires guest HTTP daemon
- Network latency
- Additional guest dependencies

### 4C: File-Based Communication (Polling)

**Concept**: Guest watches for files, creates response files

**Implementation**
```bash
# Host sends command
echo "id" > /shared/command.txt

# Guest polls
while [ -f /shared/command.txt ]; do
  cmd=$(cat /shared/command.txt)
  eval "$cmd" > /shared/response.txt
  rm /shared/command.txt
done

# Host reads response
cat /shared/response.txt
```

**Advantages**
- Works with minimal guest dependencies
- Uses shared mount point
- Simple polling mechanism

**Disadvantages**
- Race conditions possible
- No real-time feedback
- Polling overhead

### 4D: QEMU Disk Snapshots + Rollback Testing

**Concept**: Snapshot guest state, test commands, rollback if failed

**Implementation**
```bash
# Create snapshot before test
virsh snapshot-create-as gnu-hurd pre-test

# Run test via serial/SSH
# Test fails or succeeds

# Rollback
virsh snapshot-revert gnu-hurd pre-test
```

**Use Case**: Automated testing that doesn't corrupt state

### 4E: Systemd Socket Activation (if Hurd Supports)

**Concept**: Guest listens on socket, responds to commands

**Implementation**
```ini
# /etc/systemd/system/command-server.socket
[Socket]
ListenStream=9001

# /etc/systemd/system/command-server.service
ExecStart=/usr/local/bin/command-handler
```

**Advantages**
- Daemon not always running
- Clean protocol
- Easy to implement

**Disadvantages**
- Requires systemd (Hurd may not have)
- Requires service implementation

### 4F: Hurd-Specific Mechanisms (Research Required)

**Potential Hurd Features**
- Hurd translators for dynamic command execution
- Messages API for inter-process communication
- Possibly unique control mechanisms not in Linux

**Research Tasks**
1. Check Hurd documentation for IPC/control mechanisms
2. Investigate Hurd settrans command capabilities
3. Look for Hurd-specific tooling

---

## Phase 5: Consolidated Testing Framework

### Architecture

```
Test Coordinator (LLM)
  ├─ Backend Abstraction Layer
  │   ├─ Docker backend
  │   ├─ Podman backend
  │   └─ Libvirt backend
  │
  ├─ Access Method Selector
  │   ├─ SSH (primary)
  │   ├─ Serial console (fallback)
  │   ├─ HTTP API (if available)
  │   └─ File polling (last resort)
  │
  ├─ Command Executor
  │   ├─ Execute command
  │   ├─ Parse output
  │   └─ Handle errors
  │
  └─ Diagnostic Generator
      ├─ Collect results
      ├─ Generate reports
      └─ Compare baselines
```

### Test Commands Library

**Docker**
```bash
make up                              # start the stack
make smoke-guest                     # SSH reachability and in-guest checks
make monitor CMD='info status'       # query the QEMU monitor
make down                            # stop and remove the stack
```

`make monitor` requires `CMD` and exits 2 with a usage message without it.

**Podman**

Every target defaults to Docker.  `CONTAINER_RUNTIME=podman` has to be passed on
each invocation: the target-specific assignment on `up-podman` applies to that
target only and does not persist into a later `make`.  Podman also publishes the
QEMU monitor on host port 9998 rather than 9999, so `MONITOR_PORT` has to follow.

```bash
make up-podman
make CONTAINER_RUNTIME=podman smoke-guest
make monitor MONITOR_PORT=9998 CMD='info status'
make CONTAINER_RUNTIME=podman down
```

**Libvirt**

Libvirt has no make targets; it is driven by `scripts/libvirt-hurd.sh`, whose
dispatcher implements `define`, `start`, `stop`, `undefine`, `status`, `info`,
`console`, and `ssh`.

```bash
./scripts/libvirt-hurd.sh define
./scripts/libvirt-hurd.sh start
./scripts/libvirt-hurd.sh status
./scripts/libvirt-hurd.sh stop
```

`cmd_ssh` ends its SSH invocation with `|| true`, so it reports success whatever
the guest returns.  Use a direct SSH command when the result is the thing being
tested:

```bash
ssh -p 2222 root@localhost 'uname -a'; echo "exit=$?"
```

### Diagnostic Output

Each test phase produces:
1. Boot time measurement
2. KVM acceleration confirmation
3. Port forwarding verification
4. Guest kernel validation
5. Access method availability
6. Performance metrics

---

## Phase 6: Documentation & Wrap-Up

### Files to Create/Update

1. **BACKEND-TESTING-RESULTS.md** (update with all results)
2. **TESTING-ROADMAP.md** (this file)
3. **LLM-CONTROL-GUIDE.md** (new - LLM-specific control mechanisms)
4. **SERIAL-CONSOLE-GUIDE.md** (new - serial console automation)
5. **PODMAN-TESTING-REPORT.md** (new - Podman results)
6. **LIBVIRT-TESTING-REPORT.md** (new - Libvirt results)
7. **FINAL-TESTING-SUMMARY.md** (new - comprehensive wrap-up)

### Final Report Structure

```
Final Testing Summary
├─ Executive Summary (all backends, key findings)
├─ Docker Backend (complete results + config)
├─ Podman Backend (complete results + config)
├─ Libvirt Backend (complete results + config)
├─ Access Methods Comparison (SSH vs serial vs HTTP)
├─ Performance Metrics (boot time, KVM, CPU, memory)
├─ Known Issues & Workarounds
├─ Recommendations for Production
└─ Future Improvements
```

---

## Timeline & Milestones

| Phase | Duration | Status |
|-------|----------|--------|
| 1. Docker Testing | ✓ Complete | DONE |
| 2. Podman Testing | 2-3 hours | NEXT |
| 3. Libvirt Testing | 2-3 hours | After Podman |
| 4. Control Methods | 2-3 hours | Parallel/After |
| 5. Framework | 1-2 hours | Final integration |
| 6. Documentation | 1-2 hours | Final pass |

**Total Remaining**: ~10-15 hours

---

## Success Criteria

- [ ] All three backends (Docker, Podman, Libvirt) tested and documented
- [ ] At least 2 access methods verified working per backend
- [ ] Serial console automation documented and tested
- [ ] Performance baselines established for all backends
- [ ] Known issues and workarounds fully documented
- [ ] Comprehensive testing guide available for future reference
- [ ] LLM control mechanisms documented for automated testing

---

## Key Unknowns to Investigate

1. **Hurd SSH Compatibility**: Why does sshd not respond despite configuration?
2. **Podman Rootless KVM**: How to pass /dev/kvm to rootless Podman?
3. **Libvirt Domain Networking**: How to configure domain for port forwarding?
4. **Serial Console Timing**: What are optimal delays for serial command execution?
5. **Hurd Unique Mechanisms**: What control mechanisms are Hurd-specific?

---

**Roadmap Created**: 2026-01-15
**Current Status**: Docker complete, Podman/Libvirt/Control methods pending
**Next Action**: Begin Podman backend testing using Docker methodology

