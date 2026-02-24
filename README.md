# GNU/Hurd Docker - x86_64 Development Environment

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-24.0+-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/)
[![QEMU](https://img.shields.io/badge/QEMU-x86__64-FF6600?logo=qemu&logoColor=white)](https://www.qemu.org/)
[![Architecture](https://img.shields.io/badge/Container-amd64%20%7C%20arm64-success)](docs/02-ARCHITECTURE/SYSTEM-DESIGN.md)
[![Guest](https://img.shields.io/badge/Guest-x86__64%20only-blue)](docs/02-ARCHITECTURE/SYSTEM-DESIGN.md)
[![Documentation](https://img.shields.io/badge/docs-comprehensive-brightgreen)](docs/INDEX.md)

**Modern Docker-based development environment for Debian GNU/Hurd x86_64**

**Release**: Debian GNU/Hurd (Debian 13 "Trixie", ports/13.0)

**Guest Architecture**: x86_64 (via QEMU)

**Container Platforms**: linux/amd64, linux/arm64 (Apple Silicon supported)

---

## Quick Start (Choose Your Path)

### Path A: Docker-based (Recommended for Most Users)

```bash
# 1. Download and setup x86_64 image (10-15 min)
./scripts/setup-hurd-amd64.sh

# 2. Start container
make up

# 3. Wait for boot (2-5 minutes)
make logs

# 4. Connect via SSH
ssh -p 2222 root@localhost
# Password: root (or press Enter)
```

**Best for**: Development, testing, CI/CD, isolated environments

### Path B: Standalone QEMU (Advanced Users)

```bash
# 1. Download QCOW2 image
./scripts/setup-hurd-amd64.sh

# 2. Launch VM directly (no Docker)
./scripts/run-hurd-qemu.sh

# 3. Connect via SSH
ssh -p 2222 root@localhost
# Password: root (or press Enter)

# Custom configuration
./scripts/run-hurd-qemu.sh --memory 8192 --cpus 4 --vnc :0
```

**Best for**: Native performance, benchmarking, direct QEMU control

### Path C: Fresh Upstream Latest Image (ports/latest)

```bash
# 1. Resolve and download latest dated hurd-amd64 image
make setup-latest

# 2. Boot using the latest-image alias (keeps baseline image untouched)
make up-latest

# 3. Follow logs and connect
make logs
ssh -p 2222 root@localhost
```

**Best for**: testing the newest Debian GNU/Hurd image while keeping reproducible baseline workflows

### Path D: Fresh Daily Installer (d-i hurd-amd64)

```bash
# 1. Resolve/download latest d-i mini.iso + create fresh qcow2 target disk
make setup-daily-installer

# 2. Boot installer media on fresh target disk
make up-installer

# Podman variant:
# PODMAN_COMPOSE_PROVIDER=podman-compose CONTAINER_RUNTIME=podman make up-podman-installer
```

**Best for**: validating against the newest installer daily when ports/latest prebuilt images lag behind

**Need help choosing?** See [docs/01-GETTING-STARTED/USAGE-MODES.md](docs/01-GETTING-STARTED/USAGE-MODES.md)

**Detailed setup**: See [docs/01-GETTING-STARTED/INSTALLATION.md](docs/01-GETTING-STARTED/INSTALLATION.md)

**Fast-track guide**: See [docs/01-GETTING-STARTED/QUICKSTART.md](docs/01-GETTING-STARTED/QUICKSTART.md)

---

## Documentation

**Complete documentation**: [docs/INDEX.md](docs/INDEX.md)

### Quick Links

**Getting Started**:
- [Usage Modes](docs/01-GETTING-STARTED/USAGE-MODES.md) - Choose Docker vs Standalone QEMU
- [Installation Guide](docs/01-GETTING-STARTED/INSTALLATION.md) - Complete setup instructions
- [Quickstart](docs/01-GETTING-STARTED/QUICKSTART.md) - Fast-track boot and verify
- [Latest Image Workflow](docs/01-GETTING-STARTED/LATEST-IMAGE-WORKFLOW.md) - Fresh upstream latest + reproducible baseline
- [Standalone QEMU Guide](docs/01-GETTING-STARTED/STANDALONE-QEMU.md) - Run Hurd without Docker

**Daily Operations**:
- [Interactive Access](docs/04-OPERATION/INTERACTIVE-ACCESS.md) - SSH, serial console, file transfers
- [Snapshots](docs/04-OPERATION/SNAPSHOTS.md) - State management and rollback
- [Monitoring](docs/04-OPERATION/MONITORING.md) - Performance tracking

**Troubleshooting**:
- [Common Issues](docs/06-TROUBLESHOOTING/COMMON-ISSUES.md) - Frequent problems and solutions
- [SSH Issues](docs/06-TROUBLESHOOTING/SSH-ISSUES.md) - Connection troubleshooting
- [FSCK Errors](docs/06-TROUBLESHOOTING/FSCK-ERRORS.md) - Filesystem recovery

**Reference**:
- [Scripts](docs/08-REFERENCE/SCRIPTS.md) - All 21 automation scripts
- [Credentials](docs/08-REFERENCE/CREDENTIALS.md) - Access and security

---

## Architecture

**Important**: This project runs a **full Debian GNU/Hurd system in a QEMU virtual machine**. Docker only hosts the QEMU process—it does *not* run Hurd as a native container. There is no direct/native Hurd-on-Docker support on Linux yet, as this would require a Mach-on-Linux or Hurd-on-Linux port (see [Doing a GNU/Hurd System Port](https://darnassus.sceen.net/~hurd-web/faq/system_port/) for details).

**Multi-Platform Container Support**: The Docker container runs on both `linux/amd64` and `linux/arm64` hosts (e.g., Apple Silicon Macs, ARM servers). QEMU inside the container emulates x86_64 for the GNU/Hurd guest regardless of host architecture.

**x86_64-only guest**:

| Component | Configuration |
|-----------|---------------|
| **QEMU Binary** | `qemu-system-x86_64` (underscore!) |
| **Release** | Debian GNU/Hurd (Debian 13 "Trixie", ports/13.0) |
| **Release Track (reproducible)** | `https://cdimage.debian.org/cdimage/ports/13.0/hurd-amd64/` |
| **Latest Track (rolling)** | `https://cdimage.debian.org/cdimage/ports/latest/hurd-amd64/` |
| **Latest Resolver** | `./scripts/resolve-latest-hurd-amd64.sh` |
| **Daily Installer Track** | `https://d-i.debian.org/daily-images/hurd-amd64/` |
| **Daily Installer Resolver** | `./scripts/resolve-latest-hurd-amd64-daily-installer.sh` |
| **Image** | debian-hurd.img.tar.xz (~337 MB compressed, ~3.9 GB raw) |
| **Image URL** | https://cdimage.debian.org/cdimage/ports/13.0/hurd-amd64/ |
| **CPU** | `-cpu max` or `-cpu host` (KVM acceleration) |
| **RAM** | 4 GB (minimum 2 GB, recommended 4-8 GB) |
| **SMP** | 1-2 cores (stable), 4+ experimental |
| **Storage** | IDE (default; guest compatibility) |
| **Machine** | pc (stable, not q35) |
| **Network** | E1000 (proven Hurd compatibility) |

**See**: [docs/02-ARCHITECTURE/SYSTEM-DESIGN.md](docs/02-ARCHITECTURE/SYSTEM-DESIGN.md)

---

## Access

### SSH (Primary)

```bash
ssh -p 2222 root@localhost
# Password: root
```

**Default accounts**:
- `root` / `root` - System administrator (UID 0)
- `agents` / `agents` - Development user (sudo NOPASSWD)

### Serial Console (Emergency)

```bash
telnet localhost 5555
# Or: ./scripts/connect-console.sh
```

### Port Mappings

| Service | Port | Usage |
|---------|------|-------|
| SSH | 2222 | Primary access |
| Serial Console | 5555 | Emergency access |
| Custom Services | Configure in compose.yaml |

**See**: [docs/03-CONFIGURATION/PORT-FORWARDING.md](docs/03-CONFIGURATION/PORT-FORWARDING.md)

---

## Features

### Core Features
- Debian 13 "Trixie" ports/13.0 GNU/Hurd guest (x86_64)
- Multi-platform container: runs on `linux/amd64` and `linux/arm64` (guest still x86_64 via QEMU)
- Optional KVM acceleration on Linux x86_64 hosts (otherwise TCG emulation). Note: some Debian GNU/Hurd images hit IDE DMA I/O errors under KVM; this repo auto-disables KVM for IDE on `pc` unless `FORCE_KVM=1`.
- Official Debian Ports images and checksums (`SHA256SUMS`) from cdimage

### Infrastructure
- IDE storage + E1000 networking defaults (guest compatibility)
- Snapshot management with QCOW2 (host-side rollback)
- Automation scripts for setup, orchestration, validation, and troubleshooting

---

## Requirements

**Docker**: Docker + Docker Compose v2

**Virtualization**:
- **Linux x86_64**: KVM (`/dev/kvm`) can be faster, but may be auto-disabled for reliability with IDE disks (`AUTO_DISABLE_KVM_FOR_IDE=1` default). Use `FORCE_KVM=1` to override.
- **macOS/Windows**: TCG emulation (slower but works)

**Disk Space**: 10-12 GB (image + container)

**RAM**: 6 GB minimum (4 GB guest + 2 GB host overhead)

**See**: [docs/01-GETTING-STARTED/INSTALLATION.md](docs/01-GETTING-STARTED/INSTALLATION.md#system-requirements)

---

## Common Tasks

### Start/Stop Environment

```bash
# Start (dev default: bind-mount ./images)
make up

# Stop (graceful)
ssh -p 2222 root@localhost shutdown -h now
make down

# Restart (container)
docker compose restart
```

### Create Snapshot

```bash
./scripts/manage-snapshots.sh create before-upgrade
```

### Monitor Performance

```bash
./scripts/monitor-qemu.sh
```

### Run System Tests

```bash
./scripts/test-hurd-system.sh
```

**See**: [docs/08-REFERENCE/SCRIPTS.md](docs/08-REFERENCE/SCRIPTS.md) for all scripts

---

## CI/CD

**GitHub Actions**: Pre-provisioned image workflow

**Advantages**:
- **Time**: 2-5 min (vs 20-40 min with serial automation)
- **Reliability**: 95%+ (vs 60-70% with serial)
- **Simplicity**: No fragile expect scripts

**Setup**: [docs/05-CI-CD/SETUP.md](docs/05-CI-CD/SETUP.md)

**Workflows**: [docs/05-CI-CD/WORKFLOWS.md](docs/05-CI-CD/WORKFLOWS.md)

**Pre-Provisioned Images**: [docs/05-CI-CD/PROVISIONED-IMAGE.md](docs/05-CI-CD/PROVISIONED-IMAGE.md)

---

## Project Structure

```
.
├── docs/                          # Complete documentation (26 files)
│   ├── INDEX.md                   # Master documentation index
│   ├── 01-GETTING-STARTED/        # Installation and quickstart
│   ├── 02-ARCHITECTURE/           # System design and QEMU config
│   ├── 03-CONFIGURATION/          # Port forwarding, users, features
│   ├── 04-OPERATION/              # Daily operations and monitoring
│   ├── 05-CI-CD/                  # GitHub Actions and automation
│   ├── 06-TROUBLESHOOTING/        # Common issues and fixes
│   ├── 07-RESEARCH/               # Deep dives and migration docs
│   └── 08-REFERENCE/              # Scripts and credentials reference
├── scripts/                       # 21 automation scripts
│   ├── setup-hurd-amd64.sh       # x86_64 image setup
│   ├── install-ssh-hurd.sh       # SSH installation
│   ├── manage-snapshots.sh       # Snapshot management
│   └── ... (18 more scripts)
├── .github/workflows/             # CI/CD workflows (x86_64 only)
├── compose.yaml                    # QEMU VM base configuration
├── Dockerfile                     # Container image
├── entrypoint.sh                  # QEMU launcher
└── ARCHIVE/                       # Historical docs (migration, i386)
```

---

## Legacy i386 content

i386 references are preserved for historical context under `ARCHIVE/` and `docs/**/archive/`. The current supported guest is x86_64.

**Migration notes**: [docs/07-RESEARCH-AND-LESSONS/X86_64-MIGRATION.md](docs/07-RESEARCH-AND-LESSONS/X86_64-MIGRATION.md)

**Lessons learned**: [docs/07-RESEARCH-AND-LESSONS/LESSONS-LEARNED.md](docs/07-RESEARCH-AND-LESSONS/LESSONS-LEARNED.md)

---

## Troubleshooting

**Cannot SSH**: [docs/06-TROUBLESHOOTING/SSH-ISSUES.md](docs/06-TROUBLESHOOTING/SSH-ISSUES.md)

**Boot failures**: [docs/06-TROUBLESHOOTING/FSCK-ERRORS.md](docs/06-TROUBLESHOOTING/FSCK-ERRORS.md)

**Performance issues**: [docs/06-TROUBLESHOOTING/COMMON-ISSUES.md](docs/06-TROUBLESHOOTING/COMMON-ISSUES.md)

**All issues**: [docs/06-TROUBLESHOOTING/](docs/06-TROUBLESHOOTING/)

---

## Contributing

**Documentation**:
- Edit relevant document in `/docs` sections
- Validate links: `markdown-link-check docs/**/*.md`
- Generate TOCs: `markdown-toc -i docs/**/*.md`
- Follow existing format and style

**Code**:
- Test changes locally
- Update documentation
- Run validation scripts
- Submit pull request

**See**: [docs/INDEX.md](docs/INDEX.md) for documentation standards

---

## Resources

**Documentation**: [docs/INDEX.md](docs/INDEX.md)

**Debian GNU/Hurd**: https://www.debian.org/ports/hurd/

**Mach Microkernel**: https://www.gnu.org/software/hurd/microkernel/mach.html

**QEMU**: https://www.qemu.org/

**GitHub Actions**: https://docs.github.com/en/actions

---

## License

MIT License - See [LICENSE](LICENSE) file

---

## Quick Reference

**Default Credentials**:
- Root: `root` / `root`
- Agents: `agents` / `agents`

**Access Ports**:
- SSH: `2222`
- Serial Console: `5555`

**Critical Binary**:
- QEMU: `qemu-system-x86_64` (underscore, not hyphen!)

**Essential Commands**:
```bash
# Start environment
make up

# Connect via SSH
ssh -p 2222 root@localhost

# Create snapshot
./scripts/manage-snapshots.sh create snapshot-name

# Monitor performance
./scripts/monitor-qemu.sh
```

**For everything else**: [docs/INDEX.md](docs/INDEX.md)

---

[Complete Documentation](docs/INDEX.md) | [Quickstart](docs/01-GETTING-STARTED/QUICKSTART.md) | [Troubleshooting](docs/06-TROUBLESHOOTING/)
