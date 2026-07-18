# Troubleshooting Playbook

A systematic decision tree for resolving common GNU/Hurd Docker issues.

## Quick Reference

| Issue | Time to Diagnose | Complexity | Severity |
|-------|------------------|-----------|----------|
| VM won't boot | 5-10 min | Medium | High |
| SSH not accessible | 5 min | Low | Medium |
| Disk/fsck errors | 10-15 min | Medium | High |
| Poor performance | 10 min | Medium | Low |
| VNC connection issues | 5-10 min | Low | Low |
| Container exits | 5 min | Low | High |
| Out of disk space | 2 min | Low | Medium |
| Network issues | 10-15 min | Medium | Medium |

---

## Issue 1: VM Won't Boot

### Symptoms
- Container starts but QEMU doesn't boot properly
- Serial console shows no output
- Health check fails or times out
- No visible GRUB menu or login prompt

### Decision Tree

```
Does container start?
├─ NO → Check: docker logs gnu-hurd-dev
│       Problem: entrypoint.sh failed
│       Solution: Fix image/secrets (see Issue #6)
│
└─ YES → Does QEMU process exist?
    ├─ NO → Check: docker exec gnu-hurd-dev ps aux | grep qemu
    │        Problem: QEMU not launching
    │        Solution: Enable debug; check QEMU_DISK_BUS compatibility
    │
    └─ YES → Does serial console show output?
        ├─ NO → Problem: GRUB timeout or kernel panic
        │        Solution: Try different disk bus or IDE controller
        │
        └─ YES → Is login prompt appearing?
            ├─ NO → Problem: Kernel panic or DMA errors
            │        Solution: Try different disk bus; reduce SMP
            │
            └─ YES → Can you login?
                ├─ NO → Problem: Authentication or root issue
                │        Solution: Reset image or use serial console
                │
                └─ YES → Boot successful! (proceed to SSH issue)
```

### Diagnostic Commands

```bash
# Check container is running
docker ps | grep gnu-hurd-dev

# View QEMU startup logs
docker logs gnu-hurd-dev | head -50

# Check QEMU process
docker exec gnu-hurd-dev ps aux | grep qemu

# Monitor serial console
docker exec gnu-hurd-dev socat - TCP:localhost:5555

# Check QEMU configuration
docker exec gnu-hurd-dev env | grep QEMU
```

### Solution Checklist

- [ ] Verify image exists: `ls -lh images/debian-hurd-amd64.qcow2`
- [ ] Check disk bus: Try `QEMU_DISK_BUS=ahci make up` if IDE fails
- [ ] Reduce CPU: Try `QEMU_SMP=1 make up` for stability
- [ ] Check KVM: Ensure `make up-kvm` if x86_64 Linux host
- [ ] Clean restart: `make down && rm -f .docker-state && make up`
- [ ] Review logs: `docker logs gnu-hurd-dev | grep -i error`

### Prevention

- Always create snapshot before major changes
- Test image integrity after download
- Use TCG fallback if IDE+KVM problematic
- Check /var/log/hurd inside guest for kernel issues

---

## Issue 2: SSH Not Accessible

### Symptoms
- Port 2222 not responding
- SSH command times out or refuses connection
- No SSH service running inside guest

### Decision Tree

```
Is container running?
├─ NO → Start it: make up
│
└─ YES → Is port 2222 bound?
    ├─ NO → Problem: Port binding failed
    │        Solution: Check compose.yaml, firewall rules
    │
    └─ YES → Does nc -zv localhost 2222 succeed?
        ├─ NO → Problem: SSH port open but service not ready
        │        Solution: Wait for boot; guest SSH not running
        │
        └─ YES → Can you connect?
            ├─ NO → Problem: SSH service crashed or misconfigured
            │        Solution: Check SSH via serial console
            │
            └─ YES → Is authentication failing?
                ├─ NO → SSH working! Success!
                │
                └─ YES → Problem: Wrong password/keys
                         Solution: Reset via serial console
```

### Diagnostic Commands

```bash
# Check port binding
netstat -tlnp | grep 2222
# or
ss -tlnp | grep 2222

# Test port accessibility
nc -zv localhost 2222

# Check via telnet
telnet localhost 2222

# Connect via SSH
ssh -v -p 2222 root@localhost

# Check SSH inside guest (serial console)
docker exec gnu-hurd-dev /opt/scripts/qemu-shell-run.sh "ps aux | grep sshd"

# View SSH service status
docker exec gnu-hurd-dev /opt/scripts/qemu-shell-run.sh "service ssh status"
```

### Solution Checklist

- [ ] Container running: `docker ps | grep gnu-hurd-dev`
- [ ] Port bound: `ss -tlnp | grep 2222`
- [ ] Port accessible: `nc -zv localhost 2222` (should get Connection succeeded)
- [ ] Wait for boot: Boot can take 3-15 minutes depending on host
- [ ] Check via serial: `docker logs gnu-hurd-dev | grep sshd`
- [ ] Restart SSH: `docker exec gnu-hurd-dev /opt/scripts/qemu-shell-run.sh "service ssh restart"`
- [ ] Reset password: Use serial console to change root password
- [ ] Check firewall: `sudo ufw status` or check iptables

### Prevention

- Use serial console for initial SSH setup
- Verify SSH is running before attempting login
- Keep default passwords in secrets directory
- Monitor SSH logs: `docker logs gnu-hurd-dev | grep ssh`

---

## Issue 3: Disk/fsck Errors

### Symptoms
- "fsck: [device] not clean" error
- Extended boot time (scanning, repairing)
- Data corruption or filesystem errors
- "Bad superblock" or similar errors

### Decision Tree

```
Is container starting?
├─ NO → fsck is checking disk
│       Wait 5-15 minutes; this is normal for first boot after crash
│       Monitor: docker logs -f gnu-hurd-dev
│
└─ YES → Is filesystem mounted read-only?
    ├─ YES → Problem: Filesystem damaged
    │         Solution: Run fsck -p inside guest or rebuild image
    │
    └─ NO → Does filesystem report errors?
        ├─ YES → Problem: Dirty journal or corruption
        │         Solution: Enable auto-fsck or manual repair
        │
        └─ NO → Disk healthy! Continue with normal operations
```

### Diagnostic Commands

```bash
# Check filesystem status in logs
docker logs gnu-hurd-dev | grep -i fsck

# Manual fsck (requires clean shutdown first)
docker exec gnu-hurd-dev /opt/scripts/guestfish-bootstrap-hurd-console.sh
# (inside guestfish)
run
fsck -p /dev/sda1

# Check disk image integrity
qemu-img info images/debian-hurd-amd64.qcow2

# Verify QEMU shutdown was clean
docker exec gnu-hurd-dev qemu-img check images/debian-hurd-amd64.qcow2
```

### Solution Checklist

- [ ] **Always use clean shutdown**: `make down` (not `docker kill`)
- [ ] Wait for fsck to complete on dirty images (5-15 min)
- [ ] Enable automatic fsck: Set `QEMU_FSCK=1` environment variable
- [ ] Reset image if corrupted: `scripts/setup-hurd-amd64.sh`
- [ ] Use IDE workaround: `AUTO_DISABLE_KVM_FOR_IDE=1 make up`
- [ ] Manual repair: Use guestfish or boot into maintenance mode
- [ ] Verify after repair: `qemu-img check` and re-run fsck

### Prevention

**Critical:** Always shut down cleanly!

```bash
# Always use this:
make down

# NEVER use (without reason):
docker kill gnu-hurd-dev
```

Additional precautions:
- Create snapshots before major operations
- Monitor disk space (prevent full disk)
- Use stable disk bus (test IDE, AHCI, SCSI)
- Check logs after unclean shutdown

---

## Issue 4: Poor Performance

### Symptoms
- Boot takes 5+ minutes
- Compilation extremely slow
- High host CPU usage without guest load
- Sluggish response in guest

### Decision Tree

```
Is KVM enabled?
├─ NO (using TCG) → This is normal (30-60x slower)
│                   Solution: Use make up-kvm on Linux x86_64
│
└─ YES → Check CPU allocation
    ├─ QEMU_SMP > 4 → Problem: Overhead from SMP
    │                  Solution: Reduce to QEMU_SMP=2-4
    │
    ├─ QEMU_RAM < 2GB → Problem: Not enough memory
    │                    Solution: Increase QEMU_RAM=4096
    │
    └─ Disk I/O bottleneck → Problem: Slow storage
                             Solution: Use SSD/NVMe; check cache mode
```

### Diagnostic Commands

```bash
# Check KVM vs TCG
docker logs gnu-hurd-dev | grep -i "accelerat\|kvm\|tcg"

# Monitor host CPU
top -p $(pgrep -f qemu-system)

# Check guest load
docker exec gnu-hurd-dev uptime
docker exec gnu-hurd-dev ps aux | head -20

# Benchmark compilation
docker exec gnu-hurd-dev time make -C /tmp/test

# Check QEMU settings
docker exec gnu-hurd-dev env | grep QEMU

# Check disk cache mode
docker inspect gnu-hurd-dev | grep -i cache
```

### Solution Checklist

- [ ] Enable KVM: `make up-kvm` (not available on macOS/non-x86)
- [ ] Reduce CPU: Try `QEMU_SMP=2 make up-kvm`
- [ ] Increase RAM: Try `QEMU_RAM=8192 make up-kvm`
- [ ] Check cache mode: `QEMU_DISK_CACHE=writeback` in environment
- [ ] Use faster storage: NVMe > SSD > HDD
- [ ] Monitor build parallelism: `make -j2` instead of `-j$(nproc)`
- [ ] Check host load: Ensure host isn't oversubscribed
- [ ] Enable disk acceleration: `QEMU_DISK_BUS=ahci`

### Performance Benchmarks

| Config | Boot | Compile |
|--------|------|---------|
| 1 core, TCG | 10 min | 45 sec |
| 2 cores, KVM | 1 min | 8 sec |
| 4 cores, KVM | 40 sec | 5 sec |

---

## Issue 5: VNC Connection Issues

### Symptoms
- Cannot connect to VNC display
- noVNC web interface not loading
- VNC port not responding

### Decision Tree

```
Is ENABLE_VNC=1?
├─ NO → Problem: VNC disabled
│        Solution: ENABLE_VNC=1 make up-vnc
│
└─ YES → Is VNC port 5900 listening?
    ├─ NO → Problem: VNC server not started
    │        Solution: Check QEMU logs for VNC startup
    │
    └─ YES → Can you connect with vncviewer?
        ├─ NO → Problem: Display config or network issue
        │        Solution: Check firewall, DISPLAY settings
        │
        └─ YES → Can you connect with noVNC?
            ├─ NO → Problem: noVNC container issue
            │        Solution: Check compose.vnc.yaml
            │
            └─ YES → VNC working! Enjoy GUI!
```

### Diagnostic Commands

```bash
# Start with VNC enabled
ENABLE_VNC=1 make up-vnc

# Check VNC port
ss -tlnp | grep 5900

# Check noVNC availability
curl -I http://localhost:6080/

# Connect via vncviewer
vncviewer localhost:5900

# Check QEMU VNC status
docker logs gnu-hurd-dev | grep -i vnc

# Test noVNC container
docker ps | grep novnc
```

### Solution Checklist

- [ ] Enable VNC: Use `compose.vnc.yaml`
- [ ] Check port: `ss -tlnp | grep 5900` should show qemu
- [ ] Check firewall: `sudo ufw allow 6080/tcp`
- [ ] Try vncviewer first: `vncviewer localhost:5900`
- [ ] Then try noVNC: `http://localhost:6080/`
- [ ] Check display: Verify DISPLAY env var in container
- [ ] Increase resolution: `DISPLAY_WIDTH=1920 DISPLAY_HEIGHT=1080`

### Prevention

- Use `make up-vnc` or `make up-kvm-vnc` for GUI work
- Monitor noVNC logs: `docker logs novnc`
- Keep firewall rules consistent

---

## Issue 6: Container Exits Immediately

### Symptoms
- `make up` fails quickly with error
- Container visible in `docker ps -a` but not in `docker ps`
- Exit code non-zero (usually 1, 137)

### Decision Tree

```
Check exit code:
├─ 137 (SIGKILL) → Problem: Out of memory or killed by system
│                   Solution: Increase QEMU_RAM or docker memory limits
│
├─ 1 (Generic error) → Check docker logs gnu-hurd-dev for cause
│                       Solution: Fix specific error
│
└─ Check container logs:
    docker logs gnu-hurd-dev
    (Look for error messages)
```

### Common Causes & Solutions

**Image not found:**
```bash
# Solution: Download image
scripts/setup-hurd-amd64.sh
# or enable auto-download
AUTO_DOWNLOAD_IMAGE=1 make up-volume
```

**Permission denied:**
```bash
# Solution: Fix permissions
chmod 755 entrypoint.sh
chmod 755 scripts/*.sh
```

**QEMU not found:**
```bash
# Solution: Install QEMU package
docker compose build --no-cache
```

**Out of memory (exit 137):**
```bash
# Solution: Increase memory
QEMU_RAM=8192 make up
```

**Entrypoint error:**
```bash
# Debug interactively
docker compose run --entrypoint /bin/bash gnu-hurd-dev
```

### Diagnostic Commands

```bash
# Check container exit status
docker ps -a | grep gnu-hurd-dev

# Get exit code
docker inspect gnu-hurd-dev --format='{{.State.ExitCode}}'

# View full error logs
docker logs gnu-hurd-dev

# Check image availability
docker images | grep gnu-hurd-docker

# Verify entrypoint
docker inspect gnu-hurd-dev | jq '.Config.Entrypoint'
```

### Solution Checklist

- [ ] Check logs: `docker logs gnu-hurd-dev`
- [ ] Image exists: `ls -lh images/debian-hurd-amd64.qcow2`
- [ ] Permissions: `chmod 755 entrypoint.sh scripts/*.sh`
- [ ] Memory limit: `QEMU_RAM=4096 make up`
- [ ] Rebuild image: `make build`
- [ ] Check QEMU: `docker run --rm ubuntu qemu-system-x86_64 --version`

### Prevention

- Always check logs after container exits
- Verify image exists before startup
- Set appropriate memory limits
- Use `make build` to ensure fresh image

---

## Issue 7: Out of Disk Space

### Symptoms
- "No space left on device" errors
- Docker operations failing
- Guest cannot write files

### Decision Tree

```
Check host disk:
├─ Host disk full → Problem: /var/lib/docker or / too large
│                    Solution: Clean up snapshots, old images
│
└─ Host disk OK → Check guest disk:
    docker exec gnu-hurd-dev df -h
    ├─ Guest disk full → Problem: /home or /tmp too large
    │                     Solution: Clean up guest files
    │
    └─ Guest disk OK → Unknown issue; check logs
```

### Diagnostic Commands

```bash
# Host disk usage
df -h /
df -h /var/lib/docker

# Docker image/volume usage
docker system df

# Guest disk usage
docker exec gnu-hurd-dev df -h
docker exec gnu-hurd-dev du -sh /home/*

# QEMU image size
ls -lh images/debian-hurd-amd64.qcow2

# Snapshots (if using)
qemu-img snapshot -l images/debian-hurd-amd64.qcow2
```

### Solution Checklist

**Guest disk full:**
- [ ] Clean /tmp: `docker exec gnu-hurd-dev rm -rf /tmp/*`
- [ ] Clean /home: Identify large files with `du -sh /home/*`
- [ ] Remove build artifacts: `docker exec gnu-hurd-dev make clean`
- [ ] Remove apt cache: `docker exec gnu-hurd-dev apt clean`

**Host disk full:**
- [ ] Remove unused images: `docker image prune -a`
- [ ] Remove unused volumes: `docker volume prune`
- [ ] Clean old snapshots: `qemu-img snapshot -d`
- [ ] Clear Docker system: `docker system prune --volumes`

### Prevention

- Monitor disk usage regularly
- Don't create multiple snapshots
- Clean up after large builds
- Use minimal host disk allocation

---

## Issue 8: Network Issues

### Symptoms
- Cannot ping from guest to host
- DNS resolution failing
- No internet access from guest
- Routing problems

### Decision Tree

```
Can you ping 10.0.2.2 (host)?
├─ NO → Problem: Guest network not initialized
│        Solution: Check network device, restart container
│
└─ YES → Can you ping 8.8.8.8?
    ├─ NO → Problem: Routing or DNS
    │        Solution: Check default gateway, DNS config
    │
    └─ YES → Can you resolve hostnames?
        ├─ NO → Problem: DNS resolution
        │        Solution: Update /etc/resolv.conf
        │
        └─ YES → Network functional!
```

### Diagnostic Commands

```bash
# From host to guest network
docker exec gnu-hurd-dev ping -c 3 10.0.2.2

# From guest to external
docker exec gnu-hurd-dev ping -c 3 8.8.8.8

# DNS resolution
docker exec gnu-hurd-dev nslookup google.com
docker exec gnu-hurd-dev cat /etc/resolv.conf

# Network config
docker exec gnu-hurd-dev ifconfig
docker exec gnu-hurd-dev route -n

# QEMU network setup
docker exec gnu-hurd-dev netstat -tlnp
```

### Solution Checklist

- [ ] Verify network device: `ifconfig` shows eth0 or e1000
- [ ] Check IP address: Should be 10.0.2.x
- [ ] Gateway accessible: `ping 10.0.2.2` should work
- [ ] DNS configured: `cat /etc/resolv.conf` has nameserver
- [ ] Update DNS: `echo nameserver 8.8.8.8 > /etc/resolv.conf`
- [ ] Restart network: `service networking restart`
- [ ] Check QEMU args: Verify `QEMU_NIC` setting

### Prevention

- Verify network early: `docker exec gnu-hurd-dev ping 10.0.2.2`
- Use stable network device (e1000)
- Keep DNS configuration simple
- Monitor network in logs

---

## General Best Practices

### Before Reporting an Issue

1. Collect diagnostic information:
   ```bash
   docker logs gnu-hurd-dev > logs/container.log
   docker inspect gnu-hurd-dev > logs/inspect.json
   make lint
   make validate
   ```

2. Try basic solutions:
   - Clean restart: `make down && make up`
   - Rebuild image: `make build`
   - Check resources: `docker stats gnu-hurd-dev`

3. Check related documentation:
   - [COMMON-ISSUES.md](COMMON-ISSUES.md)
   - [SSH-ISSUES.md](SSH-ISSUES.md)
   - [OPTIMIZATION-2025.md](../02-ARCHITECTURE/qemu/OPTIMIZATION-2025.md)

### Creating Snapshots for Recovery

```bash
# Create snapshot before testing
docker exec gnu-hurd-dev qemu-img snapshot -c pre-test

# List snapshots
docker exec gnu-hurd-dev qemu-img snapshot -l

# Revert to snapshot
docker exec gnu-hurd-dev qemu-img snapshot -a pre-test
```

### Emergency Recovery

If VM is completely broken:

```bash
# Reset to clean state
make down
scripts/setup-hurd-amd64.sh  # Redownload image
make build                    # Rebuild container
make up                       # Start fresh
```

---

## Escalation Path

**Still stuck?**

1. Review [COMMON-ISSUES.md](COMMON-ISSUES.md) for known issues
2. Check [docs/07-RESEARCH-AND-LESSONS/](../07-RESEARCH-AND-LESSONS/) for research notes
3. Search existing GitHub issues
4. Create detailed issue report with:
   - Output from `docker logs gnu-hurd-dev`
   - `docker inspect gnu-hurd-dev` (JSON)
   - `make validate` results
   - Your configuration (QEMU_RAM, QEMU_SMP, etc.)
   - Host details (OS, CPU, RAM, Docker version)

---

## Related Documentation

- [COMMON-ISSUES.md](COMMON-ISSUES.md) - Specific known issues
- [SSH-ISSUES.md](SSH-ISSUES.md) - SSH-specific troubleshooting
- [FSCK-ERRORS.md](FSCK-ERRORS.md) - Filesystem error details
- [docs/02-ARCHITECTURE/OPTIMIZATION-2025.md](../02-ARCHITECTURE/qemu/OPTIMIZATION-2025.md) - Performance tuning
- [docs/03-CONFIGURATION/RESOURCE-SIZING.md](../03-CONFIGURATION/RESOURCE-SIZING.md) - Resource allocation
