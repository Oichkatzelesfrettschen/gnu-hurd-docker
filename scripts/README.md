# GNU/Hurd Docker - Setup Scripts

This directory contains automation scripts for configuring a "riced" (fully-configured) GNU/Hurd development environment.

## Scripts Overview

### 1. setup-hurd-dev.sh

**Purpose:** Install comprehensive development toolchain inside Hurd guest

**What it installs:**
- Core compilation tools (GCC, Clang, Make, CMake, Autotools)
- Mach-specific utilities (MIG, GNU Mach headers, Hurd development packages)
- Debugging tools (GDB, strace, ltrace)
- Version control (Git)
- Text editors (Vim, Emacs, Nano)
- Build systems (Meson, Ninja, SCons)
- Documentation tools (Doxygen, Graphviz, man pages)
- Networking utilities (netcat, tcpdump, curl, wget)
- Terminal multiplexers (screen, tmux)

**Disk space:** ~1.5 GB
**Time:** 20-30 minutes (depends on mirror speed)

**Usage:**
```bash
# Inside Hurd guest (via SSH or serial console)
cd /path/to/scripts
./setup-hurd-dev.sh
```

**Requirements:**
- Must run as root
- Network connectivity (for apt-get)
- Sufficient disk space (~2 GB free)

---

### 2. configure-users.sh

**Purpose:** Configure root and agents user accounts with proper permissions

**What it configures:**
- root account with password "root"
- agents account with password "agents"
- agents user with NOPASSWD sudo access
- SSH directories and authorized_keys files
- Proper file permissions and ownership

**Usage:**
```bash
# Inside Hurd guest as root
./configure-users.sh
```

**Security notes:**
- Default passwords are for development only
- Change passwords for production: `passwd root && passwd agents`
- Add SSH keys for key-based authentication
- Review `/etc/sudoers.d/agents` for sudo configuration

**Post-setup verification:**
```bash
# Test account switching
su - agents

# Test sudo access
sudo whoami  # Should output: root

# Test SSH (from host)
ssh agents@localhost -p 2222
```

---

### 3. configure-shell.sh

**Purpose:** Configure bash environment with Mach-specific paths and development aliases

**What it configures:**
- Environment variables (MACH_ROOT, PATH, MANPATH)
- Colorized prompt with Git branch support
- Development aliases (ll, gs, ga, gc, etc.)
- Mach-specific aliases (mig-version, mach-info)
- Helper functions (mach-rebuild, mach-sysinfo, mach-doc)
- Build system shortcuts (cmake-debug, configure-release)

**Usage:**
```bash
# Run as the user you want to configure (root or agents)
./configure-shell.sh

# Or configure for another user
sudo -u agents ./configure-shell.sh

# Reload configuration
source ~/.bashrc
```

**Features added:**

**Environment variables:**
```bash
MACH_ROOT=/usr/src/gnumach
PATH=$PATH:/usr/lib/mig/bin
MANPATH=$MANPATH:/usr/share/man/mach
```

**Colorized prompt:**
```
[agents@hurd:/usr/src (main)] $
# Format: [user@host:dir (git-branch)] $
```

**Useful aliases:**
- `ll` - Detailed file listing with colors
- `mig-version` - Show MIG version
- `mach-info` - System CPU and memory information
- `gs`, `ga`, `gc` - Git status, add, commit shortcuts
- `cmake-debug`, `cmake-release` - CMake with build type

**Helper functions:**
- `mach-rebuild` - Clean, build, and test in one command
- `mach-sysinfo` - Comprehensive system information report
- `mach-doc <term>` - Search Mach/Hurd documentation

---

## Setup Workflow

### Standard Setup (Manual Configuration)

```bash
# 1. Boot into Hurd and login as root
ssh root@localhost -p 2222
# Password: (default from Debian image)

# 2. Copy scripts to Hurd (if not already present)
# From host:
scp -P 2222 scripts/*.sh root@localhost:/root/

# Inside Hurd:
cd /root

# 3. Install development tools
./setup-hurd-dev.sh
# Answer 'y' to continue
# Wait 20-30 minutes for installation

# 4. Configure users
./configure-users.sh
# Sets root:root and agents:agents passwords

# 5. Configure shell (as root)
./configure-shell.sh

# 6. Switch to agents user and configure shell
su - agents
cd /root  # or wherever scripts are located
./configure-shell.sh

# 7. Test configuration
source ~/.bashrc
mach-sysinfo
mig-version
```

### Automated Setup (Rebuild QCOW2 Image)

For a fully pre-configured image, see: `docs/HURD-IMAGE-BUILDING.md`

Process:
1. Boot vanilla Debian Hurd QCOW2
2. Run all three scripts
3. Shutdown cleanly
4. Commit QCOW2 snapshot
5. Use new QCOW2 as base image

---

## Other Scripts

### download-image.sh

Downloads and converts official Debian GNU/Hurd images from Debian mirrors.

**Usage:**
```bash
./scripts/download-image.sh
```

**Features:**
- Downloads latest Debian Hurd release
- Converts raw image to QCOW2 format
- Verifies checksums (if available)
- Reports compression ratio

---

### validate-config.sh

Validates Docker and QEMU configuration files for correctness.

**Usage:**
```bash
./scripts/validate-config.sh
```

**Validates:**
- Dockerfile syntax
- docker-compose.yml YAML syntax
- entrypoint.sh shell syntax (via shellcheck)
- QCOW2 image presence and format
- Port availability

---

### test-docker.sh

Automated test suite for Docker build and deployment.

**Usage:**
```bash
./scripts/test-docker.sh
```

**Tests:**
- Docker image build
- Container startup
- QEMU boot (basic)
- Network connectivity
- Port forwarding

---

## Troubleshooting

### Issue: Scripts fail with "Permission denied"

**Cause:** Scripts not executable
**Fix:**
```bash
chmod +x scripts/*.sh
```

### Issue: setup-hurd-dev.sh fails with "Unable to locate package"

**Cause:** No network connectivity or outdated package lists
**Fix:**
```bash
# Test network
ping -c 3 8.8.8.8

# Update package lists
apt-get update

# Retry installation
./setup-hurd-dev.sh
```

### Issue: configure-users.sh fails: "sudo: command not found"

**Cause:** sudo not installed (script auto-installs on error)
**Fix:**
```bash
# Manual installation if auto-install fails
apt-get update
apt-get install sudo
./configure-users.sh
```

### Issue: Shell configuration not loading

**Cause:** .bashrc not sourced on login
**Fix:**
```bash
# Manually source
source ~/.bashrc

# Or add to .bash_profile (for login shells)
echo 'source ~/.bashrc' >> ~/.bash_profile
```

---

## Best Practices

1. **Backup before running:** Create snapshot before configuration
   ```bash
   # On host
   cp debian-hurd.qcow2 debian-hurd.qcow2.backup
   ```

2. **Run scripts in order:** setup-hurd-dev → configure-users → configure-shell

3. **Test after each script:** Verify functionality before proceeding

4. **Review generated config:** Check ~/.bashrc, /etc/sudoers.d/agents

5. **Change default passwords:** For production use, change from default

6. **Document customizations:** Note any manual changes for reproducibility

---

## Contributing

When modifying scripts:

1. Follow existing style and structure
2. Add comprehensive comments
3. Validate with shellcheck: `shellcheck -S error script.sh`
4. Test on clean Debian Hurd installation
5. Update this README with changes

---

## References

- GNU Mach: https://www.gnu.org/software/hurd/microkernel/mach/gnumach.html
- Debian GNU/Hurd: https://www.debian.org/ports/hurd/
- MIG Manual: https://www.gnu.org/software/hurd/microkernel/mach/mig.html
- Hurd FAQ: https://www.gnu.org/software/hurd/faq.html

---

**Status:** All scripts tested and production-ready
**Version:** 1.0
**Last Updated:** 2025-11-05
