# Reference Documentation

**Last Updated**: 2025-11-07
**Section**: 08-REFERENCE
**Purpose**: Complete reference materials for scripts and credentials

---

## Overview

This section provides comprehensive reference documentation for automation scripts and access credentials in the GNU/Hurd x86_64 Docker environment.

**Audience**: All users (quick reference)

**Use Case**: Look up script usage, check default credentials, find automation tools

---

## Documents in This Section

### [SCRIPTS.md](SCRIPTS.md)
**Complete reference for all 21 automation scripts**

**Categories**:
1. **Setup Scripts** - Download images, initialize environments
2. **Installation Scripts** - Install software inside Hurd guest
3. **Configuration Scripts** - Configure users, shell, system settings
4. **Provisioning Scripts** - End-to-end automated workflows
5. **Management Scripts** - Snapshots, monitoring, access
6. **Testing Scripts** - Validation, system tests, audits

**Key Scripts**:
- `setup-hurd-amd64.sh` - Setup x86_64 image with 80GB expansion
- `install-ssh-hurd.sh` - Install SSH server via serial console
- `configure-users.sh` - Configure root and agents accounts
- `manage-snapshots.sh` - QCOW2 snapshot management
- `monitor-qemu.sh` - Real-time performance monitoring
- `bringup-and-provision.sh` - Orchestrated provisioning

**When to use**: Find script for specific task, learn script usage, automate operations

---

### [CREDENTIALS.md](CREDENTIALS.md)
**Access credentials, SSH configuration, and security**

**Topics**:
- Default user accounts (root, agents)
- SSH access methods
- Serial console access
- Password management
- SSH key-based authentication
- Port mappings (2222, 5555)
- Network configuration
- Security recommendations (dev vs production)
- Troubleshooting access issues

**Key Information**:
- Root password: `root`
- Agents password: `agents`
- SSH port: `2222`
- Serial console port: `5555`

**When to use**: Check default passwords, configure SSH, troubleshoot access

---

## Quick Reference

### Default Credentials

| User | Password | Sudo | Description |
|------|----------|------|-------------|
| root | root | N/A | System administrator (UID 0) |
| agents | agents | NOPASSWD | Development user with sudo |

**Security Note**: Change passwords for production use!

---

### Access Methods

| Method | Port | Usage |
|--------|------|-------|
| SSH | 2222 | Primary access (terminal, SCP, SFTP) |
| Serial Console | 5555 | Emergency access (telnet) |
| Docker Exec | N/A | Container shell (not guest!) |

---

### Common Script Operations

**Setup x86_64 environment**:
```bash
./scripts/setup-hurd-amd64.sh
```

**Install SSH server**:
```bash
./scripts/install-ssh-hurd.sh
```

**Configure users**:
```bash
./scripts/configure-users.sh
```

**Create snapshot**:
```bash
./scripts/manage-snapshots.sh create snapshot-name
```

**Monitor performance**:
```bash
./scripts/monitor-qemu.sh
```

**Full provisioning** (automated):
```bash
ROOT_PASS=root AGENTS_PASS=agents ./scripts/bringup-and-provision.sh
```

---

## Quick Navigation

**Getting Started**:
- [Installation](../01-GETTING-STARTED/INSTALLATION.md) - Setup environment
- [Quickstart](../01-GETTING-STARTED/QUICKSTART.md) - Fast start guide

**Configuration** (customize):
- [User Configuration](../03-CONFIGURATION/USER-CONFIGURATION.md) - Manage users
- [Port Forwarding](../03-CONFIGURATION/PORT-FORWARDING.md) - Configure ports

**Operation** (daily use):
- [Interactive Access](../04-OPERATION/INTERACTIVE-ACCESS.md) - SSH, serial console
- [Snapshots](../04-OPERATION/SNAPSHOTS.md) - State management
- [Monitoring](../04-OPERATION/MONITORING.md) - Performance

**Troubleshooting** (when things break):
- [SSH Issues](../06-TROUBLESHOOTING/SSH-ISSUES.md) - Access problems
- [Common Issues](../06-TROUBLESHOOTING/COMMON-ISSUES.md) - General problems

---

## Script Categories

### Setup Scripts

**Purpose**: Initialize environments, download images

| Script | Description | Time |
|--------|-------------|------|
| `download-image.sh` | Download Debian Hurd image | 5-10 min |
| `setup-hurd-amd64.sh` | Setup x86_64 with 80GB disk | 10-15 min |
| `full-automated-setup.sh` | End-to-end setup (deprecated) | 45-60 min |

**Use**: Initial setup, fresh installations

**Reference**: [SCRIPTS.md - Setup Scripts](SCRIPTS.md#setup-scripts)

---

### Installation Scripts

**Purpose**: Install software inside Hurd guest

| Script | Description | Disk Space | Time |
|--------|-------------|------------|------|
| `install-ssh-hurd.sh` | Install SSH server | ~50 MB | 5-15 min |
| `install-essentials-hurd.sh` | Essential packages | ~500 MB | 10-20 min |
| `install-nodejs-hurd.sh` | Node.js and npm | ~200 MB | 5-10 min |
| `setup-hurd-dev.sh` | Full dev toolchain | ~1.5 GB | 20-30 min |

**Use**: Software installation, development setup

**Reference**: [SCRIPTS.md - Installation Scripts](SCRIPTS.md#installation-scripts)

---

### Configuration Scripts

**Purpose**: Configure users, shell, system settings

| Script | Description | Time |
|--------|-------------|------|
| `configure-users.sh` | Setup root and agents users | <1 min |
| `configure-shell.sh` | Bash environment, aliases | <1 min |
| `fix-sources-hurd.sh` | Fix apt sources (Debian-Ports) | 2-5 min |

**Use**: User management, shell customization, package sources

**Reference**: [SCRIPTS.md - Configuration Scripts](SCRIPTS.md#configuration-scripts)

---

### Management Scripts

**Purpose**: Snapshots, monitoring, access

| Script | Description | Time |
|--------|-------------|------|
| `manage-snapshots.sh` | QCOW2 snapshot management | Instant |
| `monitor-qemu.sh` | Real-time performance monitoring | Continuous |
| `connect-console.sh` | Connect to serial console | Instant |

**Use**: State management, performance analysis, emergency access

**Reference**: [SCRIPTS.md - Management Scripts](SCRIPTS.md#management-scripts)

---

### Testing Scripts

**Purpose**: Validation, system tests, audits

| Script | Description | Time |
|--------|-------------|------|
| `test-docker.sh` | Docker build/deployment tests | 5-10 min |
| `test-hurd-system.sh` | Comprehensive system validation | 5-15 min |
| `validate-config.sh` | Config file validation | <1 min |

**Use**: Verify functionality, CI/CD testing, quality assurance

**Reference**: [SCRIPTS.md - Testing Scripts](SCRIPTS.md#testing-scripts)

---

## Credentials Reference

### SSH Access

**Default Configuration**:
```bash
# Connect as root
ssh -p 2222 root@localhost
# Password: root

# Connect as agents
ssh -p 2222 agents@localhost
# Password: agents
```

**SSH Config** (convenience):
```bash
# ~/.ssh/config
Host hurd-dev
    HostName localhost
    Port 2222
    User root
    IdentityFile ~/.ssh/id_ed25519_hurd

Host hurd-agents
    HostName localhost
    Port 2222
    User agents
    IdentityFile ~/.ssh/id_ed25519_hurd
```

**Reference**: [CREDENTIALS.md - SSH Access](CREDENTIALS.md#ssh-access)

---

### Serial Console Access

**Connection**:
```bash
# Via telnet
telnet localhost 5555

# Via script
./scripts/connect-console.sh
```

**Login**:
- Username: `root`
- Password: `root` (after provisioning) or empty (before)

**Exit**: `Ctrl+]` then type `quit`

**Reference**: [CREDENTIALS.md - Serial Console](CREDENTIALS.md#serial-console-access)

---

### Security Recommendations

**Development** (acceptable):
- Default passwords OK for localhost-only access
- Expose SSH on `127.0.0.1:2222` only

**Production** (CRITICAL):
- **Change all default passwords**:
  ```bash
  passwd root
  passwd agents
  ```
- **Use SSH key-based authentication**:
  ```bash
  ssh-copy-id -i ~/.ssh/id_ed25519.pub -p 2222 root@localhost
  ```
- **Disable password authentication**:
  ```bash
  sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
  systemctl restart ssh
  ```
- **Restrict SSH access** to specific hosts/networks
- **Enable firewall rules** on Docker host

**Reference**: [CREDENTIALS.md - Security](CREDENTIALS.md#security-recommendations)

---

## For Script Developers

**Best Practices**:
1. Follow existing style and structure
2. Add comprehensive comments
3. Validate with shellcheck: `shellcheck -S error script.sh`
4. Test on clean Debian Hurd installation
5. Update [SCRIPTS.md](SCRIPTS.md) with changes

**Script Template**:
```bash
#!/bin/bash
# Script Name - Purpose
# Usage: ./script.sh [options]
set -e  # Exit on error

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
echo_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Main script logic
echo_info "Starting script..."
# [commands here]
echo_success "Script complete"
```

---

## For System Administrators

**Daily Reference**:
- Check default passwords: [CREDENTIALS.md](CREDENTIALS.md#default-user-accounts)
- Find automation script: [SCRIPTS.md](SCRIPTS.md) (alphabetical index)
- Verify security config: [CREDENTIALS.md - Security](CREDENTIALS.md#security-recommendations)

**Maintenance**:
- Rotate passwords every 90 days (production)
- Update SSH keys annually
- Review script functionality quarterly

**Documentation**:
- Update [SCRIPTS.md](SCRIPTS.md) when adding/modifying scripts
- Update [CREDENTIALS.md](CREDENTIALS.md) when changing access methods

---

## Troubleshooting

**Script fails**:
- Check execution permissions: `chmod +x scripts/*.sh`
- Verify dependencies: See [SCRIPTS.md](SCRIPTS.md) - script requirements
- Review script output for errors

**Cannot access system**:
- Try all access methods: SSH, serial console, Docker exec
- Check credentials: [CREDENTIALS.md](CREDENTIALS.md)
- See [SSH Issues](../06-TROUBLESHOOTING/SSH-ISSUES.md)

**Security concerns**:
- Review [CREDENTIALS.md - Security](CREDENTIALS.md#security-recommendations)
- Change default passwords immediately
- Implement SSH key-based auth

---

[← Back to Documentation Index](../INDEX.md)
