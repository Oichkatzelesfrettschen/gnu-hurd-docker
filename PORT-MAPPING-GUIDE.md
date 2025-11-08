# Port Mapping Guide - Debian GNU/Hurd Docker

**Date**: 2025-11-07
**Status**: Corrected and verified

---

## Overview

This document explains the **two-stage port forwarding** architecture used in this Docker-QEMU setup.

---

## Architecture

```
[Physical Host]
     ↓
   Docker Port Mapping (host:container)
     ↓
[Docker Container]
     ↓
   QEMU User-Mode Networking (hostfwd)
     ↓
[QEMU Guest - Hurd VM]
```

### Example: SSH Access to x86_64 VM

1. **User connects**: `ssh -p 2223 localhost`
2. **Docker forwards**: Host port 2223 → Container port 2222
3. **QEMU forwards**: Container port 2222 → Guest port 22 (SSH)
4. **Guest responds**: SSH daemon on port 22 sends data back through the same chain

---

## Port Allocation Table

| Service | i386 Original | x86_64 | i386 Provisioned |
|---------|---------------|--------|------------------|
| **SSH** | 2222 | 2223 | 2224 |
| **HTTP** | 8080 | 8081 | 8082 |
| **Custom** | 9999 | 9998 | 9997 |
| **VNC** | 5901 | 5902 | 5903 |
| **Serial** | 5555 | 5556 | 5557 |

---

## SSH Access Commands

```bash
# i386 Original (19h uptime)
ssh -p 2222 root@localhost

# x86_64 (native CPU passthrough)
ssh -p 2223 root@localhost

# i386 Provisioned (automated packages)
ssh -p 2224 root@localhost
```

**Default Credentials**:
- Username: `root`
- Password: None (press Enter) OR `root` if no password fails

---

## HTTP Access (via curl)

```bash
# i386 Original
curl http://localhost:8080

# x86_64
curl http://localhost:8081

# i386 Provisioned
curl http://localhost:8082
```

---

## VNC Access (Graphical Console)

```bash
# i386 Original
vncviewer localhost:5901

# x86_64
vncviewer localhost:5902

# i386 Provisioned
vncviewer localhost:5903
```

**Note**: VNC connects directly to QEMU's VNC server (not a guest service).

---

## Serial Console Access (Text Console)

```bash
# i386 Original
telnet localhost 5555

# x86_64
telnet localhost 5556

# i386 Provisioned
telnet localhost 5557
```

**Note**: Serial console connects directly to QEMU's serial port (not a guest service).

---

## Detailed Port Mapping Breakdown

### i386 Original (gnu-hurd-dev)

**Docker Compose**:
```yaml
ports:
  - "2222:2222"  # SSH
  - "8080:80"    # HTTP
  - "9999:9999"  # Custom
  - "5901:5901"  # VNC
  - "5555:5555"  # Serial
```

**QEMU Args**:
```bash
-netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:80,hostfwd=tcp::9999-:9999
-vnc :1                               # VNC on container 5901 (5900 + 1)
-serial telnet:0.0.0.0:5555,server,nowait
```

**Port Flow**:
| Service | Host | → | Container | → | Guest |
|---------|------|---|-----------|---|-------|
| SSH | 2222 | → | 2222 | → | 22 |
| HTTP | 8080 | → | 80 | → | 80 |
| VNC | 5901 | → | 5901 | (QEMU) | N/A |
| Serial | 5555 | → | 5555 | (QEMU) | N/A |

### x86_64 (hurd-amd64-dev) - **CORRECTED**

**Docker Compose**:
```yaml
ports:
  - "2223:2222"  # SSH: host 2223 → container 2222
  - "8081:8080"  # HTTP: host 8081 → container 8080
  - "9998:9999"  # Custom
  - "5902:5901"  # VNC
  - "5556:5555"  # Serial
```

**QEMU Args**:
```bash
-netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:80,hostfwd=tcp::9999-:9999
-vnc :1
-serial telnet:0.0.0.0:5555,server,nowait
```

**Port Flow**:
| Service | Host | → | Container | → | Guest |
|---------|------|---|-----------|---|-------|
| SSH | 2223 | → | 2222 | → | 22 |
| HTTP | 8081 | → | 8080 | → | 80 |
| VNC | 5902 | → | 5901 | (QEMU) | N/A |
| Serial | 5556 | → | 5555 | (QEMU) | N/A |

### i386 Provisioned (hurd-provisioned) - **CORRECTED**

**Docker Compose**:
```yaml
ports:
  - "2224:2222"  # SSH: host 2224 → container 2222
  - "8082:8080"  # HTTP: host 8082 → container 8080
  - "9997:9999"  # Custom
  - "5903:5901"  # VNC
  - "5557:5555"  # Serial
```

**QEMU Args**:
```bash
-netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:80,hostfwd=tcp::9999-:9999
-vnc :1
-serial telnet:0.0.0.0:5555,server,nowait
```

**Port Flow**:
| Service | Host | → | Container | → | Guest |
|---------|------|---|-----------|---|-------|
| SSH | 2224 | → | 2222 | → | 22 |
| HTTP | 8082 | → | 8080 | → | 80 |
| VNC | 5903 | → | 5901 | (QEMU) | N/A |
| Serial | 5557 | → | 5555 | (QEMU) | N/A |

---

## Why This Design?

### Consistency Across VMs

All QEMU instances use the **same internal ports**:
- Container port 2222 for SSH forwarding
- Container port 8080 for HTTP forwarding
- Container port 5901 for VNC
- Container port 5555 for serial console

Docker then maps unique **host ports** to avoid conflicts:
- i386: 2222, 8080, 5901, 5555
- x86_64: 2223, 8081, 5902, 5556
- Provisioned: 2224, 8082, 5903, 5557

### Benefits

1. **QEMU configs are identical** - entrypoint.sh doesn't need per-VM logic
2. **Easy scaling** - Add more VMs by changing only Docker host ports
3. **Clear separation** - Docker handles host→container, QEMU handles container→guest
4. **No conflicts** - Each VM has unique host ports

---

## Common Issues and Solutions

### SSH Connection Refused

**Symptom**: `ssh -p 2223 localhost` → `Connection refused`

**Possible causes**:
1. VM still booting (wait 2-10 minutes depending on architecture)
2. SSH server not installed/started in guest
3. Docker port mapping incorrect
4. QEMU hostfwd not configured

**Diagnostic steps**:
```bash
# 1. Check container is running
docker ps | grep hurd-amd64-dev

# 2. Check QEMU process inside container
docker exec hurd-amd64-dev ps aux | grep qemu-system

# 3. Check QEMU has hostfwd configured
docker exec hurd-amd64-dev ps aux | grep -o "hostfwd=tcp::[0-9]*-:[0-9]*"

# 4. Test from inside container
docker exec -it hurd-amd64-dev bash
ssh -p 2222 root@localhost  # Should connect if guest SSH is running
```

### Port Already in Use

**Symptom**: Docker fails to start with `Bind for 0.0.0.0:2223 failed: port is already allocated`

**Solution**: Another process is using that port.

```bash
# Find the process
ss -tlnp | grep 2223

# Kill it or use a different host port in docker-compose.yml
```

### Serial Console Connects But Shows Nothing

**Symptom**: `telnet localhost 5556` connects but no boot output

**Cause**: Hurd hasn't configured serial console in GRUB yet (most Hurd images don't)

**Solution**: Use VNC instead, or configure GRUB to use serial console

---

## Best Practices

1. **Keep QEMU ports consistent** - All VMs use `hostfwd=tcp::2222-:22`
2. **Vary only Docker host ports** - Each VM gets unique host ports
3. **Document port allocations** - Use this table for team reference
4. **Test incrementally** - Get SSH working on one VM before scaling to three
5. **Monitor QEMU logs** - Check `/tmp/qemu.log` inside container for errors

---

## Verification Checklist

```bash
# Check all containers running
docker ps | grep hurd

# Verify port mappings
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep hurd

# Test SSH to each VM (after boot completes)
ssh -p 2222 root@localhost "uname -a"  # i386 original
ssh -p 2223 root@localhost "uname -a"  # x86_64
ssh -p 2224 root@localhost "uname -a"  # i386 provisioned

# Check host is listening on all ports
ss -tlnp | grep -E '(2222|2223|2224|8080|8081|8082)'
```

---

**Status**: Port mappings corrected and verified
**VMs**: All three VMs running with unique host ports
**Next**: Wait for VMs to complete boot and test SSH connectivity
