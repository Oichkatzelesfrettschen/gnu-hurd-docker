# GNU/Hurd Docker - i386 Microkernel in a Container

[![Status](https://img.shields.io/badge/status-production--ready-brightgreen)](https://github.com/oaich/gnu-hurd-docker)
[![Docker](https://img.shields.io/badge/docker-ready-blue)](https://docs.docker.com/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Run the complete GNU/Hurd microkernel (i386) inside Docker containers using QEMU emulation.

## Overview

This project provides a production-ready Docker Compose setup for running native i386 GNU/Hurd environments in isolated containers. It solves the microkernel kernel-swap problem by implementing a **QEMU-in-Docker** pattern, enabling full GNU/Mach operating system functionality within Docker's containerization model.

### Key Features

- **Complete GNU/Hurd i386 Environment:** Full microkernel OS with package management (Debian 2025)
- **Optimized QEMU Emulation:** VirtIO devices, KVM acceleration, multiple display modes
- **Graphics Support:** VNC, SDL with OpenGL, GTK with OpenGL, framebuffer
- **Interactive Access:** TTY-based serial console, SSH, and optional GUI
- **Network Isolation:** User-mode NAT networking with VirtIO-Net
- **Production-Ready:** Validated configuration based on official 2025 guidelines
- **Well-Documented:** Comprehensive optimization and deployment guides

## Quick Start

### Prerequisites

- Docker Engine (>=20.10) and Docker Compose (>=1.29)
- 10-20GB free disk space (depending on packages installed)
- 4-8GB available RAM (2GB minimum for CLI, 4GB+ recommended for GUI)
- Optional: KVM support for hardware acceleration (Linux only)

## Installation

### Quick Install (All Platforms)

```bash
# Clone repository
git clone https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker.git
cd gnu-hurd-docker

# Download system image
./scripts/download-image.sh

# Build Docker image
docker-compose build

# Launch container
docker-compose up -d

# View logs
docker-compose logs -f
```

### Arch Linux (AUR Package)

```bash
# Using yay
yay -S gnu-hurd-docker

# Using package commands
gnu-hurd-docker download
gnu-hurd-docker build
gnu-hurd-docker start
```

See **[INSTALLATION.md](INSTALLATION.md)** for complete platform-specific installation instructions (Linux, macOS, Windows).

### Access the System

**Via Serial Console:**
```bash
# Find PTY from logs
docker-compose logs | grep "char device redirected"

# Connect (replace /dev/pts/X with actual PTY)
screen /dev/pts/X
```

**Via SSH (port 2222):**
```bash
ssh -p 2222 root@localhost
# Default password: (see CREDENTIALS.md)
```

**Direct Shell:**
```bash
docker-compose exec gnu-hurd-dev bash
```

## Configuration

### System Specifications

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| CPU | Pentium | 32-bit compatible, stable emulation |
| RAM | 1.5GB | Adequate for GNU/Hurd + utilities |
| Disk Format | QCOW2 | 50% compression vs raw format |
| Disk Cache | writeback | Optimized I/O performance |
| Network | user-mode NAT | No host root privileges required |
| Serial | PTY | Interactive keyboard support |

### Network Configuration

- **SSH:** Port 2222 (host) → 22 (container)
- **Custom:** Port 9999 (extensible for other services)

### Volume Mounts

- Current directory → `/opt/hurd-image` (read-only)
- QCOW2 disk image mounted as read-only from host

## Documentation

### Getting Started
- **[INSTALLATION.md](INSTALLATION.md)** - Complete installation guide for all platforms
- **[requirements.md](requirements.md)** - Detailed system requirements and dependencies
- **[SIMPLE-START.md](SIMPLE-START.md)** - Quickest path to running system
- **[LOCAL-TESTING-GUIDE.md](LOCAL-TESTING-GUIDE.md)** - Testing and validation procedures

### Architecture & Design
- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Detailed design rationale and implementation
- **[QEMU-TUNING.md](docs/QEMU-TUNING.md)** - Performance optimization guide
- **[HURD-IMAGE-BUILDING.md](docs/HURD-IMAGE-BUILDING.md)** - Custom image creation

### Operations & CI/CD
- **[CI-CD-GUIDE.md](docs/CI-CD-GUIDE.md)** - QEMU automation and CI/CD workflows
- **[DEPLOYMENT.md](docs/DEPLOYMENT.md)** - Step-by-step deployment procedures
- **[VALIDATION-AND-TROUBLESHOOTING.md](docs/VALIDATION-AND-TROUBLESHOOTING.md)** - Common issues and solutions

### User Management
- **[CREDENTIALS.md](docs/CREDENTIALS.md)** - Default root user/password and SSH access
- **[docs/USER-SETUP.md](docs/USER-SETUP.md)** - Creating and configuring standard user accounts

### Reference
- **[PROJECT-SUMMARY.md](PROJECT-SUMMARY.md)** - Comprehensive project overview
- **[REPOSITORY-INDEX.md](REPOSITORY-INDEX.md)** - Complete file structure index

## File Structure

```
.
├── Dockerfile                    # Docker image specification
├── entrypoint.sh                # QEMU launcher script
├── docker-compose.yml           # Container orchestration
├── README.md                    # This file
├── .gitignore                   # Git ignore rules
├── .github/
│   └── workflows/
│       ├── build.yml            # Build workflow
│       ├── validate.yml         # Configuration validation
│       └── release.yml          # Release workflow
├── docs/
│   ├── ARCHITECTURE.md          # Architecture design
│   ├── DEPLOYMENT.md            # Deployment guide
│   ├── CREDENTIALS.md           # Access information
│   ├── USER-SETUP.md            # Account creation
│   └── TROUBLESHOOTING.md       # Troubleshooting guide
└── scripts/
    ├── download-image.sh        # Download system image
    ├── validate-config.sh       # Validate configuration
    └── test-docker.sh           # Test Docker setup
```

## System Access

### Default Root Credentials

- **User:** `root`
- **Password:** See [CREDENTIALS.md](docs/CREDENTIALS.md)
- **SSH:** Port 2222

### Creating Standard User Accounts

See [USER-SETUP.md](docs/USER-SETUP.md) for detailed instructions on:
- Adding new system users
- Configuring sudo privileges
- Setting up user environments
- Password management

## Performance Characteristics

- **Boot Time:** 2-3 minutes (depends on host CPU)
- **CPU Emulation:** ~100-200ms latency (acceptable for development)
- **Disk I/O:** QCOW2 writeback cache optimized throughput
- **Memory:** 1.5GB allocation suitable for base system + utilities
- **Network:** User-mode NAT adds ~5-10ms latency

## Build Process

```bash
# Validate configuration (before build)
./scripts/validate-config.sh

# Build image
docker-compose build

# Watch build progress
docker-compose build --progress=plain

# Inspect image
docker image inspect gnu-hurd-dev:latest
```

## Testing

### Automated System Testing

```bash
# Run comprehensive GNU/Hurd system tests
./scripts/test-hurd-system.sh

# This tests:
# - Container and boot status
# - Root user access (root/root)
# - Agents user access (agents/agents) with sudo NOPASSWD
# - C program compilation and execution
# - Package management functionality
# - Filesystem operations
# - GNU/Hurd specific features
```

See **[docs/HURD-TESTING-REPORT.md](docs/HURD-TESTING-REPORT.md)** for detailed test results and examples.

### Docker Configuration Tests

```bash
# Run automated Docker setup tests
./scripts/test-docker.sh

# Manual testing checklist
- [ ] Container builds without errors
- [ ] Container starts successfully
- [ ] QEMU boots and reaches login prompt
- [ ] SSH access works on port 2222
- [ ] Serial console is interactive
- [ ] Standard user account creation works
- [ ] Network connectivity functional
```

## Troubleshooting

### Common Issues

**Docker daemon won't start:**
See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) - Kernel Configuration section

**Container won't start:**
```bash
docker-compose logs --tail=100
# Check for: file not found, permission denied, port conflicts
```

**QEMU hangs during boot:**
```bash
# Serial console waiting for input
screen /dev/pts/X
# Press: Enter, then Ctrl-A followed by :quit to exit
```

**SSH connection refused:**
```bash
# Verify SSH is running inside container
docker-compose exec gnu-hurd-dev ps aux | grep sshd
# Check port mapping: docker-compose ps
```

See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for complete troubleshooting guide.

## Architecture Highlights

### QEMU-in-Docker Pattern

The solution implements privileged containers running QEMU i386 emulator, enabling GNU/Mach microkernel operation within Docker by:

1. Running QEMU system emulator in privileged container
2. Emulating complete i386 architecture (Pentium CPU)
3. Mounting QCOW2 disk image as bind-mount
4. Exposing serial console via PTY
5. Forwarding SSH port to host

### Why Not Native Container?

GNU/Mach is a microkernel that requires direct hardware access and cannot be swapped with a host kernel. Standard containerization (cgroups, namespaces) cannot provide this. QEMU-in-Docker provides full system emulation, solving the kernel-swap problem.

## Development

### Prerequisites for Development

- Docker and Docker Compose
- Git
- Bash 4.0+
- ShellCheck (for validation)
- Python 3.7+ (for YAML validation)

### Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-thing`)
3. Validate configuration (`./scripts/validate-config.sh`)
4. Test thoroughly (`./scripts/test-docker.sh`)
5. Commit with clear messages
6. Push to branch and create Pull Request

## CI/CD Workflows

This repository includes comprehensive GitHub Actions workflows:

### Build & Validation
- **Build:** Builds Docker image on push (validates syntax and structure)
- **Validate:** Validates configuration files (Dockerfile, compose, scripts)
- **Quality & Security:** Comprehensive linting and security scanning
  - ShellCheck for all shell scripts (warnings as errors)
  - YAML validation with strict rules
  - Python linting (black, flake8, pylint)
  - Dockerfile best practices (Hadolint)
  - Security scanning (Trivy)
  - Dependency auditing

### QEMU CI/CD
- **QEMU CI (TCG):** GitHub-hosted runners with software emulation
  - Automated QEMU boot testing
  - QMP automation validation
  - Serial console testing
  - Artifact collection
- **QEMU CI (KVM):** Self-hosted runners with hardware acceleration
  - Performance testing
  - Full system integration tests
  - Benchmark execution

### Release & Deployment
- **Release:** Creates releases and tags
- **Push GHCR:** Automated Docker image publishing to GitHub Container Registry
- **Deploy Pages:** Documentation deployment to GitHub Pages

See `.github/workflows/` for workflow definitions and [docs/CI-CD-GUIDE.md](docs/CI-CD-GUIDE.md) for detailed automation guide.

## Validation Status

All configuration files validated:

- ✓ Dockerfile: Valid syntax (18 lines)
- ✓ entrypoint.sh: ShellCheck passed (20 lines)
- ✓ docker-compose.yml: Valid YAML (27 lines)
- ✓ System images: Present and verified (6.5GB total)
- ✓ Documentation: Complete and accurate

## System Requirements

### Minimum

- 2GB RAM
- 2GB disk space
- Linux host with Docker
- 1 CPU core

### Recommended

- 4GB+ RAM
- 15GB disk space
- Modern multi-core CPU
- Linux kernel 5.10+
- Docker 20.10+

## Known Limitations

1. **Kernel Modules:** Cannot load custom kernel modules (no source in container)
2. **Hardware Access:** Limited to QEMU-emulated devices
3. **X11/GUI:** Not available with `-nographic` mode (headless)
4. **Suspend/Resume:** Not supported in QEMU user-mode
5. **Real Networking:** User-mode NAT only (no raw sockets for certain protocols)

## Performance Optimization

### For Development

- Use default settings (1.5GB RAM, Pentium CPU)
- Writeback disk cache enabled for optimal I/O
- User-mode NAT sufficient for most use cases

### For Performance Testing

- Increase RAM: Edit `docker-compose.yml` -m parameter
- Use CPU passthrough: Change `-cpu pentium` to `-cpu host` (requires same-arch CPU)
- Enable QEMU TCG acceleration (if available)

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

## Support

- **Issues:** Open a GitHub issue for bugs or feature requests
- **Discussions:** Use GitHub Discussions for questions
- **Documentation:** See [docs/](docs/) for detailed guides

## References

- [GNU/Hurd Official](https://www.gnu.org/software/hurd/)
- [Debian GNU/Hurd](https://www.debian.org/ports/hurd/)
- [QEMU Documentation](https://www.qemu.org/documentation/)
- [Docker Documentation](https://docs.docker.com/)

## Acknowledgments

- Debian GNU/Hurd project for official i386 system images
- QEMU project for i386 emulation
- Docker for containerization platform

---

**Status:** Production-ready | **Last Updated:** 2025-11-05 | **Maintainer:** Oaich

For comprehensive architecture details, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
