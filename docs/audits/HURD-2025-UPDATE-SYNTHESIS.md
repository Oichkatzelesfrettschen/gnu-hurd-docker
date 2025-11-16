# Debian GNU/Hurd 2025 Update Synthesis

**Date**: 2025-11-16
**Purpose**: Comprehensive analysis of official Debian GNU/Hurd 2025 release vs current repository
**Sources**:
1. Official YES_REALLY_README.txt from cdimage.debian.org
2. ChatGPT research on Hurd 2025 development workstation setup
3. Current gnu-hurd-docker repository state

---

## Executive Summary

### Critical Findings

1. **WRONG IMAGE URL**: Current repo uses `/latest/` but official 2025 release is in `/13.0/` directory
2. **Release Name**: "Debian GNU/Hurd 2025 'Trixie'" - snapshot of Debian sid at Trixie release time
3. **Date**: Release snapshot dated **2025-11-05** (November 5, 2025)
4. **Major Features Missing from Docs**: Rust/LLVM support, NetBSD Rump drivers, ACPI/APIC, SMP

---

## Detailed Comparison

### 1. Image Download URLs

#### ❌ Current Repository (INCORRECT)
```bash
# scripts/setup-hurd-amd64.sh line 22
https://cdimage.debian.org/cdimage/ports/latest/hurd-amd64/debian-hurd.img.tar.xz
```

#### ✅ Official README (CORRECT)
```bash
# Pre-installed image
http://cdimage.debian.org/cdimage/ports/13.0/hurd-amd64/debian-hurd.img.tar.xz

# Installer ISO
http://cdimage.debian.org/cdimage/ports/13.0/hurd-amd64/iso-cd/debian-hurd-2025-amd64-NETINST-1.iso
```

#### 📋 Action Required
- Update all download URLs to use `/13.0/` instead of `/latest/`
- Document that this is the official Debian 13 "Trixie" release
- Add installer ISO as alternative download option

---

### 2. Release Information

#### Official Details
- **Name**: Debian GNU/Hurd 2025 "Trixie"
- **Type**: Unofficial hurd-amd64 port (not part of official Debian Trixie)
- **Base**: Snapshot of Debian sid at time of Debian 13 Trixie release
- **Date**: November 2025 (snapshot 20251105)
- **Architecture**: hurd-amd64 (64-bit) + hurd-i386 (32-bit)
- **Package Coverage**: ~72% of Debian archive (from ChatGPT research)

#### Current Repository
- ✅ Correctly identifies as x86_64/amd64
- ✅ Correctly deprecated i386
- ❌ Missing "Trixie" release name
- ❌ Missing snapshot date (20251105) context
- ❌ Missing package coverage statistics

---

### 3. New Features in Hurd 2025

#### From ChatGPT Research (NOT in official README)
1. **64-bit Support**: First official amd64 release
2. **NetBSD Rump Drivers**: User-space disk drivers (no more Linux drivers in Mach!)
3. **ACPI/APIC Support**: Modern hardware initialization
4. **SMP Support**: Initial multi-core support (experimental)
5. **Rust/LLVM/Clang**: Full toolchain support since LLVM 8.0
6. **Package Count**: 72% of Debian archive (~65,000+ packages)

#### Current Documentation Status
- ✅ 64-bit support documented
- ⚠️ SMP mentioned but not detailed
- ❌ Rump drivers not mentioned
- ❌ ACPI/APIC not mentioned
- ❌ Rust/LLVM support not highlighted
- ❌ Package coverage statistics missing

---

### 4. QEMU Configuration

#### Official README Recommendations
```bash
# Basic KVM invocation
kvm -m 2G -drive file=$(echo debian-hurd*.img),cache=writeback

# With SSH forwarding
kvm -m 2G \
    -drive file=$(echo debian-hurd*.img),cache=writeback \
    -net user,hostfwd=tcp:127.0.0.1:2222-:22 \
    -net nic,model=e1000
```

#### Our Current Configuration (docker-compose.yml)
```yaml
QEMU_RAM: 4096          # We use 4GB (official recommends 2GB minimum)
QEMU_SMP: 2             # We use 2 cores
```

#### VirtualBox-Specific (from official README)
- **HPET Required**: `VBoxManage modifyvm <name> --hpet=on`
- **CPU Count**: 1 recommended (SMP still experimental)
- **Disk Controller**: IDE fallback if SATA issues
- **Input**: PS/2 only (NO USB HID support yet)
- **Network**: Intel PRO/1000 MT or AMD PCnet

#### Gaps in Current Docs
- ❌ HPET requirement for VirtualBox not documented
- ❌ PS/2-only input limitation not documented
- ❌ AMD PCnet as fallback NIC not mentioned
- ❌ cache=writeback recommendation not explained

---

### 5. System Configuration

#### Default Accounts (Official)
```
User: root    Password: (empty/none)
User: demo    Password: (empty/none)
```

#### Our Current Setup
```
User: root    Password: root
User: agents  Password: agents
```

**Analysis**: We added passwords for security - this is GOOD but needs documentation that official image has NO passwords.

#### APT Sources (from ChatGPT Research)
```bash
# Snapshot archive (for 2025-11-05 release)
deb [check-valid-until=no trusted=yes] \
  https://snapshot.debian.org/archive/debian-ports/20251105T000000Z/ sid main
deb [check-valid-until=no trusted=yes] \
  https://snapshot.debian.org/archive/debian-ports/20251105T000000Z/ unreleased main

# Current unstable (for updates)
deb http://deb.debian.org/debian-ports unstable main
deb http://deb.debian.org/debian-ports unreleased main
```

**Missing from our docs**: Complete APT sources configuration for Hurd 2025!

---

### 6. Installation Best Practices

#### From Official README
1. **Desktop Installation**: DON'T install desktop during initial install
   - Snapshot mirror is very slow
   - Can timeout
   - Install base system first, add desktop later with apt
2. **Preferred Desktop**: LXDE (GNOME and KDE not fully working)
3. **Partitioning**: Single partition for all (NO separate /usr or /usr/local)
4. **Memory**: 500MB minimum for text installer, 2GB for graphical
5. **Disk Expansion**: Use qemu-img resize + parted + resize2fs

#### From ChatGPT Research
1. **Hurd Console**: Must be started manually and enabled in `/etc/default/hurd-console`
2. **X11 Configuration**: Run `dpkg-reconfigure x11-common` to allow non-root X
3. **Display Manager**: Use XDM (GDM and LightDM don't work)
4. **Filesystem**: ext2 with xattr for translators - MUST shutdown properly!
5. **Keyboard Layout**: `dpkg-reconfigure keyboard-configuration`

#### Missing from Our Docs
- ❌ Desktop installation warnings
- ❌ Hurd console setup steps
- ❌ X11/GUI configuration guide
- ❌ Filesystem fragility warnings
- ❌ Partition layout requirements

---

### 7. Hurd-Specific Features

#### Translator Examples (from Official README)

**Hello World Translator:**
```bash
touch hello
settrans hello /hurd/hello
cat hello
# Output: Hello World!

fsysopts hello --contents='Hello GNU!\n'
cat hello
# Output: Hello GNU!

settrans -g hello  # Remove translator
```

**Transparent FTP:**
```bash
settrans -c ftp: /hurd/hostmux /hurd/ftpfs /
ls ftp://ftp.gnu.org/
```

**Mount Remote ISO:**
```bash
settrans -c mnt /hurd/iso9660fs \
  $PWD/ftp://ftp.gnu.org/old-gnu/gnu-f2/hurd-F2-main.iso
ls mnt/
```

**Current Status**: We have ZERO translator examples in our documentation!

---

### 8. Development Environment

#### From ChatGPT Research

**MIG (Mach Interface Generator)**:
```bash
apt install mig         # Installs mig-x86_64-gnu
```

**Building GNU Mach with SMP**:
```bash
git clone https://git.savannah.gnu.org/git/hurd/gnumach.git
cd gnumach && autoreconf -i && mkdir build && cd build
../configure --enable-ncpus=4 --enable-apic --enable-kdb --disable-linux-groups
make -j4 gnumach.gz
```

**Device Naming Change**:
- Old: `hd0` (IDE)
- New: `wd0` (NetBSD Rump nomenclature)
- Must update GRUB and /etc/fstab!

**Debugging**:
- Kernel: `--enable-kdb` for built-in debugger
- QEMU: `-S -s` for GDB stub
- User-space: Standard GDB works
- RPC tracing: `trace` command from hurd package

**Current Status**:
- ❌ MIG not documented
- ❌ Kernel building not documented
- ❌ Device naming changes not documented
- ❌ Debugging tools not documented

---

### 9. Known Limitations

#### From Official README
1. No firmware loading support (no non-free firmware)
2. No wireless network support
3. No sound support yet
4. SATA only in AHCI mode (not RAID)

#### From ChatGPT Research
1. No USB HID devices (keyboard/mouse must be PS/2)
2. No native Docker support (requires Mach-on-Linux port)
3. SMP experimental (can cause crashes with >1 CPU)
4. strace doesn't exist (use `trace` for RPC tracing)
5. procfs limited (exists but minimal)

#### Current Documentation
- ✅ Notes that Hurd runs in QEMU VM, not native container
- ❌ Missing specific hardware limitation details
- ❌ Missing SMP stability warnings
- ❌ Missing USB limitations

---

### 10. Testing and Verification

#### Official README
- Recommends KVM for best experience
- Real hardware "mileage will vary" due to limited driver testing
- Stick with well-tested KVM environment

#### ChatGPT Research
- VirtualBox less tested than KVM
- QEMU/KVM most tested and recommended
- First boot may take 1-2 minutes for font caching
- Use snapshots before risky experiments

#### Our Current Testing
- ✅ We have test scripts
- ✅ We have health checks
- ⚠️ Need to document first-boot timing expectations
- ⚠️ Need to emphasize KVM preference

---

## Priority Action Items

### Critical (Must Fix Immediately)
1. ✅ Update image URLs from `/latest/` to `/13.0/`
2. ✅ Add Trixie release name and 20251105 snapshot date
3. ✅ Document NetBSD Rump drivers and device naming changes
4. ✅ Add APT sources configuration for Hurd 2025

### High Priority (Important Features)
5. ✅ Document Rust/LLVM/Clang support
6. ✅ Add ACPI/APIC and SMP information
7. ✅ Create translator examples section
8. ✅ Add GUI/X11 setup guide
9. ✅ Document Hurd console setup

### Medium Priority (Nice to Have)
10. ✅ Add development environment guide (MIG, kernel building)
11. ✅ Document VirtualBox HPET requirement
12. ✅ Add filesystem safety warnings
13. ✅ Document hardware limitations
14. ✅ Add installer ISO option

### Low Priority (Documentation Polish)
15. ✅ Add package coverage statistics (72%)
16. ✅ Expand troubleshooting with common issues
17. ✅ Add links to official Hurd FAQ and documentation
18. ✅ Document debugging tools and techniques

---

## Files Requiring Updates

### Scripts
- ✅ `scripts/download-image.sh` - Update URL to /13.0/
- ✅ `scripts/setup-hurd-amd64.sh` - Update URL to /13.0/
- ✅ `scripts/download-released-image.sh` - Update URL to /13.0/

### Documentation
- ✅ `README.md` - Add Trixie, new features, translator examples
- ✅ `docs/01-GETTING-STARTED/INSTALLATION.md` - Add GUI setup, APT sources
- ✅ `docs/01-GETTING-STARTED/QUICKSTART.md` - Update URLs
- ✅ `docs/02-ARCHITECTURE/OVERVIEW.md` - Add Rump drivers, ACPI/APIC
- ✅ `docs/02-ARCHITECTURE/SYSTEM-DESIGN.md` - Add device naming changes
- ✅ `docs/03-CONFIGURATION/USER-CONFIGURATION.md` - Add Hurd console setup
- ✅ `docs/06-TROUBLESHOOTING/COMMON-ISSUES.md` - Add hardware limitations
- ✅ CREATE: `docs/04-OPERATION/TRANSLATORS.md` - Translator examples and guide
- ✅ CREATE: `docs/04-OPERATION/GUI-SETUP.md` - X11 and desktop setup
- ✅ CREATE: `docs/07-RESEARCH/DEVELOPMENT-ENVIRONMENT.md` - MIG, kernel building

### Configuration
- ⚠️ `docker-compose.yml` - Consider documenting cache=writeback
- ⚠️ `Dockerfile` - Add comments about Hurd 2025 features

---

## References

**Official Documentation:**
- YES_REALLY_README.txt: http://cdimage.debian.org/cdimage/ports/13.0/hurd-amd64/YES_REALLY_README.txt
- Debian Hurd FAQ: https://darnassus.sceen.net/~hurd-web/faq/
- GNU Hurd FAQ: http://www.gnu.org/software/hurd/faq.html
- Open Issues: http://www.gnu.org/software/hurd/open_issues.html
- Install Guide: http://www.debian.org/ports/hurd/hurd-install

**Community:**
- Mailing List: debian-hurd@lists.debian.org
- Upstream: bug-hurd@gnu.org
- IRC: #hurd on Freenet, #debian-hurd on OFTC

**Source Code:**
- GNU Mach: https://git.savannah.gnu.org/git/hurd/gnumach.git
- GNU Hurd: https://git.savannah.gnu.org/git/hurd/hurd.git
- Glibc (Hurd): https://sourceware.org/git/glibc.git

---

## Conclusion

The Debian GNU/Hurd 2025 "Trixie" release represents a **major milestone** with 64-bit support, modern hardware support (ACPI/APIC), user-space Rump drivers, and even Rust/LLVM. Our repository is largely correct but missing:

1. **Correct official URLs** (critical!)
2. **Release context** (Trixie, snapshot date)
3. **New features documentation** (Rump, ACPI, Rust)
4. **Hurd-specific guides** (translators, GUI setup, development)
5. **Hardware limitations** (USB, sound, SMP stability)

With these updates, our repository will be the **definitive guide** for running Debian GNU/Hurd 2025 in Docker/QEMU environments.
