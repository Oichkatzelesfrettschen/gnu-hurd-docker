# GNU/Hurd Docker - Custom Features and Configurations

**Last Updated**: 2025-11-07
**Consolidated From**:
- CUSTOM-HURD-FEATURES.md (2025-11-06)

**Purpose**: Complete reference for custom configurations, packages, and features beyond base Debian GNU/Hurd

**Scope**: Debian GNU/Hurd x86_64 only (i386 deprecated 2025-11-07)

---

## Overview

This document details all **custom configurations, provisioning scripts, and features** beyond the base Debian GNU/Hurd x86_64 installation.

**Customizations Include**:
- Optimized QEMU x86_64 configuration
- Comprehensive development package sets
- Optional GUI (XFCE desktop environment)
- Custom shell environment (aliases, functions, prompt)
- 9p filesystem sharing for host↔guest file exchange
- Automated provisioning scripts

---

## QEMU Configuration

### Optimized x86_64 Settings

**Current Configuration** (from entrypoint.sh and docker-compose.yml):

```yaml
CPU: host (KVM) or max (TCG)
Cores: 2 (SMP stable in Hurd 2025)
RAM: 4096 MB (4 GB)
KVM: Auto-detected (falls back to TCG if unavailable)
Storage: IDE controller (Hurd-compatible)
Network: e1000 NIC (Intel Gigabit Ethernet)
Display: nographic (default) or VNC/SDL/GTK
Machine: pc (i440fx chipset, Hurd-compatible)
```

**CPU Model Selection**:
```bash
# With KVM (hardware acceleration)
-cpu host
# Provides: Full CPU passthrough, native performance

# With TCG (software emulation)
-cpu max
# Provides: All emulated features enabled
```

**Comparison**:
| Feature | host (KVM) | max (TCG) |
|---------|------------|-----------|
| Performance | ~80-90% native | ~10-20% native |
| Requirements | /dev/kvm access | None |
| Compatibility | Host CPU features | All x86_64 features |
| Boot Time | 2-5 minutes | 5-10 minutes |

### Enhanced Entrypoint Features

**Environment Variable Overrides**:

```bash
# Override CPU model
export QEMU_CPU="Skylake-Client"  # Specific CPU model

# Override RAM
export QEMU_RAM=8192  # 8 GB

# Override SMP cores
export QEMU_SMP=4  # 4 cores

# Override display mode
export DISPLAY_MODE="vnc"  # or "sdl", "gtk", "nographic"

# Restart container to apply
docker-compose up -d --force-recreate
```

**Supported Display Modes**:

1. **nographic** (default):
   - No graphical output
   - Serial console only
   - Best for headless servers

2. **vnc**:
   - VNC server on port 5900
   - Connect: `vncviewer localhost:5900`
   - Best for remote graphical access

3. **sdl**:
   - SDL window on host
   - Requires X11/Wayland on host
   - Best for local development with GUI

4. **gtk**:
   - GTK window on host
   - Better scaling and integration than SDL
   - Best for desktop environments

### Control Channels

**Five independent control channels**:

1. **SSH (port 2222)**: Secure shell access
2. **Serial Console (telnet :5555)**: Direct TTY access
3. **QMP Socket (/qmp/qmp.sock)**: JSON automation
4. **HMP Monitor (telnet :9999)**: Human-readable commands
5. **9p Filesystem (virtio)**: Host↔guest file sharing

See `docs/02-ARCHITECTURE/CONTROL-PLANE.md` for complete details.

---

## Package Installation

### Provisioning Scripts

**Available in `./share/` directory** (accessible from guest via 9p mount):

#### install-essentials-hurd.sh

**Purpose**: Core utilities and development tools

**Packages Installed**:

**Core Development**:
- build-essential (gcc, g++, make)
- cmake, autoconf, automake, libtool
- pkg-config, flex, bison, texinfo
- git, gdb, valgrind
- manpages-dev, dpkg-dev

**Programming Languages**:
- python3, python3-pip, python3-dev
- perl, libperl-dev
- Optional: ruby, go, java (if available in hurd-amd64)

**System Utilities**:
- curl, wget
- htop, sysstat (system monitoring)
- screen, tmux (terminal multiplexers)
- rsync, zip, unzip, tree
- net-tools, dnsutils, netcat-openbsd
- ca-certificates, openssl
- vim, emacs-nox, nano, less

**Hurd-Specific Development**:
- **hurd-dev**: Hurd development headers
- **gnumach-dev**: GNU Mach kernel headers
- **mig**: Mach Interface Generator (IPC compiler)

**Usage**:
```bash
# Inside guest (after mounting /mnt/host)
mount -t 9p -o trans=virtio scripts /mnt/host
bash /mnt/host/install-essentials-hurd.sh
```

#### install-nodejs-hurd.sh

**Purpose**: Node.js runtime and npm package manager

**Status**: ⚠️ **Optional** - Node.js availability on hurd-amd64 limited

**Check Availability**:
```bash
# Inside guest
apt-cache search nodejs
apt-cache policy nodejs

# If available, install:
apt-get install nodejs npm
```

**Alternative** (build from source):
```bash
# Download Node.js source
wget https://nodejs.org/dist/v18.17.0/node-v18.17.0.tar.gz
tar xzf node-v18.17.0.tar.gz
cd node-v18.17.0

# Build (requires Python 3, GCC)
./configure --prefix=/usr/local
make -j$(nproc)
make install

# Verify
node --version
npm --version
```

**Note**: Building Node.js on Hurd may require patches. Check Debian Hurd mailing list for status.

#### install-claude-code-hurd.sh

**Purpose**: Install Claude Code development tools and dependencies

**Packages**:
- Development headers for Hurd/Mach
- Editor support (vim, emacs with LSP)
- Build tools (cmake, ninja)

**Usage**:
```bash
bash /mnt/host/install-claude-code-hurd.sh
```

#### run-all-installations.sh

**Purpose**: Run all installation scripts in sequence

**Usage**:
```bash
# Mount shared directory
mount -t 9p -o trans=virtio scripts /mnt/host

# Run all scripts
bash /mnt/host/run-all-installations.sh

# Includes:
# 1. install-essentials-hurd.sh
# 2. install-nodejs-hurd.sh (if available)
# 3. install-claude-code-hurd.sh
```

**Duration**: 10-30 minutes depending on network and system speed

---

## GUI Desktop Environment

### XFCE Installation (Optional)

**Packages**:
- **xorg**: X11 display server
- **x11-xserver-utils**: X11 utilities
- **xterm**: Basic terminal
- **xinit**: X11 initialization
- **xfce4**: XFCE desktop environment
- **xfce4-goodies**: XFCE extras (panel plugins, utilities)
- **xfce4-terminal**: XFCE terminal emulator
- **thunar**: File manager
- **mousepad**: Text editor
- **firefox-esr**: Web browser (if available)
- **gimp**: Image editor (if available)

**Install GUI**:
```bash
# Inside guest
apt-get update
apt-get install -y \
    xorg x11-xserver-utils xterm xinit \
    xfce4 xfce4-goodies xfce4-terminal \
    thunar mousepad
```

### Launch XFCE Desktop

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

### VNC Access to GUI

**Enable VNC in docker-compose.yml**:
```yaml
environment:
  ENABLE_VNC: 1
```

**Connect from Host**:
```bash
vncviewer localhost:5900
```

**Inside VNC Session**:
```bash
# Start XFCE
startxfce4

# Or start individual apps
xfce4-terminal
thunar
mousepad
```

**Display Resolution**:
- Default: 1024x768
- Change via XFCE Settings → Display

---

## Shell Environment Customizations

### Custom .bashrc Additions

**From configure-shell.sh script**:

#### Environment Variables

```bash
# Mach development paths
export MACH_ROOT=/usr/src/gnumach
export PATH=$PATH:/usr/lib/mig/bin
export MANPATH=$MANPATH:/usr/share/man/mach
export PKG_CONFIG_PATH=$PKG_CONFIG_PATH:/usr/lib/x86_64-gnu/pkgconfig

# Build configuration
export CC=gcc
export CXX=g++
export MAKE=make

# ccache support (if installed)
if command -v ccache >/dev/null; then
    export CC="ccache gcc"
    export CXX="ccache g++"
fi
```

#### Colorized Prompt

```bash
# Git branch parser function
parse_git_branch() {
    git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}

# Colorized prompt
# Format: [user@host:dir (git-branch)] $
# Green user@host, blue directory, yellow git branch
PS1='\[\033[01;32m\]\u@hurd-x86_64\[\033[00m\]:\[\033[01;34m\]\w\[\033[01;33m\]$(parse_git_branch)\[\033[00m\]\$ '
```

#### Development Aliases

```bash
# File listing
alias ll='ls -lahF --color=auto'
alias la='ls -AF --color=auto'
alias l='ls -CF --color=auto'

# Colored output
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias diff='diff --color=auto'

# Mach-specific
alias mig-version='mig --version 2>&1 | head -1'
alias mach-info='uname -a && cat /proc/cpuinfo | head -20'
alias mach-memory='free -h && cat /proc/meminfo | head -10'

# Build shortcuts
alias cmake-debug='cmake -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON'
alias cmake-release='cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_EXPORT_COMPILE_COMMANDS=ON'
alias configure-debug='./configure CFLAGS="-g -O0 -Wall" CXXFLAGS="-g -O0 -Wall"'
alias configure-release='./configure CFLAGS="-O2 -DNDEBUG" CXXFLAGS="-O2 -DNDEBUG"'

# Git shortcuts
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate --all'
alias gd='git diff'
alias gdc='git diff --cached'

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
    local dir="${1:-.}"
    cd "$dir" || return 1

    echo "Detecting build system..."

    if [ -f "Makefile" ]; then
        echo "Found Makefile, running make clean && make"
        make clean && make
    elif [ -f "meson.build" ]; then
        echo "Found meson.build, running meson compile -C build"
        meson compile -C build
    elif [ -f "CMakeLists.txt" ]; then
        echo "Found CMakeLists.txt, running cmake --build build"
        cmake --build build
    else
        echo "No recognized build system found"
        return 1
    fi

    # Run tests if available
    if [ -f "Makefile" ] && grep -q "^test:" Makefile; then
        echo "Running tests..."
        make test
    fi
}

# System information summary
mach-sysinfo() {
    echo "=== GNU/Hurd x86_64 System Information ==="
    echo ""
    echo "Kernel:"
    uname -a
    echo ""
    echo "CPU:"
    cat /proc/cpuinfo | grep "model name" | head -1
    echo "CPU cores:" $(nproc)
    echo ""
    echo "Memory:"
    free -h
    echo ""
    echo "Disk:"
    df -h /
    echo ""
    echo "Hurd packages:"
    dpkg -l | grep -E "hurd-dev|gnumach|mig" | awk '{print $2, $3}'
}

# Search Mach documentation
mach-doc() {
    local query="$1"
    if [ -z "$query" ]; then
        echo "Usage: mach-doc <search_term>"
        return 1
    fi

    echo "Searching Mach documentation for: $query"
    echo ""

    # Search man pages
    man -k "$query" | grep -i mach

    # Search /usr/share/doc
    if [ -d /usr/share/doc/gnumach-dev ]; then
        find /usr/share/doc/gnumach-dev -type f -exec grep -l -i "$query" {} \;
    fi
}
```

---

## Directory Structure

### Development Directories

**Auto-created on First Login** (via configure-shell.sh):

```
/home/*/workspace/     # User workspace (projects, builds)
/home/*/projects/      # User projects (git repos)
/home/*/Downloads/     # Downloads
/home/*/Documents/     # Documentation
```

**System Directories**:
```
/usr/local/src/        # System-wide source code
/mnt/host/             # 9p mount point for host files
/opt/                  # Optional software installations
```

### 9p Filesystem Sharing

**Purpose**: Fast bidirectional file exchange between host and guest

**Configuration** (auto-configured in entrypoint.sh):
```bash
# QEMU args
-virtfs local,path=/share,mount_tag=scripts,security_model=none,id=fsdev0
```

**Docker Volume**:
```yaml
# docker-compose.yml
volumes:
  - ./share:/share:rw
```

**Mount in Guest**:
```bash
# Create mount point
mkdir -p /mnt/host

# Mount filesystem
mount -t 9p -o trans=virtio scripts /mnt/host

# Verify
ls -la /mnt/host
```

**Persistent Mount** (add to /etc/fstab):
```bash
echo "scripts /mnt/host 9p trans=virtio,version=9p2000.L,nofail 0 0" >> /etc/fstab

# Test
mount -a
```

**Automatic Mount** (systemd unit):
```bash
# Create mount unit
cat > /etc/systemd/system/mnt-host.mount << 'EOF'
[Unit]
Description=9p Host File Sharing
After=network.target

[Mount]
What=scripts
Where=/mnt/host
Type=9p
Options=trans=virtio,version=9p2000.L,nofail

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
systemctl daemon-reload
systemctl enable --now mnt-host.mount
```

**Usage Examples**:

```bash
# Host: Share files
cp myproject.tar.gz ./share/

# Guest: Access files
ls /mnt/host/myproject.tar.gz
tar xzf /mnt/host/myproject.tar.gz

# Guest: Export build artifacts
cp build/myapp /mnt/host/

# Host: Retrieve artifacts
ls -lh ./share/myapp
```

---

## System Optimizations

### Resource Limits

**File Descriptor Limits** (/etc/security/limits.conf):

```bash
# Increase open file limits for development workloads
* soft nofile 4096
* hard nofile 8192
* soft nproc 2048
* hard nproc 4096
```

**Apply Limits**:
```bash
# Add to /etc/security/limits.conf
cat >> /etc/security/limits.conf <<'EOF'
* soft nofile 4096
* hard nofile 8192
* soft nproc 2048
* hard nproc 4096
EOF

# Verify (logout/login required)
ulimit -n
# Expected: 4096
```

### Kernel Parameters

**Not directly configurable** (Hurd uses different kernel parameter mechanism than Linux)

**Hurd-Specific Tuning**:
- GNU Mach kernel options set at boot via GRUB
- See `/boot/grub/grub.cfg` for kernel boot parameters

---

## Helper Scripts Reference

### Available Scripts (in `./scripts/` directory)

1. **bringup-and-provision.sh**
   - Full automated VM setup
   - Boots VM, provisions users, installs packages
   - Use for: Fresh installations

2. **configure-shell.sh**
   - Sets up custom .bashrc with aliases and functions
   - Use for: Shell environment customization

3. **configure-users.sh**
   - Creates development users with SSH keys
   - Use for: Multi-user setups

4. **connect-console.sh**
   - Interactive serial console connection
   - Use for: Emergency access, boot debugging

5. **download-image.sh**
   - Downloads official Debian GNU/Hurd x86_64 image
   - Use for: Initial setup

6. **fix-sources-hurd.sh**
   - Configures Debian-Ports APT sources
   - Use for: Package repository issues

7. **full-automated-setup.sh**
   - Complete automation: boot → configure → ready
   - Use for: CI/CD pipelines

8. **install-hurd-packages.sh**
   - Main package installer (dev tools, optional GUI)
   - Use for: Package provisioning

9. **install-ssh-hurd.sh**
   - Installs and configures SSH server
   - Sets up openssh-server with key-based auth
   - Use for: SSH access setup

10. **manage-snapshots.sh**
    - QEMU snapshot management (create, restore, list)
    - Use for: Save/restore VM state

11. **monitor-qemu.sh**
    - Real-time QEMU performance monitoring
    - Displays CPU, memory, disk I/O stats
    - Use for: Performance analysis

12. **setup-hurd-dev.sh**
    - Hurd-specific development environment setup
    - Installs gnumach-dev, hurd-dev, mig
    - Use for: Hurd kernel development

13. **test-hurd-system.sh**
    - Comprehensive system verification
    - Tests Hurd functionality, translators, services
    - Use for: Post-installation validation

14. **validate-config.sh**
    - Pre-flight configuration checks
    - Validates QEMU settings before launch
    - Use for: Debugging startup issues

---

## Verification Commands

### Check Installed Features

```bash
# Hurd-specific packages
dpkg -l | grep -E "hurd-dev|gnumach|mig"

# Expected output:
# ii  gnumach-dev    1.8+...    Mach kernel headers
# ii  hurd-dev       0.9...     Hurd development files
# ii  mig            ...        Mach Interface Generator

# GUI packages (if installed)
dpkg -l | grep -E "xfce|xorg|x11"

# Development tools
which gcc g++ make cmake git gdb python3
# All should return: /usr/bin/<tool>

# Custom aliases (after sourcing .bashrc)
alias | grep -E "mach-|cmake-|configure-"

# Custom functions
type mach-rebuild mach-sysinfo mach-doc
# Should show: mach-rebuild is a function
```

### Test GUI Availability

```bash
# Check X11 components installed
which startx xinit startxfce4 X Xorg

# Check display variable
echo $DISPLAY
# Expected: :0 (if X11 running)

# List available X servers
ls /usr/bin/X*
```

### Test 9p Mount

```bash
# Mount manually
mount -t 9p -o trans=virtio scripts /mnt/host

# Verify mount
mount | grep 9p
# Expected: scripts on /mnt/host type 9p (...)

# Test write access
echo "test" > /mnt/host/test.txt
cat /mnt/host/test.txt
# Expected: test
```

---

## Recommended Workflow

### First Boot Checklist

1. ✅ **Login**: root / root (or empty password)
2. ✅ **Source bashrc**: `source ~/.bashrc`
3. ✅ **Update packages**: `apt-get update`
4. ✅ **Mount 9p share**: `mount -t 9p -o trans=virtio scripts /mnt/host`
5. ⬜ **Run provisioning**: `bash /mnt/host/run-all-installations.sh`
6. ⬜ **Start GUI (optional)**: `startxfce4` (if XFCE installed)
7. ⬜ **Test development**: `mach-sysinfo`, `gcc --version`

### Development Session

**SSH Access**:
```bash
# From host
ssh -p 2222 root@localhost

# Or with key-based auth
ssh hurd-local
```

**VNC Access** (for GUI):
```bash
# From host
vncviewer localhost:5900

# Inside guest
startxfce4
```

**File Sharing**:
```bash
# Host: Share code
cp project.tar.gz ./share/

# Guest: Extract and build
mount /mnt/host
tar xzf /mnt/host/project.tar.gz -C ~/workspace/
cd ~/workspace/project
mach-rebuild
```

**Build Project**:
```bash
cd ~/workspace/myproject
mach-rebuild  # Auto-detects build system (make/meson/cmake)
```

---

## Troubleshooting

### GUI Not Starting

**Symptom**: `startxfce4` fails or shows errors

**Diagnostics**:
```bash
# Check X11 installed
dpkg -l | grep xorg

# Check xinit available
which xinit startx

# Check X server executable
which X Xorg
```

**Solutions**:

1. **Install X11**:
   ```bash
   apt-get install xorg x11-xserver-utils xinit
   ```

2. **Try starting X manually**:
   ```bash
   startx -- :0
   ```

3. **Check X11 logs**:
   ```bash
   cat ~/.local/share/xorg/Xorg.0.log
   ```

### 9p Mount Fails

**Symptom**: `mount -t 9p` fails with "No such device"

**Diagnostics**:
```bash
# Check kernel module loaded
lsmod | grep 9p

# Check fstab entry (if automatic mount)
cat /etc/fstab | grep 9p

# Check QEMU configuration (from host)
docker logs hurd-x86_64-qemu | grep virtfs
```

**Solutions**:

1. **Load 9p modules**:
   ```bash
   modprobe 9pnet 9pnet_virtio 9p
   ```

2. **Manual mount with version**:
   ```bash
   mount -t 9p -o trans=virtio,version=9p2000.L scripts /mnt/host
   ```

3. **Verify QEMU args** (on host):
   ```bash
   docker exec hurd-x86_64-qemu ps aux | grep virtfs
   # Expected: -virtfs local,path=/share,mount_tag=scripts,...
   ```

### Aliases Not Working

**Symptom**: Custom aliases not available

**Cause**: .bashrc not sourced

**Solutions**:

1. **Reload bashrc**:
   ```bash
   source ~/.bashrc
   ```

2. **Check if aliases defined**:
   ```bash
   grep "Mach development" ~/.bashrc
   ```

3. **Run configure-shell.sh**:
   ```bash
   bash /mnt/host/configure-shell.sh
   source ~/.bashrc
   ```

---

## Learning Path

### For Hurd Development

1. **Read documentation**:
   ```bash
   mach-doc "task"  # Search Mach docs
   man mach        # Mach manual pages
   ```

2. **Explore examples**:
   ```bash
   ls /usr/share/doc/gnumach-dev/examples/
   ```

3. **Check headers**:
   ```bash
   ls /usr/include/mach/
   ls /usr/include/hurd/
   ```

4. **Test builds**:
   ```bash
   cd ~/workspace
   cat > hello-mach.c << 'EOF'
   #include <mach.h>
   #include <stdio.h>

   int main() {
       printf("Hello from Mach on x86_64!\n");
       printf("Task port: %u\n", mach_task_self());
       return 0;
   }
   EOF

   gcc -o hello-mach hello-mach.c
   ./hello-mach
   ```

### For GUI Development

1. **Start XFCE**:
   ```bash
   startxfce4
   ```

2. **Open terminal**:
   ```bash
   xfce4-terminal
   ```

3. **Use editors**:
   - mousepad (GUI text editor)
   - vim (CLI editor)
   - emacs (CLI/GUI editor)

4. **Test graphics**:
   - gimp (image editor)
   - firefox-esr (web browser)

---

## Summary

**Custom Features Enabled**:
- ✅ Optimized QEMU x86_64 config (host/max CPU, 2 cores, 4GB RAM)
- ✅ Comprehensive development packages (gcc, git, gdb, Hurd tools)
- ✅ Optional GUI (XFCE with xinit support)
- ✅ Custom shell environment (aliases, functions, colorized prompt)
- ✅ 9p filesystem sharing (host↔guest bidirectional)
- ✅ Automated provisioning scripts (install-*.sh, run-all-installations.sh)
- ✅ Mach-specific development helpers (mig, gnumach-dev, hurd-dev)
- ⚠️ Node.js/NVM (limited availability on hurd-amd64, build from source if needed)

**Next Steps**:
1. Mount shared directory: `mount -t 9p -o trans=virtio scripts /mnt/host`
2. Run provisioning: `bash /mnt/host/run-all-installations.sh`
3. Verify installation: `mach-sysinfo`
4. Start GUI (optional): `startxfce4`
5. Begin development in `~/workspace/`

**Key Resources**:
- Provisioning scripts: `./share/*.sh`
- Helper scripts: `./scripts/*.sh`
- Architecture docs: `docs/02-ARCHITECTURE/`
- QEMU configuration: `entrypoint.sh`, `docker-compose.yml`

---

**Status**: Production Ready (x86_64-only)
**Last Updated**: 2025-11-07
**Maintainer**: Oichkatzelesfrettschen
**Architecture**: Pure x86_64
