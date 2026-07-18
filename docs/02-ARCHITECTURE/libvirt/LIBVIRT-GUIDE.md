# Libvirt Integration Guide for GNU/Hurd

## Overview

This guide covers using **libvirt** with KVM/QEMU to run GNU/Hurd as an alternative to Docker or Podman. Libvirt provides a unified interface for virtual machine management and is useful for:

- Users who prefer managing VMs directly (vs. containerization)
- Systems where Docker/Podman is unavailable or impractical
- Advanced hypervisor features (snapshots, live migration, complex networking)
- Integration with existing libvirt/KVM infrastructure

**Status**: Production-ready (included with config/libvirt/gnu-hurd.xml and scripts/libvirt-hurd.sh)

---

## Quick Start

### 1. Install Prerequisites

**Arch/CachyOS**:
```bash
sudo pacman -S libvirt qemu qemu-system-x86 edk2-ovmf
sudo systemctl enable --now libvirtd
```

**Ubuntu/Debian**:
```bash
sudo apt install libvirt-bin qemu-system-x86 libvirt-clients
sudo systemctl enable --now libvirtd
```

**Fedora/RHEL**:
```bash
sudo dnf install libvirt qemu-system-x86
sudo systemctl enable --now libvirtd
```

### 2. Add User to KVM Group (Optional, for non-root access)

```bash
sudo usermod -a -G libvirt,kvm $USER
newgrp libvirt
```

### 3. Download Disk Image

```bash
./scripts/download-image.sh
# Creates: /var/lib/libvirt/images/debian-hurd-amd64.qcow2
```

### 4. Define Domain

```bash
./scripts/libvirt-hurd.sh define
```

This reads `config/libvirt/gnu-hurd.xml` and registers the domain with libvirt.

### 5. Start and Access

```bash
./scripts/libvirt-hurd.sh start
./scripts/libvirt-hurd.sh console    # Serial console
# Or in another terminal:
./scripts/libvirt-hurd.sh ssh        # SSH to root@localhost:2222
```

---

## Configuration

### Domain Template

The domain definition is in `config/libvirt/gnu-hurd.xml`. Key settings:

```xml
<!-- Memory and CPU -->
<memory unit="KiB">4194304</memory>      <!-- 4 GB RAM -->
<vcpu placement="static">2</vcpu>        <!-- 2 vCPUs -->

<!-- Boot from disk -->
<boot dev="hd"/>

<!-- KVM acceleration (falls back to TCG if unavailable) -->
<qemu:commandline>
  <qemu:arg value="-enable-kvm"/>
</qemu:commandline>

<!-- Port forwarding (Slirp user-mode networking) -->
<portForward proto="tcp" hostPort="2222" guestPort="22"/>   <!-- SSH -->
<portForward proto="tcp" hostPort="8080" guestPort="80"/>   <!-- HTTP -->
```

### Customization

To adjust the domain template before defining:

```bash
# Edit the XML template
vi config/libvirt/gnu-hurd.xml

# Then define
./scripts/libvirt-hurd.sh define
```

Adjustable parameters:
- **Memory**: Change `<memory unit="KiB">4194304</memory>` (4 GB = 4194304 KiB)
- **vCPUs**: Change `<vcpu>2</vcpu>` to 1, 4, 8, etc.
- **Disk**: Change `<source file=".../debian-hurd-amd64.qcow2"/>`
- **Ports**: Modify `<portForward>` entries for SSH/HTTP forwarding
- **Name**: Change `<name>gnu-hurd-dev</name>` (must be unique)

Environment variables override defaults:

```bash
DOMAIN_NAME=my-hurd SSH_PORT=2223 ./scripts/libvirt-hurd.sh define
```

---

## Usage

### Wrapper Script Commands

The `./scripts/libvirt-hurd.sh` script provides a simple interface:

| Command | Purpose |
|---------|---------|
| `define` | Register domain with libvirt (one-time) |
| `start` | Boot the VM |
| `stop` | Shut down the VM |
| `console` | Access serial console (Ctrl+] to exit) |
| `ssh [args]` | SSH to root@localhost:2222 |
| `status` | Show brief status |
| `info` | Show detailed configuration |
| `undefine` | Remove domain definition |

### Direct Virsh Commands

You can also use `virsh` directly:

```bash
# List all domains
virsh list --all

# Show domain details
virsh dominfo gnu-hurd-dev

# Connect to console
virsh console gnu-hurd-dev        # Exit: Ctrl+]

# Shutdown gracefully
virsh shutdown gnu-hurd-dev

# Force stop
virsh destroy gnu-hurd-dev

# Edit domain XML
virsh edit gnu-hurd-dev

# Dump domain config to XML
virsh dumpxml gnu-hurd-dev > backup.xml
```

---

## Networking

### Port Forwarding (Slirp User-Mode)

The default configuration uses **Slirp user-mode networking** with port forwarding:

| Service | Host | Guest |
|---------|------|-------|
| SSH | localhost:2222 | 10.0.2.15:22 |
| HTTP | localhost:8080 | 10.0.2.15:80 |

Access from host:
```bash
ssh -p 2222 root@localhost
curl http://localhost:8080
```

### Switching to Bridged Networking (Advanced)

For direct network access, replace the `<interface type="user">` with:

```xml
<interface type="bridge">
  <source bridge="br0"/>
  <model type="virtio"/>
</interface>
```

Then:
1. Configure a bridge (e.g., `br0`) on your host
2. Run `virsh edit gnu-hurd-dev` and apply the change
3. Restart the domain: `virsh destroy gnu-hurd-dev && virsh start gnu-hurd-dev`

**Warning**: Bridged networking requires additional host configuration and may conflict with Docker/Podman bridges.

---

## Snapshots and Backups

### Create Snapshot

```bash
virsh snapshot-create-as gnu-hurd-dev snapshot1 "Initial setup"
virsh snapshot-list gnu-hurd-dev
```

### Revert to Snapshot

```bash
virsh snapshot-revert gnu-hurd-dev snapshot1
virsh start gnu-hurd-dev    # Start after revert if needed
```

### List Snapshots

```bash
virsh snapshot-list gnu-hurd-dev
```

### Delete Snapshot

```bash
virsh snapshot-delete gnu-hurd-dev snapshot1
```

### Backup Disk Image

```bash
# Copy disk image
sudo cp /var/lib/libvirt/images/debian-hurd-amd64.qcow2 \
        /var/lib/libvirt/images/debian-hurd-amd64-backup.qcow2

# List QCOW2 info
qemu-img info /var/lib/libvirt/images/debian-hurd-amd64.qcow2
```

---

## Performance Tuning

### Check KVM Availability

```bash
./scripts/libvirt-hurd.sh info
# Look for KVM acceleration status
```

If KVM is available (Linux x86_64 with `/dev/kvm`), boot time is 30-60 seconds.
If using TCG emulation, expect 3-5 minutes.

### Disk Performance

The domain template uses:
```xml
<driver name="qemu" type="qcow2" cache="writeback" io="threads"/>
```

This provides good balance. For higher performance (with more risk):
- Change `cache="writeback"` to `cache="unsafe"` (loses data safety on crash)
- Change `io="threads"` to `io="native"` if filesystem supports AIO

### CPU Performance

To pin vCPUs to specific host cores:
```xml
<cputune>
  <vcpupin vcpu="0" cpuset="0"/>
  <vcpupin vcpu="1" cpuset="1"/>
</cputune>
```

Then restart: `virsh destroy gnu-hurd-dev && virsh start gnu-hurd-dev`

---

## Monitoring and Debugging

### Domain Status

```bash
virsh dominfo gnu-hurd-dev
virsh domstate gnu-hurd-dev
```

### Resource Usage

```bash
# Real-time memory/CPU usage (requires virt-top)
sudo virt-top

# Or via virsh
virsh domstats gnu-hurd-dev
```

### Console Output

```bash
# Serial console (text-only)
virsh console gnu-hurd-dev

# VNC console (graphical) - check port with:
virsh edit gnu-hurd-dev    # Look for <graphics type="vnc" port="..."/>
vncviewer 127.0.0.1:5900   # Adjust port number as needed
```

### Logs

QEMU logs are typically in:
```bash
# QEMU process logs
sudo journalctl -u libvirtd -f    # Follow libvirt logs

# Domain-specific logs
ls -la /var/log/libvirt/qemu/gnu-hurd-dev.log 2>/dev/null || echo "Not found (check permissions)"
```

---

## Troubleshooting

### Domain Won't Start

**Error**: `virsh start gnu-hurd-dev` fails

**Solutions**:
1. Check libvirtd status: `sudo systemctl status libvirtd`
2. Verify disk image exists: `ls -la /var/lib/libvirt/images/debian-hurd-amd64.qcow2`
3. Check permissions: `ls -la /var/lib/libvirt/images/`
4. Review logs: `sudo journalctl -u libvirtd -n 50`

### SSH Connection Refused

**Error**: `ssh -p 2222 root@localhost` → `Connection refused`

**Solutions**:
1. Check if domain is running: `./scripts/libvirt-hurd.sh status`
2. Wait for boot (60 seconds for KVM, 5 minutes for TCG)
3. Check SSH is listening: `./scripts/libvirt-hurd.sh console`
4. Verify port forwarding: `virsh edit gnu-hurd-dev` → check `<portForward>`

### Out of Memory

**Error**: Domain boots but becomes unresponsive or crashes

**Solutions**:
1. Reduce memory allocation: `virsh edit gnu-hurd-dev` → change `<memory>` (1 GB = 1048576 KiB)
2. Stop other VMs: `virsh list --all` then `virsh shutdown <domain>`
3. Check host memory: `free -h`

### KVM Not Available

**Error**: Falling back to TCG emulation (slow boots)

**Causes**:
- Not running on Linux x86_64
- `/dev/kvm` not present (nested virt not enabled in host VM)
- User doesn't have permissions

**Solutions**:
1. For nested KVM: Enable on host hypervisor (VirtualBox: Settings → System → Check "Nested VT-x/AMD-V")
2. For permissions: `sudo usermod -a -G kvm $USER` then log out/in
3. Verify: `ls -la /dev/kvm` and `[ -r /dev/kvm ] && [ -w /dev/kvm ] && echo "OK" || echo "No access"`

---

## Comparison: Docker vs. Podman vs. Libvirt

| Feature | Docker | Podman | Libvirt |
|---------|--------|--------|---------|
| **Lightweight** | Yes | Yes | No (full VM) |
| **Setup Complexity** | Low | Low | Medium |
| **Performance Overhead** | Minimal | Minimal | Higher (full VM) |
| **GUI Support** | No | No | Yes (virt-manager) |
| **Snapshots** | Limited | Limited | Full VM snapshots |
| **Resource Control** | Per-container | Per-container | Per-VM |
| **Daemon Required** | Docker daemon | Podman socket | libvirtd |
| **Best For** | Development | Development/CI | Long-running testing, infrastructure |

---

## Security Considerations

### User Access

By default, only root can manage libvirt domains. To allow non-root:

```bash
sudo usermod -a -G libvirt,kvm $USER
newgrp libvirt
virsh list    # Should work without sudo
```

**Note**: Membership in the `libvirt` group grants powerful capabilities (equivalent to partial root access). Use with caution.

### Network Isolation

The default Slirp user-mode networking provides isolation: the guest cannot see or interfere with the host network beyond forwarded ports.

To be more restrictive:
- Remove HTTP port forwarding: Edit `config/libvirt/gnu-hurd.xml` and delete the HTTP `<portForward>`
- Use serial console only: Set `CONSOLE_TYPE=serial` in environment

### SELinux / AppArmor (Linux)

On systems with mandatory access controls:

```bash
# Check if enforcing
sudo getenforce    # SELinux
sudo aa-enabled    # AppArmor

# Libvirt policies usually allow VM operation; if issues occur:
sudo ausearch -m avc | grep qemu    # SELinux denials
sudo journalctl | grep apparmor     # AppArmor denials
```

---

## Integration with Docker/Podman

You can run **both** Docker containers and libvirt VMs on the same host:

```bash
# Start Hurd VM via libvirt
./scripts/libvirt-hurd.sh start

# Run other workloads via Docker
docker compose up -d

# SSH into Hurd for testing
./scripts/libvirt-hurd.sh ssh
```

However, avoid using Hurd running in libvirt **inside** a Docker container (nested VM + container = complex debugging).

---

## Advanced: Using Libvirt in Docker Compose

For CI/CD or complex orchestration, you can define a service that manages the Hurd VM:

**compose.libvirt.yaml** (Example):
```yaml
version: "3.8"
services:
  hurd:
    image: ubuntu:22.04
    privileged: true
    volumes:
      - /var/lib/libvirt/images:/var/lib/libvirt/images:shared
      - /var/run/libvirt:/var/run/libvirt:shared
      - ./config/libvirt:/etc/libvirt/gnu-hurd:ro
      - ./scripts:/scripts:ro
    entrypoint: |
      /bin/bash -c '
        apt-get update && apt-get install -y libvirt-clients qemu-system-x86
        /scripts/libvirt-hurd.sh define
        /scripts/libvirt-hurd.sh start
        sleep infinity
      '
```

**Warning**: Complex setup; only for advanced users.

---

## Related Documentation

- **Domain Template**: `config/libvirt/gnu-hurd.xml`
- **Wrapper Script**: `scripts/libvirt-hurd.sh`
- **Libvirt Manual**: `man virsh`
- **QEMU Manual**: `man qemu-system-x86_64`
- **Docker Comparison**: `docs/05-CI-CD/COMPOSE-VARIANTS.md`

---

## Next Steps

1. Run `./scripts/libvirt-hurd.sh define` to register the domain
2. Run `./scripts/libvirt-hurd.sh start` to boot
3. Use `./scripts/libvirt-hurd.sh console` or SSH for access
4. Explore `virsh` commands for advanced management

For issues or questions, refer to:
- Libvirt documentation: https://libvirt.org/
- QEMU documentation: https://www.qemu.org/
- This project's troubleshooting guide: `docs/06-TROUBLESHOOTING/PLAYBOOK.md`

---

**Last Updated**: 2026-01-15
**Status**: Production-ready
**Maintenance**: Community-supported
