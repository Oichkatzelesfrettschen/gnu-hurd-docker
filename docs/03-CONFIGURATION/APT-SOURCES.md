# APT Sources Configuration for Debian GNU/Hurd 2025

**Last Updated**: 2025-11-16
**Purpose**: Configure APT sources for optimal package installation on Hurd 2025
**Scope**: Debian GNU/Hurd 2025 "Trixie" (snapshot 2025-11-05)

---

## Table of Contents

1. [Overview](#overview)
2. [Understanding Hurd Package Sources](#understanding-hurd-package-sources)
3. [Recommended Configuration](#recommended-configuration)
4. [Alternative Configurations](#alternative-configurations)
5. [Package Installation](#package-installation)
6. [Troubleshooting](#troubleshooting)
7. [References](#references)

---

## Overview

Debian GNU/Hurd uses a combination of **snapshot archives** and **current unstable** repositories to provide both stability and up-to-date packages.

### Why Multiple Sources?

1. **Snapshot Archive** (2025-11-05): Fixed release point, guaranteed package versions
2. **Unstable (sid)**: Latest packages and security updates
3. **Unreleased**: Hurd-specific patches not yet in main Debian

---

## Understanding Hurd Package Sources

### Repository Types

#### 1. Debian Ports (debian-ports)

**URL**: `http://deb.debian.org/debian-ports`

**Purpose**: Architecture-specific packages for Hurd (hurd-amd64, hurd-i386)

**Suites**:
- `unstable` (sid) - Current development packages
- `unreleased` - Hurd-specific patches

#### 2. Debian Main

**URL**: `http://deb.debian.org/debian`

**Purpose**: Architecture-independent source packages

**Usage**: Source packages only (`deb-src`)

#### 3. Snapshot Archive

**URL**: `https://snapshot.debian.org/archive/debian-ports/<timestamp>/`

**Purpose**: Fixed point-in-time packages for reproducibility

**Timestamp**: `20251105T000000Z` for Hurd 2025 "Trixie"

---

## Recommended Configuration

### Configuration 1: Hybrid (Snapshot + Unstable)

This is the **recommended configuration** for most users - combines stability of snapshot with freshness of unstable.

#### Edit `/etc/apt/sources.list`

```bash
sudo nano /etc/apt/sources.list
```

#### Complete Configuration

```bash
# Debian GNU/Hurd 2025 "Trixie" APT Sources
# Hybrid configuration: Snapshot + Unstable

# ==============================================================================
# SNAPSHOT ARCHIVE (Debian 13 "Trixie" - 2025-11-05)
# ==============================================================================
# Fixed point-in-time for reproducibility
# Use check-valid-until=no because snapshots are historical

# Binary packages (hurd-amd64 architecture)
deb [check-valid-until=no trusted=yes] https://snapshot.debian.org/archive/debian-ports/20251105T000000Z/ sid main
deb [check-valid-until=no trusted=yes] https://snapshot.debian.org/archive/debian-ports/20251105T000000Z/ unreleased main

# Source packages (architecture-independent)
deb-src [check-valid-until=no trusted=yes] https://snapshot.debian.org/archive/debian/20251105T000000Z/ sid main

# ==============================================================================
# CURRENT UNSTABLE (Rolling updates)
# ==============================================================================
# Latest packages and security updates

# Binary packages (hurd-amd64)
deb http://deb.debian.org/debian-ports unstable main
deb http://deb.debian.org/debian-ports unreleased main

# Source packages
deb-src http://deb.debian.org/debian unstable main

# ==============================================================================
# NOTES:
# - Snapshot provides base system stability
# - Unstable provides latest packages and security updates
# - APT will prefer newer versions from unstable when available
# - Use apt-cache policy <package> to check which source will be used
# ==============================================================================
```

#### Apply Configuration

```bash
# Update package lists
sudo apt update

# Install archive keyring (if needed)
sudo apt install debian-ports-archive-keyring

# Upgrade to latest versions
sudo apt upgrade
```

---

## Alternative Configurations

### Configuration 2: Unstable Only (Bleeding Edge)

For users who want **only the latest packages**:

```bash
# /etc/apt/sources.list - Unstable only

# Current Debian Ports (unstable)
deb http://deb.debian.org/debian-ports unstable main
deb http://deb.debian.org/debian-ports unreleased main

# Source packages
deb-src http://deb.debian.org/debian unstable main
```

**Pros**:
- Always latest packages
- Faster package fetching (no snapshot server)
- Immediate security updates

**Cons**:
- Less stability
- Possible package conflicts
- Breaking changes more frequent

---

### Configuration 3: Snapshot Only (Maximum Stability)

For users who need **reproducible builds** or **maximum stability**:

```bash
# /etc/apt/sources.list - Snapshot only

# Snapshot Archive (2025-11-05)
deb [check-valid-until=no trusted=yes] https://snapshot.debian.org/archive/debian-ports/20251105T000000Z/ sid main
deb [check-valid-until=no trusted=yes] https://snapshot.debian.org/archive/debian-ports/20251105T000000Z/ unreleased main
deb-src [check-valid-until=no trusted=yes] https://snapshot.debian.org/archive/debian/20251105T000000Z/ sid main
```

**Pros**:
- Guaranteed reproducibility
- No unexpected updates
- Stable package versions

**Cons**:
- No security updates
- Missing newer packages
- Snapshot server can be slow

---

## Package Installation

### Update Package Lists

After changing sources:

```bash
sudo apt update
```

### Install Basic Tools

```bash
# Development tools
sudo apt install \
    build-essential \
    git \
    vim \
    gdb

# System utilities
sudo apt install \
    sudo \
    ssh \
    wget \
    curl \
    htop
```

### Install GUI (LXDE)

```bash
# LXDE desktop (recommended for Hurd)
sudo apt install lxde-core

# Or full LXDE with extras
sudo apt install lxde

# X11 display manager
sudo apt install xdm
```

### Check Package Source

To see which repository a package comes from:

```bash
# Show package policy
apt-cache policy <package-name>

# Example: Check vim
apt-cache policy vim

# Output shows:
#   Installed: (version)
#   Candidate: (version)
#   Version table:
#     (version) 500
#       500 http://deb.debian.org/debian-ports unstable/main hurd-amd64 Packages
```

### Pin to Specific Source

If you want to force installation from snapshot:

Create `/etc/apt/preferences.d/snapshot-priority`:

```
Package: *
Pin: origin snapshot.debian.org
Pin-Priority: 1001
```

Or for unstable priority:

```
Package: *
Pin: release o=Debian,a=unstable
Pin-Priority: 900
```

---

## Troubleshooting

### Issue: apt update fails with "Release file expired"

**Symptom**:
```
E: Release file for https://snapshot.debian.org/.../Release is not valid yet
```

**Solution**: Add `check-valid-until=no` to snapshot sources:

```bash
deb [check-valid-until=no trusted=yes] https://snapshot.debian.org/...
```

---

### Issue: GPG signature errors

**Symptom**:
```
GPG error: The following signatures couldn't be verified
```

**Solution**: Install archive keyring:

```bash
# Download keyring from unstable
wget http://deb.debian.org/debian-ports/pool/main/d/debian-ports-archive-keyring/debian-ports-archive-keyring_2023.02.01_all.deb

# Install manually
sudo dpkg -i debian-ports-archive-keyring_2023.02.01_all.deb

# Update again
sudo apt update
```

Or use `trusted=yes` (less secure):

```bash
deb [trusted=yes] http://deb.debian.org/debian-ports unstable main
```

---

### Issue: Package not found

**Symptom**:
```
E: Package 'foo' has no installation candidate
```

**Solutions**:

1. **Check package exists for hurd-amd64**:
   ```bash
   apt-cache search <package-name>
   ```

2. **Check Debian Ports website**:
   https://buildd.debian.org/status/package.php?p=<package-name>&suite=sid

3. **Try source package**:
   ```bash
   apt source <package-name>
   cd <package-name>-*/
   dpkg-buildpackage -b
   sudo dpkg -i ../<package-name>_*.deb
   ```

---

### Issue: apt install times out

**Symptom**: Download hangs or times out (especially on snapshot server)

**Solutions**:

1. **Increase timeout**:
   ```bash
   sudo apt -o Acquire::http::Timeout=300 install <package>
   ```

2. **Switch to unstable** (faster mirror):
   Comment out snapshot lines, use only unstable

3. **Use different mirror**:
   Try `ftp.de.debian.org` or other Debian mirrors

4. **Download manually**:
   ```bash
   wget http://deb.debian.org/debian-ports/pool/main/.../package.deb
   sudo dpkg -i package.deb
   sudo apt install -f  # Fix dependencies
   ```

---

### Issue: Dependency conflicts

**Symptom**:
```
The following packages have unmet dependencies:
  foo : Depends: bar (>= 1.2.3) but 1.2.2 is to be installed
```

**Solutions**:

1. **Update all packages first**:
   ```bash
   sudo apt update
   sudo apt upgrade
   sudo apt install <package>
   ```

2. **Use aptitude** (better dependency resolver):
   ```bash
   sudo apt install aptitude
   sudo aptitude install <package>
   ```

3. **Check package version**:
   ```bash
   apt-cache policy <package>
   ```

---

## Advanced Configuration

### Using apt-cacher-ng (Local Cache)

Speed up package installation with local caching:

```bash
# On host machine (Linux), install apt-cacher-ng
sudo apt install apt-cacher-ng

# In Hurd VM, point to cache
echo 'Acquire::http::Proxy "http://10.0.2.2:3142";' | sudo tee /etc/apt/apt.conf.d/02proxy

# Now apt uses local cache
sudo apt update
sudo apt install <package>  # Downloads cached
```

### Offline Package Installation

Prepare packages on internet-connected machine:

```bash
# Download package and dependencies
apt download <package>
apt-cache depends <package> | grep Depends | awk '{print $2}' | xargs apt download

# Transfer .deb files to Hurd system
# Install offline
sudo dpkg -i *.deb
```

---

## References

### Official Documentation

- **Debian Ports**: http://deb.debian.org/debian-ports/
- **Snapshot Archive**: https://snapshot.debian.org/
- **Debian Hurd Packages**: https://packages.debian.org/source/sid/hurd
- **Package Build Status**: https://buildd.debian.org/status/

### Community Resources

- **Debian Hurd Mailing List**: debian-hurd@lists.debian.org
- **Hurd FAQ**: https://darnassus.sceen.net/~hurd-web/faq/
- **IRC**: #debian-hurd on OFTC

---

## Quick Reference

```bash
# Recommended /etc/apt/sources.list
# Snapshot (base)
deb [check-valid-until=no trusted=yes] https://snapshot.debian.org/archive/debian-ports/20251105T000000Z/ sid main
deb [check-valid-until=no trusted=yes] https://snapshot.debian.org/archive/debian-ports/20251105T000000Z/ unreleased main
# Unstable (updates)
deb http://deb.debian.org/debian-ports unstable main
deb http://deb.debian.org/debian-ports unreleased main
# Source
deb-src http://deb.debian.org/debian unstable main

# Update and install
sudo apt update
sudo apt install debian-ports-archive-keyring
sudo apt upgrade

# Check package source
apt-cache policy <package>

# Install with timeout
sudo apt -o Acquire::http::Timeout=300 install <package>
```

---

## See Also

- [GUI-SETUP.md](../04-OPERATION/GUI-SETUP.md) - Installing desktop environment
- [DEVELOPMENT-ENVIRONMENT.md](../07-RESEARCH-AND-LESSONS/DEVELOPMENT-ENVIRONMENT.md) - Dev tools
- [INSTALLATION.md](../01-GETTING-STARTED/INSTALLATION.md) - Initial setup
- [TROUBLESHOOTING](../06-TROUBLESHOOTING/COMMON-ISSUES.md) - General troubleshooting

---

**Pro Tip**: Use the hybrid configuration (snapshot + unstable) for best balance of stability and freshness!
