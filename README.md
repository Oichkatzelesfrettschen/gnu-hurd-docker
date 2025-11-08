# GNU/Hurd Docker - x86_64 Development Environment

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-24.0+-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/)
[![QEMU](https://img.shields.io/badge/QEMU-x86__64-FF6600?logo=qemu&logoColor=white)](https://www.qemu.org/)
[![Architecture](https://img.shields.io/badge/Architecture-x86__64%20only-success)](docs/02-ARCHITECTURE/SYSTEM-DESIGN.md)
[![Documentation](https://img.shields.io/badge/docs-comprehensive-brightgreen)](docs/INDEX.md)

**Modern Docker-based development environment for Debian GNU/Hurd x86_64**

**Architecture**: Pure x86_64 (i386 deprecated 2025-11-07)

---

## Quick Start

```bash
# 1. Download and setup x86_64 image (10-15 min)
./scripts/setup-hurd-amd64.sh

# 2. Start container
docker-compose up -d

# 3. Wait for boot (2-5 minutes)
docker-compose logs -f

# 4. Connect via SSH
ssh -p 2222 root@localhost
# Password: root (or press Enter)
```

**For detailed setup**: See [docs/01-GETTING-STARTED/INSTALLATION.md](docs/01-GETTING-STARTED/INSTALLATION.md)

**For fast-track guide**: See [docs/01-GETTING-STARTED/QUICKSTART.md](docs/01-GETTING-STARTED/QUICKSTART.md)

---

## Documentation

**Complete documentation**: [docs/INDEX.md](docs/INDEX.md)

### Quick Links

**Getting Started**:
- [Installation Guide](docs/01-GETTING-STARTED/INSTALLATION.md) - Complete setup instructions
- [Quickstart](docs/01-GETTING-STARTED/QUICKSTART.md) - Fast-track boot and verify

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

**x86_64-Only** (i386 deprecated 2025-11-07):

| Component | Configuration |
|-----------|---------------|
| **QEMU Binary** | `qemu-system-x86_64` (underscore!) |
| **Image** | debian-hurd-amd64-20250807.img (337 MB download, 80 GB dynamic) |
| **CPU** | `-cpu max` or `-cpu host` (KVM acceleration) |
| **RAM** | 4 GB (configurable: 2-8 GB) |
| **SMP** | 1-2 cores (stable) |
| **Storage** | SATA/AHCI (recommended) |
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
| Custom Services | Configure in docker-compose.yml |

**See**: [docs/03-CONFIGURATION/PORT-FORWARDING.md](docs/03-CONFIGURATION/PORT-FORWARDING.md)

---

## Features

- ✅ **x86_64 Native**: Full 64-bit architecture (i386 removed)
- ✅ **KVM Acceleration**: 30-60s boot (vs 3-5 min TCG)
- ✅ **Official Debian Image**: debian-hurd-amd64-20250807
- ✅ **SATA/AHCI Storage**: Stable x86_64 Hurd support
- ✅ **Pre-Provisioned CI**: 85% faster, 95% reliable
- ✅ **Comprehensive Docs**: 26 documents, 8 sections
- ✅ **21 Automation Scripts**: Setup, install, configure, test
- ✅ **Snapshot Management**: QCOW2 snapshots for rollback

---

## Requirements

**Docker**: Docker + Docker Compose v2

**Virtualization**:
- **Linux**: KVM (`/dev/kvm`) - 3x faster boot
- **macOS/Windows**: TCG emulation (slower but works)

**Disk Space**: 10-12 GB (image + container)

**RAM**: 6 GB minimum (4 GB guest + 2 GB host overhead)

**See**: [docs/01-GETTING-STARTED/INSTALLATION.md](docs/01-GETTING-STARTED/INSTALLATION.md#system-requirements)

---

## Common Tasks

### Start/Stop Environment

```bash
# Start
docker-compose up -d

# Stop (graceful)
ssh -p 2222 root@localhost shutdown -h now
docker-compose down

# Restart
docker-compose restart
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
├── docker-compose.yml             # QEMU VM configuration
├── Dockerfile                     # Container image
├── entrypoint.sh                  # QEMU launcher
└── ARCHIVE/                       # Historical docs (migration, i386)
```

---

## Migration (i386 → x86_64)

**Date**: 2025-11-07

**Breaking Changes**:
- All i386 support removed
- QEMU binary: `qemu-system-i386` → `qemu-system-x86_64`
- RAM: 1.5 GB → 4 GB
- Storage: IDE → SATA/AHCI
- Machine: q35 → pc

**Migration Guide**: [docs/07-RESEARCH/X86_64-MIGRATION.md](docs/07-RESEARCH/X86_64-MIGRATION.md)

**Lessons Learned**: [docs/07-RESEARCH/LESSONS-LEARNED.md](docs/07-RESEARCH/LESSONS-LEARNED.md)

**Archive**: [ARCHIVE/migration/](ARCHIVE/migration/)

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
docker-compose up -d

# Connect via SSH
ssh -p 2222 root@localhost

# Create snapshot
./scripts/manage-snapshots.sh create snapshot-name

# Monitor performance
./scripts/monitor-qemu.sh
```

**For everything else**: [docs/INDEX.md](docs/INDEX.md)

---

[📖 Complete Documentation](docs/INDEX.md) | [🚀 Quickstart](docs/01-GETTING-STARTED/QUICKSTART.md) | [🔧 Troubleshooting](docs/06-TROUBLESHOOTING/)
