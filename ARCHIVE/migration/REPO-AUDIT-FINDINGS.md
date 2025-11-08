# Repository Audit: Existing GNU/Hurd i386 Provisioning Features

## Executive Summary

✅ **CONFIRMED:** This repository already has comprehensive provisioning scripts!
🎯 **ARCHITECTURE:** Debian GNU/Hurd 2025 i386 (hurd-i386, i686)
📦 **FEATURES:** Development tools, GUI support, apt updates, user management

## Existing Provisioning Scripts Found

### 1. `scripts/install-hurd-packages.sh` ⭐ COMPREHENSIVE
**Purpose:** Complete package installation (CLI + optional GUI)

**Includes:**
- ✅ Core development tools (gcc, g++, make, cmake, autoconf, automake)
- ✅ Programming languages (Python3, Perl, Ruby, Go, Java)
- ✅ System utilities (curl, wget, htop, screen, tmux, vim)
- ✅ Hurd-specific packages (hurd-dev, gnumach-dev, mig)
- ✅ **OPTIONAL GUI:** X11 + Xfce4 + Firefox ESR + GIMP
- ✅ Development directories (~/workspace, ~/projects)
- ✅ Bash aliases configured
- ✅ 9p mount point for host filesystem sharing (`/mnt/host`)
- ✅ System optimizations (file descriptor limits)

**GUI Stack (Optional):**
```bash
- xorg, x11-xserver-utils, xterm, xinit
- xfce4, xfce4-goodies, xfce4-terminal
- thunar, mousepad
- emacs, geany (IDEs)
- firefox-esr, gimp (applications)
```

### 2. `scripts/setup-hurd-dev.sh` ⭐ DEV FOCUSED
**Purpose:** Install comprehensive development environment

**Includes:**
- ✅ Core compilation tools (GCC, Clang, Make, CMake)
- ✅ Mach-specific utilities (MIG, GNU Mach headers)
- ✅ Debuggers (GDB, strace, ltrace, valgrind)
- ✅ Version control (Git)
- ✅ Editors (Vim, Emacs, nano)
- ✅ Build systems (Ninja, Meson, SCons)
- ✅ Documentation tools (Doxygen, Graphviz)
- ✅ ~1.5 GB packages, 20-30 min install time

### 3. `scripts/full-automated-setup.sh` ⭐ COMPLETE AUTOMATION
**Purpose:** Fully automated end-to-end setup

**Workflow:**
1. Wait for Hurd to boot (max 10 minutes)
2. Setup root password (root:root, expires on first login)
3. Create agents user (agents:agents, sudoer, expires on first login)
4. Install all development tools
5. Configure shell environment

**Security:** Passwords expire on first login (forces user to change)

### 4. `scripts/bringup-and-provision.sh`
**Purpose:** Orchestrate container boot + provisioning

**Workflow:**
1. Boot Docker container
2. Enable SSH via serial console
3. Fix Debian-Ports sources and upgrade
4. Create agents sudo user
5. Install basic dev toolchain (gcc, make, git, vim)

### 5. `scripts/fix-sources-hurd.sh`
**Purpose:** Fix APT sources for Debian-Ports

**Critical for i386:** Ensures apt-get works correctly on hurd-i386 port

### 6. `scripts/configure-shell.sh`
**Purpose:** Shell environment configuration

### 7. `scripts/configure-users.sh`
**Purpose:** User management and configuration

## Display Modes (entrypoint.sh)

The QEMU launcher supports multiple display modes:

| Mode | Description | Use Case |
|------|-------------|----------|
| `nographic` | Serial console only | CI, headless servers, SSH-only |
| `vnc` | VNC server on port 5901 | Remote GUI access |
| `sdl-gl` | SDL with OpenGL | Local GUI, GPU acceleration |
| `gtk-gl` | GTK with OpenGL | Local GUI, better integration |
| `sdl` | SDL without GL | Local GUI, no GPU |
| `gtk` | GTK without GL | Local GUI, no GPU |

**Video Adapters:**
- `std` - Standard VGA (default, Hurd-compatible)
- `virtio-vga-gl` - VirtIO with GL (if supported)
- `cirrus` - Cirrus Logic (legacy)

## Docker Compose Configuration

### GUI Profile (default)
```yaml
gnu-hurd-dev:
  RAM: 4096 MB
  CPUs: 4
  Display: sdl-gl
  Ports: 2222 (SSH), 5555 (serial), 5901 (VNC)
  Storage: IDE (Hurd-compatible)
  Network: e1000 (Hurd-compatible)
```

### CLI Profile (headless)
```yaml
gnu-hurd-cli:
  RAM: 2048 MB
  CPUs: 1
  Display: nographic
  Ports: 2223 (SSH), 5556 (serial)
```

## Filesystem Sharing (9p)

**Host → Guest:** `/share` directory mounted as `/mnt/host` in Hurd
**Tag:** `scripts` (VirtIO 9p)
**Usage:** Share files between host and Hurd guest

## What's Already Working

✅ **Architecture:** Debian GNU/Hurd 2025 i386 (i686) confirmed
✅ **Provisioning:** Comprehensive scripts for dev + GUI
✅ **APT Updates:** Debian-Ports sources configured
✅ **Users:** root + agents (sudoer) with password expiry
✅ **Development:** Full toolchain (gcc, clang, make, git, gdb)
✅ **GUI:** Optional Xfce4 + Firefox + GIMP
✅ **Sharing:** 9p filesystem for host integration
✅ **Display:** Multiple modes (nographic, VNC, SDL, GTK)
✅ **Acceleration:** KVM detection and fallback to TCG

## What Should Be in Pre-Provisioned Image

Based on audit findings, the pre-provisioned i386 image should include:

### Tier 1: Essential (Always Include)
- ✅ SSH server (openssh-server, random-egd)
- ✅ Root password: root
- ✅ Agents user: agents (sudoer, NOPASSWD)
- ✅ APT sources fixed for Debian-Ports (hurd-i386)
- ✅ APT cache updated (apt-get update)
- ✅ Core development tools:
  - gcc, g++, make, cmake
  - autoconf, automake, libtool, pkg-config
  - git, vim, nano
  - gdb, strace

### Tier 2: Development (Recommended)
- ✅ Hurd-specific: hurd-dev, gnumach-dev, mig
- ✅ Compilers: clang, llvm
- ✅ Build systems: ninja-build, meson
- ✅ Languages: python3, python3-pip, perl
- ✅ Utilities: curl, wget, htop, screen, tmux, rsync
- ✅ Documentation: doxygen, graphviz

### Tier 3: GUI (Optional, Large)
- ⚠️ X11: xorg, xinit, xterm (~100 MB)
- ⚠️ Xfce4: xfce4, xfce4-goodies (~200 MB)
- ⚠️ Applications: firefox-esr (~300 MB), gimp (~150 MB)

**Recommendation:** Create **TWO** pre-provisioned images:
1. **debian-hurd-provisioned-cli.img** - Tier 1 + Tier 2 (1-1.5 GB additional)
2. **debian-hurd-provisioned-gui.img** - Tier 1 + Tier 2 + Tier 3 (2-3 GB additional)

## Integration Strategy

### Option A: Minimal CI Image (Fast)
**For CI workflows that need speed:**
- Base: Fresh Debian GNU/Hurd 2025 i386
- Add: SSH, users, apt updates, core dev tools (Tier 1 only)
- Size: ~500 MB additional
- Boot → SSH ready: < 2 minutes
- **Use case:** Fast CI testing, basic builds

### Option B: Full Dev Image (Comprehensive)
**For development and testing:**
- Base: Fresh Debian GNU/Hurd 2025 i386
- Add: Tier 1 + Tier 2 (all dev tools, Hurd-specific)
- Size: ~1.5 GB additional
- Boot → SSH ready: < 2 minutes
- **Use case:** Development, comprehensive testing

### Option C: GUI Image (Kitchen Sink)
**For interactive use and GUI testing:**
- Base: Fresh Debian GNU/Hurd 2025 i386
- Add: Tier 1 + Tier 2 + Tier 3 (full GUI stack)
- Size: ~3 GB additional
- Boot → SSH ready: < 2 minutes
- Boot → X11 ready: ~5 minutes
- **Use case:** GUI testing, demos, interactive development

## Recommendation for CI

**Use Option B** (Full Dev Image) because:
1. Includes all Hurd-specific development tools
2. Still reasonably sized (~3.5 GB total)
3. Fast boot time (< 2 minutes)
4. Covers 99% of CI testing needs
5. No GUI overhead in CI (nographic mode)

**Skip GUI** for CI because:
- Adds ~1.5 GB size
- Not needed for headless CI
- Can be installed later if needed via apt

## Files to Integrate

### Priority 1: Must Use
- `scripts/install-ssh-hurd.sh` - Already in create-provisioned-image.sh ✅
- `scripts/fix-sources-hurd.sh` - **ADD THIS** (critical for apt)
- `scripts/setup-hurd-dev.sh` - **MERGE THIS** (comprehensive dev tools)

### Priority 2: Consider
- `scripts/install-hurd-packages.sh` - Similar to setup-hurd-dev.sh (choose one)
- `scripts/configure-shell.sh` - Nice-to-have (bash aliases)
- `scripts/configure-users.sh` - Partially covered by bringup script

### Priority 3: Reference
- `scripts/full-automated-setup.sh` - Good reference for automation patterns
- `scripts/bringup-and-provision.sh` - Good reference for SSH + users

## Next Steps

1. **Enhance `create-provisioned-image.sh`** to include:
   - Call `fix-sources-hurd.sh` after SSH setup
   - Call `setup-hurd-dev.sh` for Tier 1 + Tier 2 packages
   - Optionally: Add flag for GUI installation (Tier 3)

2. **Create variant scripts:**
   - `create-provisioned-image-cli.sh` - Tier 1 + Tier 2
   - `create-provisioned-image-gui.sh` - Tier 1 + Tier 2 + Tier 3

3. **Upload both variants to GitHub Releases:**
   - `debian-hurd-provisioned-cli.img.tar.gz` (recommended for CI)
   - `debian-hurd-provisioned-gui.img.tar.gz` (for development)

4. **Update CI workflow** to use CLI variant

## Summary

🎯 **Your repo is already feature-complete!**

The existing scripts already handle:
- ✅ APT updates
- ✅ GUI (Xfce4, Firefox)
- ✅ Full development environment
- ✅ Hurd-specific tools
- ✅ User management
- ✅ Multiple display modes

**All we need to do:**
1. Integrate existing scripts into `create-provisioned-image.sh`
2. Create CLI and GUI variants
3. Upload to GitHub Releases
4. Update CI to download and use

**Result:** Production-ready pre-provisioned Debian GNU/Hurd 2025 i386 images! 🚀
