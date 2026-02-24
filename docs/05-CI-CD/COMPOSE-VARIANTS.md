# Docker Compose & Podman Compose Variants Guide

## Overview

This project supports multiple compose frontends across different platforms and runtimes. Understanding the differences between variants helps you choose the right tool for your environment and workflow.

## Compose Variants

### Docker Compose v2 (Recommended)

**What it is**: The modern Docker Compose implementation integrated into the Docker CLI (`docker compose`).

**Installation**:
```bash
# Included with Docker Desktop 3.0+
docker --version    # Should be >=20.10
docker compose version
```

**Usage**:
```bash
docker compose up -d
docker compose -f docker-compose.yml -f docker-compose.kvm.yml up -d
docker compose logs -f
docker compose down
```

**Characteristics**:
- **Implementation**: Go-based, built-in Docker CLI command
- **Installation**: Ships with Docker Desktop (macOS, Windows) or Docker Engine (Linux)
- **Performance**: Faster than v1 (rewritten from scratch)
- **Features**: Supports all modern docker-compose.yml syntax (version 3.8+)
- **Cross-platform**: Available on Linux, macOS (via Docker Desktop), Windows (via Docker Desktop + WSL2)
- **Defaults**: Automatically uses available hardware acceleration (VT-x/AMD-V on Linux, Hyper-V on Windows)

**Compatibility Matrix**:
| Platform | Status | Notes |
|----------|--------|-------|
| Linux x86_64 | Full | Recommended. Supports KVM via /dev/kvm |
| Linux ARM64 | Full | TCG mode. Can use Podman instead |
| macOS x86_64 | Full | Via Docker Desktop with Intel backend |
| macOS ARM64 | Full | Via Docker Desktop with Apple Silicon backend |
| Windows 10/11 x86_64 | Full | Via Docker Desktop + WSL2 |
| BSD | Limited | Experimental; not officially supported |

**When to use**:
- Primary development workflow
- CI/CD pipelines (GitHub Actions, GitLab CI)
- Docker Desktop users
- Production deployments

---

### Docker Compose v1 (Legacy)

**What it is**: The original Python-based Docker Compose tool (`docker-compose` standalone).

**Installation**:
```bash
# Standalone binary (deprecated)
sudo pip install docker-compose

# Or via package manager (some distros still provide it)
sudo apt install docker-compose     # Ubuntu/Debian
sudo pacman -S docker-compose       # Arch
```

**Usage**:
```bash
docker-compose up -d
docker-compose -f docker-compose.yml -f docker-compose.kvm.yml up -d
docker-compose logs -f
docker-compose down
```

**Characteristics**:
- **Implementation**: Python-based
- **Status**: Deprecated (no new releases since 2021)
- **Performance**: Slower than v2 (Python overhead)
- **Features**: Supports docker-compose.yml version 3.x
- **Maintenance**: Security fixes only; no new features
- **Installation**: Requires Python 3.6+ and pip

**Compatibility Matrix**:
| Platform | Status | Notes |
|----------|--------|-------|
| Linux x86_64 | Full | Still works; maintained for backward compatibility |
| Linux ARM64 | Full | Works but slower than v2 |
| macOS (x86_64 + ARM64) | Partial | Can be installed, but Docker Desktop includes v2 |
| Windows | Partial | Can be installed in WSL2, but Docker Desktop includes v2 |
| BSD | Limited | May work with Python interpreter |

**When to use**:
- Legacy projects that explicitly require v1
- Environments without Python 3 runtime available
- Minimal installations where smaller size matters

**Deprecation Notice**: This variant is no longer maintained. Migrate to v2 or podman-compose.

---

### Podman Compose

**What it is**: A Python-based compose tool for Podman that mimics Docker Compose API.

**Installation**:
```bash
# Linux (apt)
sudo apt install podman-compose

# Linux (pip)
pip3 install podman-compose

# macOS (brew)
brew install podman-compose

# All platforms
pip3 install --user podman-compose
```

**Usage**:
```bash
podman-compose up -d
podman-compose -f docker-compose.yml -f docker-compose.bind.yml up -d
podman-compose logs -f
podman-compose down
```

**Characteristics**:
- **Implementation**: Python-based wrapper around Podman
- **Compatibility**: ~90% compatible with Docker Compose syntax
- **Daemonless**: No background daemon required
- **Rootless**: Can run without root privileges (major security advantage)
- **Performance**: Comparable to docker-compose v1 (Python-based)
- **Features**: Supports Podman-specific features (pods, etc.)

**Compatibility Matrix**:
| Platform | Status | Notes |
|----------|--------|-------|
| Linux x86_64 (daemon) | Full | Best choice for rootless containers |
| Linux x86_64 (rootless) | Full | Recommended for security-conscious environments |
| Linux ARM64 | Full | Native support; TCG mode for QEMU |
| macOS | Partial | Requires Podman Machine; slower than Docker Desktop |
| Windows | Partial | Requires WSL2 + Podman; slower than Docker Desktop |
| BSD | Limited | Not officially supported |

**When to use**:
- Rootless container execution (security requirement)
- Projects that don't require Docker daemon
- ARM64 Linux hosts (direct support without Docker)
- Kubernetes-focused workflows (Podman pod feature)
- Decentralized container management

---

### Libvirt + QEMU (Alternative VM Management)

**What it is**: Full virtual machine management via libvirt, running QEMU/KVM as the hypervisor.

**Installation**:
```bash
# Linux (libvirt daemon + tools)
sudo apt install libvirt-bin qemu-system-x86    # Ubuntu/Debian
sudo pacman -S libvirt qemu-system-x86          # Arch/CachyOS
sudo dnf install libvirt qemu-system-x86        # Fedora/RHEL

# Enable and start daemon
sudo systemctl enable --now libvirtd
```

**Usage**:
```bash
# Option 1: Direct libvirt management
./scripts/libvirt-hurd.sh define
./scripts/libvirt-hurd.sh start
virsh console gnu-hurd-dev

# Option 2: Docker Compose orchestration (experimental)
docker compose -f docker-compose.libvirt.yml up -d
```

**Characteristics**:
- **Implementation**: Hypervisor-based (full VM, not containerized)
- **Control Mechanism**: libvirt daemon + virsh CLI
- **Daemonless**: No (requires libvirtd running)
- **Overhead**: Higher (full VM footprint vs. container)
- **Features**: Full VM snapshots, live migration, complex networking
- **Acceleration**: KVM (30-60s boot) or TCG fallback (3-5min boot)

**Compatibility Matrix**:
| Platform | Status | Notes |
|----------|--------|-------|
| Linux x86_64 (KVM) | Full | Best performance. Native KVM acceleration |
| Linux x86_64 (TCG) | Full | Slower but functional. For nested VMs |
| Linux ARM64 | Full | TCG only. No native ARM64 KVM for x86_64 guests |
| macOS | Limited | Requires special setup (UTM or similar); not recommended |
| Windows | Limited | Requires Hyper-V + nested virt; complex setup |
| BSD | Not Supported | Libvirt focus is Linux and Xen hypervisors |

**When to use**:
- Need full VM features (snapshots, live migration)
- Integration with existing libvirt/KVM infrastructure
- Advanced hypervisor management and monitoring
- Long-running testing or infrastructure use cases
- Direct VM management without containerization
- When Docker/Podman not available or impractical

**When NOT to use**:
- Simple one-off testing (Docker/Podman is lighter)
- Need lightweight containers (full VM has overhead)
- Limited disk/memory (containers use less resources)
- macOS or Windows (requires complex setup)

---

## Detailed Comparison

### Installation & Setup Complexity

| Aspect | Docker v2 | Docker v1 | Podman Compose | Libvirt |
|--------|-----------|-----------|-----------------|---------|
| Installation | Built-in (v20.10+) | `pip install docker-compose` | `apt install` or `pip install` | `apt install libvirt qemu` |
| Setup time | None (ship ready) | 2-5 minutes | 5-10 minutes | 10-15 minutes |
| Dependencies | Docker | Docker + Python 3.6+ | Podman + Python 3.6+ | libvirtd + QEMU + virsh |
| Post-install | Nothing | May need `/usr/local/bin` | May need PATH setup | systemctl enable libvirtd |
| Uninstall | N/A | `pip uninstall` | `pip uninstall` or `apt remove` | `apt remove libvirt` |

### Performance Characteristics

**Startup Time**:
```
Docker Compose v2:     ~200-300ms
Docker Compose v1:     ~800-1200ms (Python startup overhead)
Podman Compose:        ~800-1200ms (Python startup overhead)
Libvirt (virsh):       ~100-150ms (CLI launch)
Libvirt (VM boot):     30-60s (KVM) or 3-5min (TCG)
```

**Memory Usage**:
```
Docker Compose v2:     ~15-20MB per operation
Docker Compose v1:     ~30-50MB (Python interpreter)
Podman Compose:        ~30-50MB (Python interpreter)
Libvirt (virsh):       ~5-10MB (CLI only)
Libvirt (running VM):  512MB-4GB (VM guest footprint, configurable)
```

**Disk Space**:
```
Docker Compose v2:     ~5MB (included with Docker)
Docker Compose v1:     ~50-100MB (Python + deps)
Podman Compose:        ~50-100MB (Python + deps)
Libvirt (tools):       ~100-200MB (libvirt + QEMU)
Libvirt (disk image):  500MB-20GB (QCOW2 image file)
```

### Feature Support

| Feature | Docker v2 | Docker v1 | Podman Compose | Libvirt |
|---------|-----------|-----------|-----------------|---------|
| Basic services | ✓ | ✓ | ✓ | ✓ (VM mgmt) |
| Networks | ✓ | ✓ | ✓ | ✓ (user/bridge) |
| Volumes | ✓ | ✓ | ✓ | ✓ (disks) |
| Snapshots | ✗ | ✗ | ✗ | ✓ (full VM) |
| Live migration | ✗ | ✗ | ✗ | ✓ |
| Health checks | ✓ | ✓ | ✓ | ⚠ (manual) |
| Resource limits | ✓ | ✓ | ✓ | ✓ |
| GPU support | ✓ | ✓ | ✓ | ✓ |
| Console access | ✗ | ✗ | ✗ | ✓ (VNC/serial) |
| Compose file version | 3.8+ | 3.x | 3.x | N/A (YAML templates) |
| Rootless mode | ⚠ (v20.10+) | ⚗ (unsupported) | ✓ (native) | ⚠ (sudo required) |
| Graphical mgmt | ✗ | ✗ | ✗ | ✓ (virt-manager) |

### Acceleration Mode Support

#### Docker Compose v2

**Linux x86_64 (KVM)**:
```bash
docker compose -f docker-compose.yml -f docker-compose.kvm.yml up -d
# Automatically detects /dev/kvm and enables KVM acceleration
```

**Status**: ✓ Full support via /dev/kvm device passthrough

#### Docker Compose v1

**Linux x86_64 (KVM)**:
```bash
docker-compose -f docker-compose.yml -f docker-compose.kvm.yml up -d
# Works identically to v2
```

**Status**: ✓ Full support (syntax compatible)

#### Podman Compose

**Linux x86_64 (KVM)**:
```bash
podman-compose -f docker-compose.yml -f docker-compose.kvm.yml up -d
# Works but requires careful /dev/kvm permission setup
# May require: sudo chmod 666 /dev/kvm
```

**Status**: ✓ Supported (requires additional permissions for rootless)

**Rootless KVM**:
```bash
# For rootless Podman with KVM (Linux x86_64)
sudo sysctl kernel.unprivileged_userns_clone=1
podman machine set --cpus=2 --memory=4096
podman-compose up -d  # KVM auto-detected in Podman Machine
```

**Status**: ⚠ Supported via Podman Machine (macOS, Windows)

#### Libvirt + QEMU

**Linux x86_64 (KVM - Recommended)**:
```bash
./scripts/libvirt-hurd.sh define
./scripts/libvirt-hurd.sh start
# KVM automatically enabled if /dev/kvm is available
```

**Status**: ✓ Full support (auto-detects KVM via -enable-kvm flag in domain XML)

**Linux x86_64 (TCG Fallback)**:
```bash
./scripts/libvirt-hurd.sh start
# Falls back to TCG if KVM unavailable (nested VM scenario)
```

**Status**: ✓ Full support (automatic fallback, slower but reliable)

**Performance**:
- **KVM mode** (native x86_64): 30-60 second boot, 3.5-4.5 GHz effective CPU
- **TCG mode** (emulated): 3-5 minute boot, 0.5-1 GHz effective CPU

**Configuration**:
```xml
<!-- config/libvirt/gnu-hurd.xml - KVM flag -->
<qemu:commandline>
  <qemu:arg value="-enable-kvm"/>  <!-- Auto-detects; graceful fallback to TCG -->
</qemu:commandline>
```

---

## Platform-Specific Guidance

### Linux x86_64 (Recommended Environment)

**Best choice**: Docker Compose v2 (integrated, fast, full KVM support)

```bash
# Install Docker (if needed)
curl -fsSL https://get.docker.com | sh

# Verify installation
docker compose version    # Should show v2.x.x

# Use for development
docker compose -f docker-compose.yml -f docker-compose.kvm.yml up -d
```

**Alternative**: Podman Compose (if rootless container execution required)

```bash
# Install Podman
sudo apt install podman podman-compose

# Use rootless mode
podman-compose up -d
```

### Linux ARM64

**Best choice**: Podman Compose (native support, direct KVM on ARM64)

```bash
# Install Podman
sudo apt install podman podman-compose

# No need for Docker Desktop or special layers
podman-compose up -d
```

**Alternative**: Docker Desktop (via ARM64 VM), but slower

### macOS x86_64 & ARM64

**Best choice**: Docker Desktop → `docker compose` v2

```bash
# Install Docker Desktop from: https://www.docker.com/products/docker-desktop
# Then:
docker compose -f docker-compose.yml up -d
```

**Alternative**: Podman Desktop (if daemonless execution preferred)

```bash
# Install Podman Desktop from: https://podman-desktop.io/
podman-compose up -d  # Runs in Podman Machine VM
```

### Windows 10/11 x86_64

**Best choice**: Docker Desktop + WSL2 → `docker compose` v2

```bash
# 1. Install Windows Subsystem for Linux 2 (WSL2)
wsl --install

# 2. Install Docker Desktop for Windows
# Download from: https://www.docker.com/products/docker-desktop

# 3. Configure Docker Desktop to use WSL2 backend
# (GUI setting: Settings → Resources → WSL integration)

# 4. Open terminal in WSL2 and use normally
docker compose up -d
```

**Alternative**: Podman Desktop + WSL2

```bash
# Similar setup as Docker Desktop but with Podman
# Performance may be slower due to VM overhead
```

---

## Migration Path

### From docker-compose v1 to Docker Compose v2

```bash
# 1. Ensure Docker >=20.10 is installed
docker --version

# 2. Verify v2 is available
docker compose version

# 3. Update scripts to use "docker compose" instead of "docker-compose"
sed -i 's/docker-compose/docker compose/g' scripts/*.sh

# 4. Test with existing docker-compose.yml (no format changes needed)
docker compose up -d

# 5. Verify all services started correctly
docker compose ps
```

**Estimated time**: ~10 minutes
**Risk**: Very low (backward compatible syntax)
**Rollback**: Just reinstall docker-compose v1 if issues arise

### From Docker to Podman

```bash
# 1. Install Podman and podman-compose
sudo apt install podman podman-compose

# 2. Test basic Podman functionality
podman --version
podman-compose --version

# 3. Update container runtime script references (if any)
# Most docker-compose.yml files work unchanged with podman-compose

# 4. Start with non-critical services first
podman-compose -f docker-compose.yml up -d

# 5. Verify container startup and logs
podman-compose logs -f

# 6. Keep Docker installed for fallback during transition
```

**Estimated time**: ~30 minutes
**Risk**: Medium (some edge cases may not work identically)
**Rollback**: Switch back to `docker-compose` commands

---

## This Project's Strategy

This project uses a **Compose-native control plane** via `Makefile` + `compose*.yaml`.
Runtime selection is explicit with `CONTAINER_RUNTIME=docker|podman`; for Podman, pin `PODMAN_COMPOSE_PROVIDER=podman-compose`.

**Usage**:

```bash
make up       # TCG (compatible with all runtimes)
make up-kvm   # KVM overlay (Linux x86_64 host + /dev/kvm required)
make down
make logs
```

**Why this approach**:
- ✓ Works with any installed compose variant
- ✓ Runtime/provider is explicit and reproducible in CI
- ✓ Enables CI/CD to run on various platforms without changes
- ✓ Uses standardized Compose/Bake workflows instead of custom orchestration wrappers

---

## Troubleshooting

### "docker-compose: command not found"

**Solution**: Install Docker Compose v2 or v1

```bash
# Option 1: Docker v2 (recommended)
docker compose version  # If this fails, upgrade Docker to >=20.10

# Option 2: Fallback to docker-compose v1
sudo pip install docker-compose

# Option 3: Use Podman instead
sudo apt install podman-compose
```

### "docker compose: command not found"

**Solution**: Either upgrade Docker or use v1/Podman

```bash
# Check Docker version
docker --version

# If <20.10, either upgrade or use:
docker-compose up -d         # v1 (requires pip install)
podman-compose up -d         # Podman (requires podman install)
```

### KVM not detected by docker-compose

**Issue**: Container starts but in TCG mode instead of KVM

**Diagnosis**:
```bash
docker compose exec gnu-hurd-dev env | grep KVM
# If empty or KVM=0, KVM not detected
```

**Solution**:

```bash
# 1. Verify /dev/kvm exists
ls -la /dev/kvm

# 2. Check Docker socket group permissions
groups $USER | grep docker

# 3. Restart Docker daemon
sudo systemctl restart docker

# 4. Try KVM override explicitly
docker compose -f docker-compose.yml -f docker-compose.kvm.yml up -d
```

### Podman rootless KVM issues

**Issue**: KVM not available in rootless Podman

**Solution**:
```bash
# Enable unprivileged namespace clones
echo "kernel.unprivileged_userns_clone = 1" | sudo tee /etc/sysctl.d/99-podman-kvm.conf
sudo sysctl -p /etc/sysctl.d/99-podman-kvm.conf

# Increase /dev/kvm access for rootless user
sudo chmod 666 /dev/kvm
```

---

## Related Documentation

- [PODMAN-SUPPORT.md](../01-GETTING-STARTED/PODMAN-SUPPORT.md) - Detailed Podman setup guide
- [DOCKER-COMPOSE-GUIDE.md](DOCKER-COMPOSE-GUIDE.md) - docker-compose usage patterns
- [Makefile](../../Makefile) - Compose control plane targets
- [compose.kvm.yaml](../../compose.kvm.yaml) - KVM acceleration overlay

---

## Summary

| Use Case | Recommended | Alternative | Avoid |
|----------|-------------|-------------|-------|
| Linux x86_64 development | Docker v2 | Podman / Libvirt | docker-compose v1 |
| Linux ARM64 development | Podman | — | Docker v1 |
| macOS development | Docker v2 | Podman Desktop | docker-compose v1 |
| Windows development | Docker v2 | Podman Desktop | docker-compose v1 |
| Rootless containers | Podman | — | Docker without special config |
| CI/CD pipelines | Docker v2 | Podman | docker-compose v1 |
| Production deployment | Docker v2 | Podman | docker-compose v1 |
| Kubernetes integration | Podman | — | Other compose tools |
| Full VM management | Libvirt | — | Containers (different model) |
| VM snapshots/migration | Libvirt | — | Containers (no native support) |
| Infrastructure testing | Libvirt | Docker v2 | Containers (less isolation) |

---

*Last updated: 2026-01-15*
*Compatibility tested: Docker 20.10+, Docker Compose v2 (2.10+), Podman 3.0+, podman-compose 1.0+, Libvirt 7.0+*
