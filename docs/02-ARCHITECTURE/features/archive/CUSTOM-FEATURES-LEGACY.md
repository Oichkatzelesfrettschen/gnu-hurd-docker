# Custom GNU/Hurd Features & Configurations
**Repository:** gnu-hurd-docker
**Image:** debian-hurd-i386-80gb.qcow2
**Date:** 2025-11-06

---

## Overview

This document details all **custom configurations, scripts, and features** beyond the base Debian GNU/Hurd installation.

---

## 🎨 Custom QEMU Configuration

### Optimized i386 Settings
```yaml
CPU: Pentium 3 (pure i386 compatibility)
Cores: 1 (SMP disabled - experimental in Hurd)
RAM: 4096 MB
KVM: Enabled (Linux hosts)
Storage: IDE controller (Hurd-native)
Network: e1000 NIC (Hurd-native)
Display: VNC (port 5901) or nographic
```

### Enhanced Entrypoint Features
- **CPU Override:** `QEMU_CPU` environment variable
- **Auto KVM Detection:** Falls back to TCG if unavailable
- **Multiple Display Modes:** nographic, VNC, SDL-GL, GTK-GL
- **9p Filesystem Sharing:** Host→Guest file sharing
- **Control Channels:** Serial console, QEMU Monitor, QMP automation

---

## 📦 Custom Package Installation

### Provisioning Scripts

#### `install-hurd-packages.sh`
Comprehensive package installer with three tiers:

**Core Development (Always)**
- build-essential, gcc, g++, make, cmake
- autoconf, automake, libtool, pkg-config
- git, gdb, manpages-dev, dpkg-dev

**Programming Languages**
- Python 3 (with pip and dev headers)
- Perl (with libperl-dev)
- Optional: Ruby, Go, Java (if available)

**System Utilities**
- curl, wget
- htop (process monitor)
- screen, tmux (terminal multiplexers)
- rsync, zip, unzip, tree
- net-tools, dnsutils
- ca-certificates
- vim, less

**Hurd-Specific Development**
- `hurd-dev` - Hurd development headers
- `gnumach-dev` - GNU Mach kernel headers
- `mig` - Mach Interface Generator

**GUI Packages (Optional)**
- X11: xorg, x11-xserver-utils, xterm, **xinit**
- Desktop: xfce4, xfce4-goodies, xfce4-terminal
- File Manager: thunar
- Editor: mousepad
- IDEs: emacs, geany
- Web Browser: firefox-esr
- Graphics: gimp

---

## 🖥️ GUI Quick-Start

### XFCE Desktop Launch

**Method 1: Simple Start**
```bash
startxfce4
```

**Method 2: Using xinit**
```bash
xinit /usr/bin/startxfce4 -- :0
```

**Method 3: Create ~/.xinitrc**
```bash
cat > ~/.xinitrc << 'EOF'
#!/bin/bash
exec startxfce4
EOF
chmod +x ~/.xinitrc
startx
```

### VNC Access
```bash
# From host machine:
vncviewer localhost:5901

# Or use TigerVNC:
tigervnc localhost:5901
```

---

## 🔧 Shell Environment Customizations

### Custom .bashrc Additions

**From `configure-shell.sh`:**

#### Environment Variables
```bash
# Mach development paths
export MACH_ROOT=/usr/src/gnumach
export PATH=$PATH:/usr/lib/mig/bin
export MANPATH=$MANPATH:/usr/share/man/mach
export PKG_CONFIG_PATH=$PKG_CONFIG_PATH:/usr/lib/i386-gnu/pkgconfig

# Build configuration
export CC=gcc
export CXX=g++
export MAKE=make

# ccache support (if installed)
export CC="ccache gcc"
export CXX="ccache g++"
```

#### Colorized Prompt
```bash
# Format: [user@host:dir (git-branch)] $
# Green user@host, blue directory, yellow git branch
PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[01;33m\]$(parse_git_branch)\[\033[00m\]\$ '
```

#### Development Aliases
```bash
# File listing
alias ll='ls -lahF --color=auto'
alias la='ls -AF --color=auto'

# Colored grep
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Mach-specific
alias mig-version='mig --version 2>&1 | head -1'
alias mach-info='uname -a && cat /proc/cpuinfo...'
alias mach-memory='free -h && cat /proc/meminfo...'

# Build shortcuts
alias cmake-debug='cmake -DCMAKE_BUILD_TYPE=Debug'
alias cmake-release='cmake -DCMAKE_BUILD_TYPE=Release'
alias configure-debug='./configure CFLAGS="-g -O0"...'
alias configure-release='./configure CFLAGS="-O2 -DNDEBUG"...'

# Git shortcuts
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'
alias gd='git diff'

# Safety (interactive prompts)
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# System monitoring
alias ports='netstat -tulanp'
alias meminfo='free -h && cat /proc/meminfo | head -10'
alias cpuinfo='cat /proc/cpuinfo'
alias diskinfo='df -h'
```

#### Custom Functions
```bash
# Quick rebuild and test
mach-rebuild() {
    # Auto-detects: Makefile, meson.build, or CMakeLists.txt
    # Runs: clean → compile → test
}

# System information summary
mach-sysinfo() {
    # Shows: kernel, CPU, memory, disks, Hurd packages
}

# Search Mach documentation
mach-doc() {
    # Searches man pages and /usr/share/doc/gnumach*
}
```

---

## 📁 Custom Directory Structure

### Development Directories
```
/home/*/workspace/     # User workspace (auto-created)
/home/*/projects/      # User projects (auto-created)
/usr/local/src/        # System-wide source code
/mnt/host/             # 9p mount point for host files
```

### 9p Filesystem Sharing

**Auto-configured in /etc/fstab:**
```
scripts /mnt/host 9p trans=virtio,version=9p2000.L,nofail 0 0
```

**Mount command:**
```bash
mount /mnt/host
```

**From Docker host, share files:**
```bash
# Files in ./share/ directory appear in /mnt/host inside VM
cp myfile.txt share/
# Access inside VM: cat /mnt/host/myfile.txt
```

---

## ⚙️ System Optimizations

### Resource Limits
```bash
# /etc/security/limits.conf
* soft nofile 4096
* hard nofile 8192
```

Allows more open file descriptors for development workloads.

---

## 🚫 What's NOT Included

### Node.js / NVM
**Status:** ❌ **Not installed by default**

**Reason:** Node.js availability on GNU/Hurd i386 is limited. The upstream Debian hurd-i386 port may not have current Node.js packages.

**How to Add:**
```bash
# Check availability first:
apt-cache search nodejs

# If available:
apt-get install nodejs npm

# Alternative: Build from source (advanced)
# Download: https://nodejs.org/dist/
# Requires: Python 3, GCC, make
# May need patches for Hurd compatibility
```

**NVM Alternative:**
```bash
# NVM may not work on Hurd due to bash compatibility
# Recommended: Use distro packages or manual installation
```

---

## 📝 Helper Scripts

### Available in `scripts/` Directory

1. **bringup-and-provision.sh**
   - Full automated setup
   - Boots VM, provisions users, installs packages

2. **configure-shell.sh**
   - Sets up custom .bashrc
   - Adds aliases, functions, colorized prompt

3. **configure-users.sh**
   - Creates development users
   - Sets passwords, sudo access

4. **connect-console.sh**
   - Interactive serial console connection
   - Auto-finds PTY device

5. **create-provisioned-image-comprehensive.sh**
   - Creates pre-provisioned images
   - Three levels: minimal, dev, gui

6. **fix-sources-hurd.sh**
   - Configures Debian-Ports APT sources
   - Fixes hurd-i386 repository access

7. **full-automated-setup.sh**
   - Complete automation script
   - Boot → configure → ready

8. **install-hurd-packages.sh**
   - Main package installer
   - GUI optional, comprehensive dev tools

9. **install-ssh-hurd.sh**
   - Installs and configures SSH server
   - Sets up openssh-server, random-egd

10. **manage-snapshots.sh**
    - QEMU snapshot management
    - Create, restore, list snapshots

11. **monitor-qemu.sh**
    - Real-time QEMU monitoring
    - CPU, memory, disk I/O stats

12. **setup-hurd-dev.sh**
    - Hurd-specific development setup
    - gnumach, mig, hurd-dev packages

13. **test-hurd-system.sh**
    - Comprehensive system tests
    - Verifies Hurd functionality

14. **validate-config.sh**
    - Pre-flight checks
    - Validates QEMU configuration

---

## 🔍 Verification Commands

### Check Installed Features

```bash
# Hurd-specific packages
dpkg -l | grep -E "hurd-dev|gnumach|mig"

# GUI packages
dpkg -l | grep -E "xfce|xorg|x11"

# Development tools
which gcc g++ make cmake git gdb python3

# Custom aliases (after sourcing .bashrc)
alias | grep -E "mach-|cmake-|configure-"

# Custom functions
type mach-rebuild mach-sysinfo mach-doc
```

### Test GUI Availability
```bash
# Check X11 installed
which startx xinit startxfce4

# Check X server
which X Xorg

# Check display variable
echo $DISPLAY
```

---

## 🎯 Recommended Workflow

### First Boot Checklist
1. ✅ **Login:** root / root
2. ✅ **Source bashrc:** `source ~/.bashrc`
3. ✅ **Update packages:** `apt-get update`
4. ⬜ **Mount 9p share:** `mount /mnt/host`
5. ⬜ **Start GUI (optional):** `startxfce4` or `startx`
6. ⬜ **Test development:** `mach-sysinfo`, `gcc --version`

### Development Session
1. **SSH Access (if configured):**
   ```bash
   ssh -p 2222 root@localhost
   ```

2. **VNC Access (for GUI):**
   ```bash
   vncviewer localhost:5901
   # Then inside VM: startxfce4
   ```

3. **File Sharing:**
   ```bash
   # Host: cp code.c share/
   # VM: mount /mnt/host && cp /mnt/host/code.c ~/
   ```

4. **Build Project:**
   ```bash
   cd ~/workspace/myproject
   mach-rebuild  # Auto-detects build system
   ```

---

## 📚 Additional Resources

### QEMU Configuration Reference
- `docker-compose.yml` - Service definitions
- `docker-compose.override.yml` - Custom overrides
- `entrypoint.sh` - QEMU launcher with feature detection

### Provisioning Reference
- `COMPREHENSIVE-IMAGE-GUIDE.md` - Image variants guide
- `HURD-SYSTEM-AUDIT.md` - System audit report
- `scripts/README.md` - Script documentation (if exists)

---

## 🆘 Troubleshooting

### GUI Not Starting
```bash
# Check X11 installed
dpkg -l | grep xorg

# Check xinit available
which xinit startx

# Try starting X manually
startx -- :0
```

### 9p Mount Fails
```bash
# Check fstab entry
cat /etc/fstab | grep 9p

# Manual mount
mount -t 9p -o trans=virtio scripts /mnt/host

# Check QEMU sharing enabled (from host)
docker-compose logs | grep virtfs
```

### Aliases Not Working
```bash
# Reload bashrc
source ~/.bashrc

# Check if configured
grep "Mach development" ~/.bashrc
```

---

## 🎓 Learning Path

### For Hurd Development
1. **Read documentation:** `mach-doc` function
2. **Explore examples:** `/usr/share/doc/gnumach*/examples/`
3. **Check headers:** `/usr/include/mach/`
4. **Test builds:** `mach-rebuild` in sample projects

### For GUI Development
1. **Start XFCE:** `startxfce4`
2. **Open terminal:** `xfce4-terminal`
3. **Use editors:** `mousepad` (GUI) or `vim` (CLI)
4. **Test graphics:** `gimp`, `firefox-esr`

---

## 📊 Summary

**Custom Features:**
- ✅ Optimized QEMU i386 config (Pentium 3, 1 core, 4GB RAM)
- ✅ Comprehensive development packages (gcc, git, gdb, Hurd tools)
- ✅ Optional GUI (XFCE with xinit support)
- ✅ Custom shell environment (aliases, functions, colorized prompt)
- ✅ 9p filesystem sharing (host↔guest)
- ✅ Automated provisioning scripts
- ✅ Mach-specific development helpers
- ❌ Node.js/NVM (not available on Hurd i386 by default)

**Next Steps:**
1. Review `HURD-SYSTEM-AUDIT.md` for system status
2. Run `mach-sysinfo` to verify configuration
3. Start GUI with `startxfce4` (if XFCE installed)
4. Mount shared files with `mount /mnt/host`
5. Begin development in `~/workspace/`

---

**Generated:** 2025-11-06 by Claude Code
**Repository:** gnu-hurd-docker
**Maintainer:** Oaich
