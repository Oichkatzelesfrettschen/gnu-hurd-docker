# GNU/Hurd Docker - x86_64 Development Environment

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-24.0+-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/)
[![QEMU](https://img.shields.io/badge/QEMU-x86__64-FF6600?logo=qemu&logoColor=white)](https://www.qemu.org/)
[![Architecture](https://img.shields.io/badge/Container-amd64%20%7C%20arm64-success)](docs/02-ARCHITECTURE/SYSTEM-DESIGN.md)
[![Guest](https://img.shields.io/badge/Guest-x86__64%20only-blue)](docs/02-ARCHITECTURE/SYSTEM-DESIGN.md)
[![Documentation](https://img.shields.io/badge/docs-comprehensive-brightgreen)](docs/index.md)

**Modern Docker-based development environment for Debian GNU/Hurd x86_64**

**Release**: Debian GNU/Hurd (Debian 13 "Trixie", ports/13.0)

**Guest Architecture**: x86_64 (via QEMU)

**Container Platforms**: linux/amd64, linux/arm64 (Apple Silicon supported)

---

## Quick Start (Choose Your Path)

### Path 0: Fastest -- released desktop image, any OS with Docker

Works the same on Linux, macOS (Intel or Apple Silicon), and Windows.
Prerequisite: [Docker](https://docs.docker.com/get-docker/) (Docker
Desktop on macOS/Windows; on Windows enable the WSL 2 backend, which
the Docker Desktop installer does by default). Podman works as a
drop-in on Linux and macOS: substitute `podman` for `docker`.

**1. Get the released guest image** (841 MB download, unpacks to a
6.7 GiB qcow2) from the
[latest release](https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/releases/latest):

```bash
# Linux / macOS / Windows (WSL or Git Bash):
git clone https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker.git
cd gnu-hurd-docker
./scripts/download-released-image.sh     # downloads, verifies, unpacks into images/
```

No bash at all (plain Windows)? Download
`debian-hurd-amd64-latest.qcow2.xz` from the release page in a
browser, extract it with 7-Zip (or `tar -xf` in PowerShell 7+), rename
the result to `debian-hurd-amd64.qcow2`, and place it in the repo's
`images/` folder.

**2. Start it:**

```bash
# Linux (KVM acceleration if /dev/kvm exists):
docker compose -f compose.yaml -f compose.kvm.yaml up -d

# macOS / Windows (no KVM inside Docker Desktop's VM -- QEMU falls
# back to TCG emulation; boot takes 5-10 min instead of 1-2):
docker compose up -d
```

**3. Use it:**

- **Desktop (UI):** the guest autostarts XFCE into a virtual
  framebuffer -- connect any VNC viewer to `localhost:5901`
  (password `hurdhurd`), or add the browser route with
  `docker compose -f compose.yaml -f compose.vnc.yaml --profile vnc up -d`
  and open `http://localhost:6080`.
- **SSH:** `ssh -p 2222 user@localhost` (initial password `user`) --
  the first login makes you set your own password.
- **Watch it boot:** `docker compose logs -f`

The same container image serves all platforms (`linux/amd64` +
`linux/arm64`); QEMU inside emulates x86_64 for the Hurd guest even on
Apple Silicon.

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
# 1. Resolve/download latest d-i mini.iso, build unattended mini-auto.iso, and create fresh qcow2 target disk
make setup-daily-installer

# 2. Boot unattended installer media on fresh target disk
make up-installer

# Podman variant:
# PODMAN_COMPOSE_PROVIDER=podman-compose CONTAINER_RUNTIME=podman make up-podman-installer
```

**Best for**: validating against the newest installer daily when ports/latest prebuilt images lag behind

### Path E: Fully Automated Fresh Install (No Manual Installer UI)

```bash
# QEMU-first full unattended flow (installer FSM + SSH + provisioning)
make auto-fresh

# Explicit QEMU path
make qemu-full-auto

# Reproducibility harness (3 attempts by default)
make qemu-auto-verify

# Extended matrix (bus x disk-size x cpu, 2 attempts per case by default)
make qemu-matrix

# Rebuild unattended ISO locally when preseed changes (no download)
make rebuild-unattended-iso

# Generate script inventory/synthesis report
make scripts-audit

# VirtualBox conceptual stub path (non-operational in this phase)
make vbox-full-auto

# Force backend from orchestration script
./scripts/install-hurd-unattended.sh --backend podman --profile x11
```

**Best for**: reproducible "fresh installer -> SSH-ready configured guest" without manual keypresses/screenshots

### Path F: Minty Hurd (XFCE + Linux Mint theming over VNC)

```bash
# Boot the provisioned desktop image (requires images/hurd-working.qcow2,
# built per MINTY-HURD-README.md)
make minty-up

# The desktop autostarts at boot (see "Desktop modes" below).
# Plain VNC: connect a viewer to 127.0.0.1:5901 (password: hurdhurd)
# Browser:   the compose vnc profile's noVNC container on :6080
```

The Minty profile layers Linux Mint's arch-independent theme and menu
packages (LMDE 7 "gigi", pinned so Debian always wins for real code --
see `scripts/lmde7-apt-setup.sh`) over XFCE on Debian GNU/Hurd. Full
walkthrough: [MINTY-HURD-README.md](MINTY-HURD-README.md).

## Desktop modes: one image, two frontends

The provisioned image starts its desktop from `/etc/hurd-desktop.mode`
(staged by `scripts/hurd-desktop-autostart.sh`, verified on both
frontends):

| Mode | What starts at boot | For |
|---|---|---|
| `vnc` (shipped default) | XFCE rendered into **Xvfb :1**, exported by **x11vnc** on 5901 | The containerized QEMU route (podman/docker) -- headless hosts, browser access via the noVNC side-container |
| `xorg` | XFCE on the real VGA console via **startx** + the vesa driver | VirtualBox or QEMU with a display window |
| `none` | Nothing (SSH only) | Servers, CI |

Switch by writing the mode file inside the guest and rebooting, e.g.
`echo xorg > /etc/hurd-desktop.mode`.

### Running the image under VirtualBox

Convert the maintained qcow2 and attach it to a VM:

```bash
qemu-img convert -O vmdk images/hurd-working.qcow2 DebianGNUHurd.vmdk
```

VM settings that gnumach (1.8+git20260224) requires, found the hard
way: **HPET enabled** (the kernel panics in `hpet_init` without it),
**APIC and IOAPIC enabled** (it hangs before any console output with
them off), PIIX3/4 IDE storage, and either VMSVGA or VBoxVGA graphics
(Xorg drives both with the vesa driver). KVM paravirtualization is
fine. 2 GiB RAM / 2 vCPUs match the QEMU defaults.

Hurd-specific X11 plumbing (why the desktop is wired the way it is):
lightdm cannot spawn a greeter without a logind seat, dbus-launch's
default session bus dies on Hurd's missing SO_PEERCRED (sessions run
via `minty-hurd-xfce` against a TCP session bus instead), x11vnc needs
`-noshm`, and the session account starts via `runuser` so the
OOBE-expired password blocks logins without blocking the desktop.

## First login (out-of-box experience)

Published/provisioned images ship two generic accounts, `user`/`user`
and `root`/`root`, with their passwords **expired**: the first
interactive login (SSH password auth or the VNC console) asks you to
set your own password before you get a shell. Details and the staging
mechanism: [docs/08-REFERENCE/CREDENTIALS.md](docs/08-REFERENCE/CREDENTIALS.md);
image publishers run `make oobe` as the final step before shutting the
guest down.

Run artifacts are written per-attempt under `logs/runs/<run-id>/` with:
- `transcript.log`
- `serial.log`
- `fsm/state.log`
- `summary.log` (status, stage, failure_tag)

By default, unattended QEMU now uses a serial-log FSM (`scripts/qemu-install-serial-fsm.sh`) for deterministic
installer progress/failure detection, with OCR monitor FSM kept as an opt-in fallback (`FSM_BACKEND=ocr`).
On partition stall, the flow now performs active serial interaction/retry probes and captures
forensic artifacts under `logs/runs/<run-id>/fsm/stall-probe/` before final abort.

**Need help choosing?** See [docs/01-GETTING-STARTED/USAGE-MODES.md](docs/01-GETTING-STARTED/USAGE-MODES.md)

**Detailed setup**: See [docs/01-GETTING-STARTED/INSTALLATION.md](docs/01-GETTING-STARTED/INSTALLATION.md)

**Fast-track guide**: See [docs/01-GETTING-STARTED/QUICKSTART.md](docs/01-GETTING-STARTED/QUICKSTART.md)

---

## Documentation

**Complete documentation**: [docs/index.md](docs/index.md)

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
│   ├── index.md                   # Master documentation index
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

**See**: [docs/index.md](docs/index.md) for documentation standards

---

## Resources

**Documentation**: [docs/index.md](docs/index.md)

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

**For everything else**: [docs/index.md](docs/index.md)

---

[Complete Documentation](docs/index.md) | [Quickstart](docs/01-GETTING-STARTED/QUICKSTART.md) | [Troubleshooting](docs/06-TROUBLESHOOTING/)
