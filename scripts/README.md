# GNU/Hurd Docker - Scripts Reference

Comprehensive script reference for GNU/Hurd development environment setup, automation, and management.

**Total Scripts**: 31 | **Last Updated**: 2025-11-08

## Quick Navigation

**I need to...**
- [Setup development environment](#setup-scripts) → `setup-hurd-dev.sh`
- [Install packages](#installation-scripts) → `install-essentials-hurd.sh`
- [Automate complete setup](#automation-scripts) → `full-automated-setup.sh`
- [Download Hurd image](#image-management) → `download-released-image.sh`
- [Test the system](#testing-scripts) → `test-hurd-system.sh`
- [Manage snapshots](#utility-scripts) → `manage-snapshots.sh`
- [Connect to console](#utility-scripts) → `connect-console.sh`
- [Monitor QEMU](#utility-scripts) → `monitor-qemu.sh`

## Script Categories

- [Setup Scripts (4)](#setup-scripts) - Configure development environment
- [Installation Scripts (5)](#installation-scripts) - Install packages and services
- [Automation Scripts (3)](#automation-scripts) - Fully automated workflows
- [Utility Scripts (5)](#utility-scripts) - Management and monitoring tools
- [Image Management (2)](#image-management) - Download and manage disk images
- [Testing Scripts (5)](#testing-scripts) - Verify system functionality

---

## Setup Scripts

Scripts for configuring the GNU/Hurd development environment.

### setup-hurd-dev.sh

**WHY**: Install comprehensive development toolchain for Mach kernel and Hurd development.

**WHAT**: Installs GCC, Clang, Make, CMake, Autotools, MIG, GNU Mach headers, Hurd development packages, debuggers, and documentation tools (~1.5 GB).

**HOW**:
```bash
# Inside Hurd guest (via SSH or serial console)
cd /path/to/scripts
./setup-hurd-dev.sh
```

**Prerequisites**:
- Must run as root
- Network connectivity
- ~2 GB free disk space

**Time**: 20-30 minutes (depends on mirror speed)

**What it installs**:
- Core: GCC, Clang, Make, CMake, Autotools
- Mach: MIG, GNU Mach headers, Hurd development packages
- Debug: GDB, strace, ltrace
- VCS: Git
- Editors: Vim, Emacs, Nano
- Build: Meson, Ninja, SCons
- Docs: Doxygen, Graphviz

**Verification**:
```bash
gcc --version
mig --version
gdb --version
```

---

### setup-hurd-amd64.sh

**WHY**: Setup Debian GNU/Hurd x86_64 environment with dynamic 80GB disk.

**WHAT**: Downloads official Debian Hurd x86_64 image, converts to QCOW2, and resizes to 80GB with dynamic expansion.

**HOW**:
```bash
./setup-hurd-amd64.sh
```

**Prerequisites**:
- qemu-img installed
- ~500 MB free space for download
- ~1 GB free space for conversion

**Output**: `debian-hurd-amd64-80gb.qcow2`

**Time**: 5-10 minutes (depends on download speed)

---

### configure-users.sh

**WHY**: Setup secure user accounts with proper sudo access for development.

**WHAT**: Configures root and agents accounts with default passwords, sets up sudo NOPASSWD access, creates SSH directories with proper permissions.

**HOW**:
```bash
# Inside Hurd guest as root
./configure-users.sh
```

**What it configures**:
- Root password: `root` (change in production)
- Agents user: `agents` / `agents` (change in production)
- Sudo: NOPASSWD access for agents
- SSH: directories and authorized_keys files

**Security notes**:
- Default passwords are for development only
- Change passwords: `passwd root && passwd agents`
- Add SSH keys for key-based auth
- Review `/etc/sudoers.d/agents`

**Verification**:
```bash
# Switch to agents
su - agents

# Test sudo
sudo whoami  # Should output: root

# Test SSH (from host)
ssh agents@localhost -p 2222
```

---

### configure-shell.sh

**WHY**: Customize bash environment with Mach-specific paths, aliases, and development helpers.

**WHAT**: Configures environment variables (MACH_ROOT, PATH, MANPATH), colorized prompt with Git branch, development aliases, and Mach helper functions.

**HOW**:
```bash
# Run as the user you want to configure
./configure-shell.sh

# Or configure for another user
sudo -u agents ./configure-shell.sh

# Reload configuration
source ~/.bashrc
```

**Environment variables added**:
```bash
MACH_ROOT=/usr/src/gnumach
PATH=$PATH:/usr/lib/mig/bin
MANPATH=$MANPATH:/usr/share/man/mach
```

**Colorized prompt**:
```
[agents@hurd:/usr/src (main)] $
```

**Useful aliases**:
- `ll` - Detailed file listing
- `mig-version` - Show MIG version
- `mach-info` - System CPU/memory info
- `gs`, `ga`, `gc` - Git shortcuts
- `cmake-debug`, `cmake-release` - CMake with build type

**Helper functions**:
- `mach-rebuild` - Clean, build, and test
- `mach-sysinfo` - Comprehensive system report
- `mach-doc <term>` - Search Mach documentation

---

## Installation Scripts

Scripts for installing packages and services inside Hurd guest.

### install-ssh-hurd.sh

**WHY**: Enable SSH access to Hurd guest for remote development.

**WHAT**: Automated SSH server installation via serial console using expect. Installs openssh-server, random-egd (entropy daemon), configures password authentication, sets root password.

**HOW**:
```bash
# From host (with QEMU running)
SERIAL_PORT=5555 ./install-ssh-hurd.sh
```

**Prerequisites**:
- QEMU running with serial console on port 5555
- expect installed on host
- telnet access to serial port

**What it does**:
1. Connects to serial console
2. Logs in as root
3. Updates package lists
4. Installs openssh-server and random-egd
5. Configures sshd for password auth
6. Sets root password to `root`

**Time**: 5-10 minutes

**Test**:
```bash
ssh -p 2222 root@localhost
# Password: root
```

---

### install-essentials-hurd.sh

**WHY**: Install essential packages for basic system functionality and development.

**WHAT**: Installs SSH server, networking tools (curl, wget, net-tools), web browsers (lynx, w3m, links), and development essentials (build-essential, git, vim, python3).

**HOW**:
```bash
# Inside Hurd guest as root
./install-essentials-hurd.sh
```

**What it installs**:

**Phase 1 - SSH Server**:
- openssh-server
- random-egd (entropy generator)

**Phase 2 - Network Tools**:
- curl, wget, ca-certificates
- net-tools, dnsutils, telnet, netcat
- iputils-ping, traceroute, iproute2

**Phase 3 - Web Browsers**:
- lynx, w3m, links, elinks
- firefox-esr (if available)

**Phase 4 - Development**:
- build-essential, git, vim, emacs-nox
- python3, python3-pip
- make, cmake, autotools

**Post-install**:
- Adds utility aliases to ~/.bashrc
- Creates /etc/motd welcome banner
- Configures SSH

**Time**: 10-20 minutes

**Verification**:
```bash
curl --version
git --version
gcc --version
ssh -p 2222 root@localhost
```

---

### install-hurd-packages.sh

**WHY**: Install comprehensive package set for CLI and optional GUI development.

**WHAT**: Installs core development tools, programming languages (Python, Perl, Ruby, Go, Java), system utilities, Hurd-specific packages, and optional X11/Xfce GUI.

**HOW**:
```bash
# Inside Hurd guest as root
./install-hurd-packages.sh
```

**What it installs**:

**Core Development**:
- build-essential, gcc, g++
- make, cmake, autoconf, automake
- git, gdb, manpages-dev

**Languages**:
- Python 3 (+ pip, dev)
- Perl (+ libperl-dev)
- Ruby (optional)
- Go (optional)
- OpenJDK 17 (optional)

**System Utilities**:
- curl, wget, htop
- screen, tmux, rsync
- zip, unzip, tree
- net-tools, dnsutils

**Hurd-Specific**:
- hurd-dev, gnumach-dev, mig

**GUI (Optional)**:
- X11 (xorg, xterm, xinit)
- Xfce (xfce4, xfce4-goodies)
- Editors (emacs, geany)
- Apps (firefox-esr, gimp)

**Post-install**:
- Creates ~/workspace and ~/projects
- Configures bash aliases
- Sets up 9p mount point at /mnt/host

**Time**: 30-60 minutes (with GUI), 10-20 minutes (without)

---

### install-nodejs-hurd.sh

**WHY**: Install Node.js for JavaScript development with multiple fallback methods.

**WHAT**: Attempts Node.js installation via Debian repositories (most reliable), or builds from source (time-consuming). Handles i386 architecture limitations.

**HOW**:
```bash
# Inside Hurd guest as root
./install-nodejs-hurd.sh
```

**Installation methods** (tried in order):

**Method 1 - Debian Repos** (Recommended):
- Installs nodejs and npm from official Debian repositories
- Likely older version (Node 12-18) but stable
- Configures npm global directory for non-root installs

**Method 2 - Build from Source** (Advanced):
- Downloads Node.js v16.20.2 source (LTS, i386-compatible)
- Compiles with conservative flags for i386
- Takes 30-60 minutes
- May fail on Hurd due to platform incompatibilities

**Time**: 5-10 minutes (repos), 30-60 minutes (source)

**Verification**:
```bash
node --version
npm --version
```

**Note**: Node.js may not be fully compatible with GNU/Hurd i386. Consider using Python as alternative.

---

### install-claude-code-hurd.sh

**WHY**: Install Claude Code CLI for AI-assisted development (experimental on Hurd).

**WHAT**: Attempts installation via native installer or npm fallback. Handles platform incompatibilities.

**HOW**:
```bash
# Inside Hurd guest (requires Node.js)
./install-claude-code-hurd.sh
```

**Prerequisites**:
- Node.js 18+ (install with install-nodejs-hurd.sh)
- npm

**Installation methods**:

**Method 1 - Native Installer**:
- Downloads official installer from claude.ai
- Likely to fail on Hurd (requires glibc, amd64)

**Method 2 - NPM**:
- Installs via `npm install -g @anthropic-ai/claude-code`
- May fail due to platform-specific binaries

**Time**: 5-10 minutes (if successful)

**Note**: Claude Code is not officially supported on GNU/Hurd. Consider using from host machine or web interface.

---

## Automation Scripts

Fully automated workflows for complete system setup.

### full-automated-setup.sh

**WHY**: Automate complete GNU/Hurd setup from boot to production-ready development environment.

**WHAT**: Automated workflow that waits for boot, sets up users, installs development tools, and configures shell environment. Requires no user intervention.

**HOW**:
```bash
# From host (after starting container)
./full-automated-setup.sh
```

**What it does**:

**Phase 1 - Wait for Boot**:
- Monitors SSH port for up to 10 minutes
- Detects when Hurd has booted

**Phase 2 - Root Password**:
- Sets root password to `root`
- Forces password change on first login

**Phase 3 - Create agents User**:
- Creates agents user with password `agents`
- Configures sudo NOPASSWD
- Forces password change on first login

**Phase 4 - Mount Scripts**:
- Mounts 9p filesystem at /mnt/scripts
- Makes setup scripts accessible

**Phase 5 - Install Dev Tools**:
- Runs automated package installation
- Installs ~1.5 GB of packages
- Takes 20-30 minutes

**Phase 6 - Configure Shell**:
- Configures bash for root and agents
- Adds Mach environment variables
- Adds development aliases

**Phase 7 - Verification**:
- Tests GCC, MIG, GDB, Git
- Checks Mach and Hurd headers
- Reports disk usage

**Time**: 30-45 minutes total

**Security Warning**: Sets default passwords that expire on first login. Change immediately.

---

### bringup-and-provision.sh

**WHY**: Orchestrate container boot, SSH enablement, and basic provisioning.

**WHAT**: Boots container, enables SSH via serial automation, fixes Debian sources, creates agents sudo user, installs basic dev toolchain.

**HOW**:
```bash
# From host
ROOT_PASS=root AGENTS_PASS=agents ./bringup-and-provision.sh
```

**Prerequisites**:
- docker, docker-compose
- telnet, expect, sshpass on host

**Environment variables**:
- `ROOT_PASS` - Root password (default: root)
- `AGENTS_PASS` - Agents password (default: agents)
- `SSH_PORT` - SSH port (default: 2222)
- `SERIAL_PORT` - Serial port (default: 5555)

**What it does**:
1. Boots container with docker-compose
2. Waits for serial console
3. Enables SSH via install-ssh-hurd.sh
4. Fixes Debian-Ports sources
5. Creates agents sudo user
6. Installs basic dev tools (gcc, make, git, vim)

**Time**: 10-20 minutes

**Test**:
```bash
ssh -p 2222 root@localhost
# Or
ssh -p 2222 agents@localhost
```

---

### fix-sources-hurd.sh

**WHY**: Configure correct Debian-Ports repositories and upgrade system packages.

**WHAT**: Fixes /etc/apt/sources.list for Debian-Ports (unstable + unreleased), installs keyring, upgrades system, configures networking, enables SSH.

**HOW**:
```bash
# From host
ROOT_PASS=root ./fix-sources-hurd.sh -h localhost -p 2222
```

**Options**:
- `-h HOST` - SSH host (default: localhost)
- `-p PORT` - SSH port (default: 2222)

**What it does**:
1. Backs up existing sources.list
2. Configures Debian-Ports repositories:
   - deb http://deb.debian.org/debian-ports unstable main
   - deb http://deb.debian.org/debian-ports unreleased main
3. Ensures DNS works (adds fallback nameservers)
4. Installs debian-ports-archive-keyring
5. Runs dist-upgrade
6. Pins default release to unstable
7. Installs networking helpers and SSH
8. Configures eth0 for DHCP
9. Enables SSH service

**Time**: 10-20 minutes (depends on upgrade size)

---

## Utility Scripts

Management, monitoring, and maintenance tools.

### boot_hurd.sh

**WHY**: Boot Hurd from a configuration file with customizable QEMU settings.

**WHAT**: Reads configuration file and constructs QEMU command with specified CPU, memory, disk, network, and graphics settings.

**HOW**:
```bash
./boot_hurd.sh <config_file>
```

**Usage**:
```bash
./boot_hurd.sh qemu-config.conf
```

**Configuration file format**:
```bash
ARCH=i386
CPU=host
MEMORY=1024M
SMP=1
ENABLE_KVM=yes
DISK_IMAGE=/path/to/debian-hurd.qcow2
NETWORK_MODE=user
NETWORK_DEVICE=e1000
HOST_FWD_SSH=tcp::2222-:22
VGA_TYPE=std
DISPLAY_TYPE=gtk
```

**Prerequisites**:
- qemu-system-i386 or qemu-system-x86_64
- Valid QCOW2 disk image

---

### connect-console.sh

**WHY**: Easily connect to QEMU serial console or monitor for debugging.

**WHAT**: Automatically finds and connects to QEMU serial console or monitor socket.

**HOW**:
```bash
# Connect to serial console
./connect-console.sh

# Connect to QEMU monitor
./connect-console.sh --monitor

# Show logs with PTY path
./connect-console.sh --logs
```

**Options**:
- `-c, --container <name>` - Container name (default: gnu-hurd-dev)
- `-m, --monitor` - Connect to QEMU monitor instead of serial
- `-l, --logs` - Show logs to find PTY path
- `-h, --help` - Show help

**Serial console**:
- Interactive terminal for GNU/Hurd
- Exit: Ctrl+A then K (screen) or Ctrl+C

**Monitor**:
- QEMU control interface
- Commands: info status, savevm, loadvm, quit
- Exit: Ctrl+C

**Prerequisites**:
- screen or socat (for connections)
- Container must be running
- QEMU started with -serial pty

---

### manage-snapshots.sh

**WHY**: Manage QCOW2 snapshots for safe experimentation and rollback.

**WHAT**: Create, list, restore, and delete QCOW2 snapshots. Create full backups.

**HOW**:
```bash
# List snapshots
./manage-snapshots.sh list

# Create snapshot
./manage-snapshots.sh create pre-upgrade

# Restore snapshot (DESTRUCTIVE)
./manage-snapshots.sh restore pre-upgrade

# Delete snapshot
./manage-snapshots.sh delete old-snapshot

# Show image info
./manage-snapshots.sh info

# Create full backup
./manage-snapshots.sh backup /backup/hurd-backup.qcow2
```

**Options**:
- `-i, --image <path>` - Specify QCOW2 image
- `-h, --help` - Show help

**Environment**:
- `QCOW2_IMAGE` - Default image path

**Prerequisites**:
- qemu-img (from qemu-utils package)

**Warning**: Restore is DESTRUCTIVE. All changes since snapshot will be lost.

---

### monitor-qemu.sh

**WHY**: Monitor QEMU performance metrics in real-time.

**WHAT**: Displays CPU usage, memory usage, runtime, and QEMU monitor status. Refreshes every 2 seconds.

**HOW**:
```bash
./monitor-qemu.sh
```

**Displays**:
- Process ID
- Runtime
- CPU usage percentage
- Memory usage (percentage and MB)
- QEMU monitor status
- VM information (if monitor available)

**Prerequisites**:
- QEMU process running
- Optional: QEMU monitor socket at /tmp/qemu-monitor.sock

**Exit**: Ctrl+C

---

### health-check.sh

**WHY**: Verify container health for Docker health checks.

**WHAT**: Checks if QEMU x86_64 process is running, SSH and HTTP ports accessible.

**HOW**:
```bash
./health-check.sh
```

**Checks**:
1. QEMU x86_64 process running (critical)
2. SSH port 2222 accessible (informational)
3. HTTP port 8080 accessible (informational)

**Exit codes**:
- 0 - Healthy (QEMU running)
- 1 - Unhealthy (QEMU not running)

**Note**: SSH/HTTP not accessible is not a failure (VM may be booting).

---

## Image Management

Scripts for downloading and managing Hurd disk images.

### download-released-image.sh

**WHY**: Download official Debian GNU/Hurd QEMU images from GitHub releases.

**WHAT**: Downloads latest or specific version of Debian Hurd x86_64 QCOW2 image from GitHub Releases, verifies checksums, extracts if compressed.

**HOW**:
```bash
# Download latest compressed image
./download-released-image.sh

# Download specific version uncompressed
./download-released-image.sh --version 1.0.0 --uncompressed

# Download to custom directory
./download-released-image.sh --output /data/images

# Skip checksum verification (not recommended)
./download-released-image.sh --no-verify
```

**Options**:
- `-v, --version VERSION` - Specific version (default: latest)
- `-o, --output DIR` - Output directory (default: ./images)
- `-u, --uncompressed` - Download uncompressed (default: compressed)
- `-n, --no-verify` - Skip checksum verification

**Environment variables**:
- `REPO` - Repository name (default: Oichkatzelesfrettschen/gnu-hurd-docker)
- `VERSION` - Release version (default: latest)
- `OUTPUT_DIR` - Output directory (default: ./images)
- `COMPRESSED` - Download compressed (default: true)
- `VERIFY_CHECKSUM` - Verify checksums (default: true)

**What it does**:
1. Creates output directory
2. Downloads image from GitHub releases
3. Downloads checksum file
4. Verifies checksum (if enabled)
5. Extracts compressed image (if compressed)
6. Renames to standard filename
7. Shows image information

**Time**: 10-30 minutes (depends on download speed)

**Output**: `debian-hurd-amd64.qcow2` in output directory

---

### qmp-helper.py

**WHY**: Interact with QEMU Machine Protocol for advanced VM control.

**WHAT**: Python helper script for sending QMP commands to QEMU.

**HOW**:
```bash
python3 qmp-helper.py <command>
```

**Note**: This script needs review and documentation. Python docstrings missing.

---

## Testing Scripts

Scripts for testing system functionality and analyzing codebase.

### test-hurd-system.sh

**WHY**: Comprehensive system testing to verify complete functionality.

**WHAT**: Tests container status, boot completion, user authentication, sudo access, C compilation, package management, filesystem operations, and Hurd features.

**HOW**:
```bash
./test-hurd-system.sh
```

**Environment variables**:
- `SSH_PORT` - SSH port (default: 2222)
- `SSH_HOST` - SSH host (default: localhost)
- `ROOT_PASSWORD` - Root password (default: root)
- `AGENTS_PASSWORD` - Agents password (default: agents)
- `TIMEOUT` - Boot timeout in seconds (default: 300)

**Tests performed**:

**Test 1 - Container Running**:
- Verifies gnu-hurd-dev container is running

**Test 2 - Boot Completion**:
- Waits up to 5 minutes for SSH port to respond

**Test 3 - Root User Access**:
- Tests SSH authentication as root
- Displays system information

**Test 4 - Agents User Access**:
- Tests SSH authentication as agents
- Verifies sudo NOPASSWD configuration

**Test 5 - C Compilation**:
- Creates test C program
- Compiles with gcc
- Executes and verifies output

**Test 6 - Package Management**:
- Tests apt-cache search

**Test 7 - Filesystem Operations**:
- Creates directories and files
- Tests read/write operations
- Cleans up

**Test 8 - Hurd Features**:
- Checks running Hurd servers
- Verifies /hurd directory

**Time**: 5-10 minutes

**Exit codes**:
- 0 - All tests passed
- 1 - Some tests failed

**Prerequisites**:
- sshpass, netcat
- Container running

---

### test-docker-provision.sh

**WHY**: Test Docker provisioning workflow locally before CI/CD.

**WHAT**: Builds provisioning Docker image, runs provisioning workflow, verifies output QCOW2 image.

**HOW**:
```bash
./test-docker-provision.sh
```

**Prerequisites**:
- docker, docker-compose
- Base QCOW2 image
- /dev/kvm (recommended for speed)

**What it does**:
1. Checks prerequisites (docker, docker-compose, KVM)
2. Locates or converts base image
3. Builds provisioning Docker image
4. Runs provisioning (10-15 minutes with KVM)
5. Verifies provisioned image created
6. Shows image details

**Time**: 15-20 minutes (with KVM), 60+ minutes (without KVM)

---

### analyze-script-complexity.sh

**WHY**: Establish quantitative baselines for script quality and maintainability.

**WHAT**: Measures LOC, cyclomatic complexity, dependencies, documentation ratio for all scripts. Outputs JSON metrics.

**HOW**:
```bash
./analyze-script-complexity.sh > /tmp/script-metrics.json
```

**Metrics measured**:
- Total lines, code lines, comment lines, blank lines
- Function count
- Cyclomatic complexity (if/for/while/case count)
- Error handling (exit points, set -e)
- External dependencies
- Comment ratio
- Header presence
- Max function lines
- Max nesting depth
- Global variables
- Maintainability rating (good/fair/poor)

**Output**: JSON format with per-script metrics

**Prerequisites**:
- POSIX shell (sh)
- Standard Unix tools (grep, awk, sed, wc)

---

### generate-complexity-report.sh

**WHY**: Process raw metrics into actionable insights and recommendations.

**WHAT**: Analyzes JSON metrics and produces structured report with rankings, anti-patterns, and recommendations.

**HOY**:
```bash
./generate-complexity-report.sh > /tmp/script-complexity-report.json
```

**Prerequisites**:
- Input: /tmp/raw-metrics.json (from analyze-script-complexity.sh)
- jq (for full analysis)

**Output sections**:
- Overall metrics (totals, averages)
- Complexity rankings (most complex, largest, simplest)
- Dependency rankings
- Documentation rankings
- Anti-patterns found (oversized scripts, deep nesting, poor maintainability)
- Test coverage gaps
- Recommendations

**Usage**:
```bash
# Generate metrics
./analyze-script-complexity.sh > /tmp/raw-metrics.json

# Generate report
./generate-complexity-report.sh > /tmp/report.json

# View report
cat /tmp/report.json | jq .
```

---

### audit-documentation.sh

**WHY**: Find documentation consolidation opportunities and stale references.

**WHAT**: Analyzes all markdown files for duplicates, outdated content, file counts, and potential issues.

**HOW**:
```bash
./audit-documentation.sh
```

**What it checks**:
- File counts (top-level, docs/)
- Duplicate names
- Files with GUIDE, QUICKSTART, CI/CD in names
- Installation-related files
- i386 references (may be outdated for x86_64)
- qemu-system-i386 references
- File sizes
- Total documentation lines
- Files with "lesson" or "learned"
- Deprecated/outdated markers
- Old dates (pre-2025)

**Output**: Text report with findings and next steps

**Note**: This script is ad-hoc and should be replaced by formal audit process.

---

## Workflows

### Standard Setup Workflow

**Purpose**: Manual step-by-step setup for learning and customization.

```bash
# 1. Boot into Hurd and login as root
ssh root@localhost -p 2222

# 2. Install development tools
./setup-hurd-dev.sh
# Time: 20-30 minutes

# 3. Configure users
./configure-users.sh

# 4. Configure shell (as root)
./configure-shell.sh

# 5. Switch to agents user and configure shell
su - agents
./configure-shell.sh

# 6. Test configuration
source ~/.bashrc
mach-sysinfo
mig-version
```

**Time**: 30-45 minutes total

---

### Automated Setup Workflow

**Purpose**: Fastest path to production-ready environment.

```bash
# 1. Start container
docker-compose up -d

# 2. Run automation
./full-automated-setup.sh
# Time: 30-45 minutes (unattended)

# 3. Verify
./test-hurd-system.sh

# 4. Login and change passwords
ssh -p 2222 root@localhost
passwd  # Change from 'root'

su - agents
passwd  # Change from 'agents'
```

**Time**: 40-60 minutes total (mostly unattended)

---

### Quick Start Workflow (Existing Image)

**Purpose**: Fastest boot with pre-configured image.

```bash
# 1. Download pre-provisioned image
./download-released-image.sh

# 2. Start container
docker-compose up -d

# 3. Connect
ssh -p 2222 root@localhost
```

**Time**: 15-30 minutes (mostly download)

---

### Development Workflow

**Purpose**: Daily development with snapshots.

```bash
# 1. Create snapshot before changes
./manage-snapshots.sh create pre-changes

# 2. Make changes, develop, test
ssh -p 2222 agents@localhost

# 3. If something breaks, restore
./manage-snapshots.sh restore pre-changes

# 4. If changes work, create new snapshot
./manage-snapshots.sh create working-state
```

---

## Troubleshooting

### Container Issues

**Issue**: Container not starting

**Cause**: Docker daemon not running or permissions issue

**Fix**:
```bash
# Check Docker status
sudo systemctl status docker

# Start Docker
sudo systemctl start docker

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker
```

---

**Issue**: Container starts but QEMU not running

**Cause**: QCOW2 image missing or corrupted

**Fix**:
```bash
# Check container logs
docker-compose logs

# Verify image exists
ls -lh images/*.qcow2

# Download fresh image
./download-released-image.sh
```

---

### Boot Issues

**Issue**: Hurd not booting (timeout)

**Cause**: Insufficient resources or KVM not available

**Fix**:
```bash
# Check KVM availability
ls -l /dev/kvm

# Increase timeout
TIMEOUT=600 ./test-hurd-system.sh

# Check VNC console
vncviewer localhost:5901

# Check serial console
./connect-console.sh
```

---

**Issue**: Boot succeeds but SSH not accessible

**Cause**: SSH not installed or networking issue

**Fix**:
```bash
# Connect via serial console
./connect-console.sh

# Install SSH manually
apt-get update
apt-get install -y openssh-server random-egd
/etc/init.d/ssh start

# Or use automation
./install-ssh-hurd.sh
```

---

### Script Execution Issues

**Issue**: Scripts fail with "Permission denied"

**Cause**: Scripts not executable

**Fix**:
```bash
chmod +x scripts/*.sh
```

---

**Issue**: setup-hurd-dev.sh fails with "Unable to locate package"

**Cause**: No network or outdated package lists

**Fix**:
```bash
# Test network
ping -c 3 8.8.8.8

# Update package lists
apt-get update

# Fix sources if needed
./fix-sources-hurd.sh
```

---

**Issue**: configure-users.sh fails: "sudo: command not found"

**Cause**: sudo not installed

**Fix**:
```bash
# Script auto-installs, but if it fails:
apt-get update
apt-get install -y sudo
./configure-users.sh
```

---

### SSH Access Issues

**Issue**: SSH connection refused

**Cause**: SSH not running or wrong port

**Fix**:
```bash
# Check if SSH is running (via serial console)
./connect-console.sh
/etc/init.d/ssh status

# Start SSH
/etc/init.d/ssh start

# Check port forwarding
docker port gnu-hurd-dev
```

---

**Issue**: SSH authentication failed

**Cause**: Wrong password or user not configured

**Fix**:
```bash
# Connect via serial console
./connect-console.sh

# Reset root password
passwd root

# Reconfigure users
./configure-users.sh
```

---

### Performance Issues

**Issue**: System very slow

**Cause**: KVM not available or insufficient resources

**Fix**:
```bash
# Check KVM
ls -l /dev/kvm

# Check resource allocation in docker-compose.yml
# Increase CPU/memory limits

# Enable KVM in QEMU args
# Add -enable-kvm to entrypoint.sh
```

---

**Issue**: High CPU usage

**Cause**: Normal during package installation or compilation

**Fix**:
```bash
# Monitor QEMU
./monitor-qemu.sh

# Check what's running (via SSH)
ssh -p 2222 root@localhost
top
ps aux
```

---

## Best Practices

### Security

1. **Change default passwords immediately**
   ```bash
   passwd root
   passwd agents
   ```

2. **Use SSH keys instead of passwords**
   ```bash
   # On host
   ssh-keygen -t ed25519

   # Copy to guest
   ssh-copy-id -p 2222 root@localhost
   ssh-copy-id -p 2222 agents@localhost
   ```

3. **Review sudo configuration**
   ```bash
   cat /etc/sudoers.d/agents
   # Consider requiring password for production
   ```

4. **Keep system updated**
   ```bash
   apt-get update && apt-get upgrade
   ```

---

### Snapshots

1. **Create snapshot before major changes**
   ```bash
   ./manage-snapshots.sh create pre-upgrade
   ./manage-snapshots.sh create pre-kernel-build
   ```

2. **Document snapshot purpose**
   - Use descriptive names: `pre-upgrade`, `working-gcc-build`
   - Keep snapshot list manageable (delete old ones)

3. **Test restoration periodically**
   ```bash
   ./manage-snapshots.sh list
   ./manage-snapshots.sh restore <name>
   ```

---

### Development

1. **Use version control for code**
   ```bash
   git init
   git add .
   git commit -m "Initial commit"
   ```

2. **Test incrementally**
   - Don't make large changes without testing
   - Use `./test-hurd-system.sh` after configuration changes

3. **Document customizations**
   - Keep notes in project CLAUDE.md
   - Track manual changes for reproducibility

---

### Monitoring

1. **Check system health regularly**
   ```bash
   ./health-check.sh
   ./monitor-qemu.sh
   ```

2. **Review logs for issues**
   ```bash
   docker-compose logs
   ssh -p 2222 root@localhost 'dmesg | tail'
   ```

3. **Monitor disk usage**
   ```bash
   du -sh images/*.qcow2
   qemu-img info images/debian-hurd-amd64.qcow2
   ```

---

## Reference

### Script Statistics

- **Total scripts**: 31
- **Total lines**: ~8,000 (estimated)
- **Setup scripts**: 4
- **Installation scripts**: 5
- **Automation scripts**: 3
- **Utility scripts**: 5
- **Image management**: 2
- **Testing scripts**: 5
- **Analysis scripts**: 3
- **Deprecated**: 2-3

### Common Script Patterns

**Error handling**:
```bash
set -euo pipefail  # Exit on error, undefined vars, pipe failures
```

**Colored output**:
```bash
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'
echo -e "${GREEN}[SUCCESS]${NC} Message"
```

**User prompts**:
```bash
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi
```

**SSH execution**:
```bash
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no \
    -p "$PORT" "user@$HOST" 'command'
```

### Environment Variables

Global variables used across scripts:

- `SSH_PORT` - SSH port (default: 2222)
- `SSH_HOST` - SSH host (default: localhost)
- `ROOT_PASSWORD` - Root password (default: root)
- `AGENTS_PASSWORD` - Agents password (default: agents)
- `SERIAL_PORT` - Serial console port (default: 5555)
- `QCOW2_IMAGE` - QCOW2 image path
- `TIMEOUT` - Operation timeout

### Related Documentation

- Parent README: `/home/eirikr/Playground/gnu-hurd-docker/README.md`
- Architecture docs: `../docs/ARCHITECTURE.md`
- Image building: `../docs/HURD-IMAGE-BUILDING.md`
- QEMU optimization: `../docs/QEMU-OPTIMIZATION-2025.md`

---

**Last Updated**: 2025-11-08
**Maintainer**: GNU/Hurd Docker Project
**License**: See repository root
