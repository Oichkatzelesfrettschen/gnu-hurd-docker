# GNU/Hurd Docker - Usage Modes Decision Guide

**Last Updated**: 2025-11-08
**Purpose**: Help users choose between Docker-based and Standalone QEMU deployment methods
**Architecture**: x86_64 only

---

## Overview

WHY: Different users have different requirements for isolation, performance, and integration.
WHAT: Two deployment modes - Docker (containerized QEMU) vs Standalone (direct QEMU).
HOW: This guide provides comparison criteria and decision flowchart to select the right mode.

The GNU/Hurd Docker project supports TWO distinct ways to run Debian GNU/Hurd:

1. **Docker Mode** (RECOMMENDED): QEMU runs inside a Docker container
2. **Standalone Mode** (ADVANCED): QEMU runs directly on your host system

---

## Quick Decision

**Use Docker Mode if you**:
- Want the simplest setup experience
- Need consistent environments across systems
- Prefer isolation from host system
- Are running in CI/CD pipelines
- Want easy cleanup and resource management

**Use Standalone Mode if you**:
- Need maximum performance
- Have specific QEMU requirements
- Want direct hardware access
- Are doing kernel development
- Prefer minimal overhead

---

## Detailed Comparison Table

| Criteria | Docker Mode | Standalone QEMU |
|----------|-------------|-----------------|
| **Setup Complexity** | Simple: `docker compose up` | Medium: Install QEMU, configure paths |
| **Performance** | Good: ~5-10% overhead | Best: Direct hardware access |
| **Isolation** | Excellent: Full container isolation | None: Runs on host directly |
| **Portability** | Excellent: Works identically everywhere | Variable: Host-specific configuration |
| **CI/CD Integration** | Native: Built for containers | Complex: Requires setup scripts |
| **Resource Overhead** | Docker daemon + container layer | QEMU only |
| **Host Requirements** | Docker + Docker Compose | QEMU + KVM (optional) |
| **Network Configuration** | Automatic via Docker | Manual iptables/bridges |
| **Storage Management** | Docker volumes | Direct filesystem access |
| **Debugging** | Through Docker logs/exec | Direct process access |
| **Snapshots** | Docker + QEMU snapshots | QEMU snapshots only |
| **Multi-instance** | Easy with compose scaling | Manual port management |
| **Clean Uninstall** | `docker compose down` + prune | Manual file cleanup |

---

## Decision Flowchart

```
START: Choose GNU/Hurd deployment mode
  |
  v
[Are you setting up CI/CD pipelines?]
  |
  YES --> DOCKER MODE
  |
  NO
  |
  v
[Do you need consistent environments across multiple machines?]
  |
  YES --> DOCKER MODE
  |
  NO
  |
  v
[Are you doing kernel/driver development requiring direct hardware?]
  |
  YES --> STANDALONE MODE
  |
  NO
  |
  v
[Do you have Docker installed and prefer containerized workflows?]
  |
  YES --> DOCKER MODE
  |
  NO
  |
  v
[Do you need absolute maximum performance (no overhead)?]
  |
  YES --> STANDALONE MODE
  |
  NO
  |
  v
[Are you comfortable with manual QEMU configuration?]
  |
  YES --> Either mode works, personal preference
  |
  NO --> DOCKER MODE
```

---

## Use Case Scenarios

### Best for Docker Mode

**Development Teams**
- Consistent environments across developers
- Easy onboarding with single command setup
- Version-controlled configuration via docker-compose.yml

**CI/CD Pipelines**
- Native container support in GitHub Actions, GitLab CI
- Reproducible builds and tests
- Easy parallel execution

**Learning and Experimentation**
- Quick setup and teardown
- No host system pollution
- Easy to reset to clean state

**Multi-Architecture Testing**
- Run multiple Hurd instances simultaneously
- Different configurations per container
- Resource isolation between instances

### Best for Standalone Mode

**Kernel Development**
- Direct KVM access for debugging
- Custom QEMU patches or builds
- Hardware passthrough capabilities

**Performance Testing**
- Benchmarking without container overhead
- Direct memory and CPU access
- Custom kernel modules

**System Integration**
- Integration with host development tools
- Direct filesystem mounting
- Custom networking setups

**Resource-Constrained Systems**
- Minimal memory footprint
- No Docker daemon overhead
- Direct process management

---

## Performance Considerations

### Docker Mode Overhead
- **CPU**: ~2-5% overhead from containerization
- **Memory**: Docker daemon uses ~200-500 MB
- **Disk I/O**: ~5-10% overhead through overlay filesystem
- **Network**: Minimal overhead through bridge network

### Standalone Mode Advantages
- **CPU**: Direct KVM acceleration with no layers
- **Memory**: Only QEMU process memory usage
- **Disk I/O**: Direct host filesystem access
- **Network**: Direct tap/bridge interfaces possible

---

## Setup Complexity Comparison

### Docker Mode Setup (3 commands)
```bash
# 1. Download image
./scripts/setup-hurd-amd64.sh

# 2. Start container
docker compose up -d

# 3. Connect
ssh -p 2222 root@localhost
```

### Standalone Mode Setup (5+ steps)
```bash
# 1. Install QEMU (varies by distro)
sudo pacman -S qemu-full  # Arch Linux

# 2. Download image
./scripts/setup-hurd-amd64.sh

# 3. Check KVM access
ls -l /dev/kvm

# 4. Run with configuration
./scripts/run-hurd-qemu.sh --memory 4096 --cpus 2

# 5. Connect
ssh -p 2222 root@localhost
```

---

## Migration Between Modes

### Docker to Standalone
1. Stop Docker container: `docker compose down`
2. Locate QCOW2 image: `images/debian-hurd-amd64.qcow2`
3. Run with standalone script: `./scripts/run-hurd-qemu.sh`

### Standalone to Docker
1. Stop QEMU process: `Ctrl-C` or kill PID
2. Ensure image is in `images/` directory
3. Start Docker: `docker compose up -d`

**Note**: Both modes use the same QCOW2 disk image format, enabling easy migration.

---

## Recommendations by User Type

| User Type | Recommended Mode | Reasoning |
|-----------|------------------|-----------|
| **New Users** | Docker | Simplest setup, best documentation |
| **Developers** | Docker | Consistent environments, easy reset |
| **DevOps/CI** | Docker | Native container integration |
| **Researchers** | Standalone | Direct access, custom configurations |
| **Kernel Hackers** | Standalone | Hardware access, debugging tools |
| **Educators** | Docker | Easy student setup, isolation |
| **Production** | Docker | Better monitoring, orchestration |

---

## Security Considerations

### Docker Mode
- **Isolation**: Container namespace isolation
- **Privileges**: Requires `--privileged` for KVM
- **Network**: Docker network policies apply
- **Updates**: Container image updates

### Standalone Mode
- **Isolation**: None, runs as user process
- **Privileges**: May need root for KVM/TAP
- **Network**: Direct host network access
- **Updates**: Manual QEMU updates

---

## Next Steps

**For Docker Mode**:
- Continue to [INSTALLATION.md](INSTALLATION.md)
- See [QUICKSTART.md](QUICKSTART.md) for fast setup

**For Standalone Mode**:
- Continue to [STANDALONE-QEMU.md](STANDALONE-QEMU.md)
- Review `scripts/run-hurd-qemu.sh --help`

---

## Summary

**Docker Mode** is recommended for most users due to:
- Simpler setup and management
- Better isolation and cleanup
- Consistent behavior across platforms
- Native CI/CD integration

**Standalone Mode** is better for:
- Maximum performance requirements
- Direct hardware access needs
- Custom QEMU configurations
- Minimal overhead scenarios

Choose based on your specific requirements and comfort level with the tools involved.