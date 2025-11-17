# GNU/Hurd GUI and Desktop Environment Setup

**Last Updated**: 2025-11-16
**Source**: Official Debian GNU/Hurd 2025 documentation and community research
**Purpose**: Complete guide to setting up graphical desktop on Debian GNU/Hurd
**Tested On**: Debian GNU/Hurd 2025 "Trixie" (snapshot 2025-11-05)

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Hurd Console Setup](#hurd-console-setup)
4. [X11 Installation](#x11-installation)
5. [Desktop Environments](#desktop-environments)
6. [Display Managers](#display-managers)
7. [Configuration](#configuration)
8. [Troubleshooting](#troubleshooting)
9. [Known Limitations](#known-limitations)
10. [References](#references)

---

## Overview

Debian GNU/Hurd 2025 supports X11 and graphical desktop environments. While not as polished as Linux, you can run a functional desktop with window managers and applications.

### What Works

✅ X.Org Server (using VESA driver)
✅ Hurd Console (text mode with VT support)
✅ LXDE Desktop Environment (recommended)
✅ Lightweight window managers (IceWM, Openbox, Fluxbox)
✅ XDM display manager
✅ Basic X11 applications (xterm, firefox-esr, etc.)

### What Doesn't Work

❌ GNOME (not fully functional)
❌ KDE Plasma (not fully functional)
❌ GDM / LightDM display managers
❌ Hardware 3D acceleration
❌ Wayland (X11 only)
❌ USB input devices (PS/2 only)

---

## Prerequisites

### System Requirements

- **RAM**: Minimum 2 GB, recommended 4 GB for GUI
- **Display**: VESA-compatible graphics (provided by QEMU/VirtualBox)
- **Input**: PS/2 keyboard and mouse (USB NOT supported)
- **Storage**: Additional 2-3 GB for desktop packages

### Base System

Ensure you have a working Hurd system with network access:

```bash
# Test network connectivity
ping -c 3 debian.org

# Update package lists
apt update

# Ensure sudo is installed
apt install sudo

# Add your user to sudo group (if needed)
adduser $USER sudo
```

---

## Hurd Console Setup

The **Hurd Console** is required for X11 to work. It provides keyboard and mouse input devices that X.Org needs.

### Step 1: Start Hurd Console

Check if Hurd console is already running:

```bash
echo $TERM
# If output is "hurd", console is running
# If output is "mach", you're on low-level Mach console

# Check for console devices
ls /dev/cons/
# Should show: kbd, mouse, vcs, display, etc.
```

### Step 2: Manual Console Start

If console is not running, start it manually:

```bash
# As root
sudo console -d vga -d pc_mouse --repeat=mouse -d pc_kbd --repeat=kbd -d generic_speaker -c /dev/vcs
```

**Explanation**:
- `-d vga` - VGA display output
- `-d pc_mouse --repeat=mouse` - PS/2 mouse with repeater
- `-d pc_kbd --repeat=kbd` - PS/2 keyboard with repeater
- `-d generic_speaker` - PC speaker (beep)
- `-c /dev/vcs` - Console device

### Step 3: Enable Console on Boot

Edit the Hurd console configuration:

```bash
sudo nano /etc/default/hurd-console
```

Change `ENABLE` to `true`:

```bash
# Enable Hurd console at boot
ENABLE="true"
```

Save and exit. Console will start automatically on next boot.

### Step 4: Switch Between Consoles

- **Alt+F1, Alt+F2, ..., Alt+F6** - Switch virtual terminals
- **Ctrl+Alt+Backspace** - Return to Mach console (from Hurd console)

---

## X11 Installation

### Step 1: Allow Non-Root X Server

Reconfigure X11 permissions:

```bash
sudo dpkg-reconfigure x11-common
```

Select: **Anybody** (allow any user to start X)

This is required because Hurd's X wrapper doesn't recognize Hurd-specific permissions.

### Step 2: Install X.Org

```bash
# Install X.Org server and basic utilities
sudo apt install xorg xterm rxvt

# Install window manager (choose one or more)
sudo apt install icewm          # Lightweight, recommended
# sudo apt install openbox       # Minimal, very fast
# sudo apt install fluxbox       # Lightweight, customizable
```

**Note**: Don't install full desktop environments yet - start minimal to verify X works.

### Step 3: Create Basic X Configuration (Optional)

Most setups work without manual `xorg.conf`, but you may want these tweaks:

#### Enable Ctrl+Alt+Backspace to Kill X

Create `/etc/X11/xorg.conf` or `/etc/X11/xorg.conf.d/10-keyboard.conf`:

```bash
sudo mkdir -p /etc/X11/xorg.conf.d
sudo nano /etc/X11/xorg.conf.d/10-keyboard.conf
```

Add:

```
Section "InputDevice"
    Identifier "Generic Keyboard"
    Driver "kbd"
    Option "XkbOptions" "terminate:ctrl_alt_bksp"
EndSection
```

#### Fix Screen Resolution Issues

If X chooses wrong resolution (letterboxing or scrolling):

```bash
sudo nano /etc/X11/xorg.conf.d/20-screen.conf
```

Add:

```
Section "Screen"
    Identifier "Default Screen"
    SubSection "Display"
        Virtual 1024 768    # Force 1024x768
    EndSubSection
EndSection
```

Common resolutions:
- `1024 768` - 4:3 standard
- `1280 720` - 16:9 HD
- `1920 1080` - 16:9 Full HD

### Step 4: Test X11

Start X manually (as normal user, not root):

```bash
startx /usr/bin/icewm
```

If successful:
- IceWM window manager should appear
- Right-click desktop for menu
- Try opening xterm from menu

**To exit**: Right-click → Logout, or press Ctrl+Alt+Backspace

---

## Desktop Environments

### LXDE (Recommended)

LXDE is the **only fully functional desktop environment** on Hurd 2025.

#### Installation

**WARNING**: Installing from snapshot mirror during Debian installation can be very slow and may timeout. Install from running system instead:

```bash
# Update APT sources first (see APT Configuration section below)
sudo apt update

# Install LXDE
sudo apt install lxde-core

# Or full LXDE with extras
sudo apt install lxde
```

**Packages included**:
- Openbox (window manager)
- LXPanel (panel/taskbar)
- PCManFM (file manager)
- LXTerminal (terminal)
- LXAppearance (theme manager)

#### Starting LXDE

```bash
startx /usr/bin/startlxde
```

Or via display manager (see below).

---

### Minimal Window Managers

For lighter systems or testing:

#### IceWM (Lightweight)

```bash
sudo apt install icewm
startx /usr/bin/icewm
```

**Features**: Menu bar, taskbar, minimal resource usage

#### Openbox (Minimal)

```bash
sudo apt install openbox obconf obmenu
startx /usr/bin/openbox
```

**Features**: Right-click menu, highly customizable, very fast

#### Fluxbox (Customizable)

```bash
sudo apt install fluxbox
startx /usr/bin/fluxbox
```

**Features**: Tabs, customizable themes, lightweight

---

### What Doesn't Work

#### GNOME

GNOME 3+ requires systemd and many modern Linux-specific features:

```bash
# NOT RECOMMENDED - will fail
sudo apt install gnome  # Broken dependencies, won't install fully
```

#### KDE Plasma

KDE has similar issues with missing dependencies:

```bash
# NOT RECOMMENDED - will fail
sudo apt install kde-plasma-desktop  # Many missing packages
```

**Alternative**: Use LXDE or lightweight WMs instead.

---

## Display Managers

Display managers provide graphical login screens.

### XDM (Recommended - Only One That Works)

```bash
# Install XDM
sudo apt install xdm

# Start XDM service
sudo service xdm start

# Enable on boot
sudo systemctl enable xdm  # If systemd available
# Or manually add to /etc/rc.local
```

**Configuration**: Edit `/etc/X11/xdm/Xsession` to set default session

### GDM / LightDM (DO NOT USE)

**Do NOT install GDM or LightDM** - they require systemd features not available on Hurd:

```bash
# BROKEN - DO NOT INSTALL
sudo apt install gdm3       # Will fail to start
sudo apt install lightdm    # Will fail to start
```

If accidentally installed, remove and use XDM:

```bash
sudo apt remove gdm3 lightdm
sudo apt install xdm
```

---

## Configuration

### APT Sources for Desktop Packages

To install desktop packages efficiently, configure proper APT sources:

#### Snapshot Archive (2025-11-05 Release)

```bash
sudo nano /etc/apt/sources.list
```

Add snapshot sources for Hurd 2025:

```
# Debian GNU/Hurd 2025 "Trixie" Snapshot (2025-11-05)
deb [check-valid-until=no trusted=yes] https://snapshot.debian.org/archive/debian-ports/20251105T000000Z/ sid main
deb [check-valid-until=no trusted=yes] https://snapshot.debian.org/archive/debian-ports/20251105T000000Z/ unreleased main
deb-src [check-valid-until=no trusted=yes] https://snapshot.debian.org/archive/debian/20251105T000000Z/ sid main
```

#### Current Unstable (For Updates)

```
# Current Debian Ports (unstable)
deb http://deb.debian.org/debian-ports unstable main
deb http://deb.debian.org/debian-ports unreleased main
deb-src http://deb.debian.org/debian unstable main
```

Update and install archive keyring:

```bash
sudo apt update
sudo apt install debian-ports-archive-keyring
```

### Keyboard Layout

```bash
sudo dpkg-reconfigure keyboard-configuration
```

Select your keyboard layout (e.g., US, UK, German, etc.)

### Timezone

```bash
# Method 1: Direct edit
sudo nano /etc/timezone
# Add: America/New_York (or your timezone)

# Method 2: Reconfigure
sudo dpkg-reconfigure tzdata
```

### Font Configuration

X may be slow on first start due to font caching:

```bash
# Rebuild font cache
fc-cache -f -v

# Install additional fonts (optional)
sudo apt install fonts-dejavu fonts-liberation
```

---

## Troubleshooting

### X Won't Start

**Symptom**: `startx` fails or crashes

**Solutions**:

1. **Check Hurd console is running**:
   ```bash
   ls /dev/cons/kbd /dev/cons/mouse
   # If missing, start console (see above)
   ```

2. **Check X log**:
   ```bash
   cat /var/log/Xorg.0.log | grep EE
   # Look for ERROR lines
   ```

3. **Try VESA driver explicitly**:
   ```bash
   sudo nano /etc/X11/xorg.conf.d/30-device.conf
   ```

   Add:
   ```
   Section "Device"
       Identifier "VGA"
       Driver "vesa"
   EndSection
   ```

4. **Reset X configuration**:
   ```bash
   sudo rm /etc/X11/xorg.conf
   startx
   ```

### Keyboard/Mouse Not Working

**Symptom**: No input in X11

**Solution**:

```bash
# Verify devices exist
ls -la /dev/cons/kbd /dev/cons/mouse

# Restart Hurd console
sudo killall console
sudo console -d vga -d pc_mouse --repeat=mouse -d pc_kbd --repeat=kbd -d generic_speaker -c /dev/vcs
```

### Screen Resolution Wrong

**Symptom**: Letterboxing, scrolling desktop, or wrong aspect ratio

**Solution**:

Create `/etc/X11/xorg.conf.d/20-screen.conf`:

```
Section "Screen"
    Identifier "Default Screen"
    SubSection "Display"
        Virtual 1024 768
    EndSubSection
EndSection
```

### First Boot Slow

**Symptom**: X takes 1-2 minutes to start on first boot

**Explanation**: Font cache generation - this is normal

**Solution**: Wait. Subsequent starts will be faster.

### Package Installation Fails

**Symptom**: apt install times out or fails

**Cause**: Snapshot mirror can be slow

**Solution**:

1. Use current unstable mirror (see APT sources above)
2. Install packages individually
3. Increase timeout:
   ```bash
   sudo apt -o Acquire::http::Timeout=300 install <package>
   ```

---

## Known Limitations

### Hardware

- ❌ **No USB input**: Must use PS/2 keyboard/mouse (emulated in QEMU/VirtualBox)
- ❌ **No 3D acceleration**: Only software rendering (VESA driver)
- ❌ **No sound**: Audio drivers not yet available
- ❌ **No wireless**: No WiFi support

### Software

- ❌ **No systemd**: Some packages expect systemd
- ❌ **No Wayland**: X11 only
- ❌ **Limited font rendering**: No full fontconfig support yet
- ❌ **Firefox ESR only**: Modern Firefox requires newer dependencies

### Virtual Machines

#### QEMU/KVM
- ✅ Works well with VGA output
- ✅ Use `-vga std` or `-vga cirrus`
- ✅ E1000 network adapter

#### VirtualBox
- ✅ Works but requires HPET:
  ```bash
  VBoxManage modifyvm "Hurd VM" --hpet on
  ```
- ✅ Use PS/2 mouse (disable USB tablet)
- ✅ Intel PRO/1000 MT network adapter
- ⚠️ Use 1 CPU only (SMP experimental)

---

## Example Session

Complete setup from scratch:

```bash
# 1. Enable Hurd console
sudo nano /etc/default/hurd-console
# Set ENABLE="true"
sudo reboot

# 2. Update sources (see APT Configuration above)
sudo nano /etc/apt/sources.list
sudo apt update

# 3. Install X and LXDE
sudo dpkg-reconfigure x11-common  # Select "Anybody"
sudo apt install xorg lxde-core xdm

# 4. Configure keyboard
sudo dpkg-reconfigure keyboard-configuration

# 5. Start X via XDM
sudo service xdm start

# Or start manually
startx /usr/bin/startlxde
```

---

## References

### Official Documentation

- **Debian Hurd X11 Guide**: http://www.debian.org/ports/hurd/hurd-install#x11
- **Hurd Console**: https://www.gnu.org/software/hurd/hurd/console.html
- **X.Org on Hurd**: https://www.gnu.org/software/hurd/hurd/running/x.html

### Community Resources

- **Hurd FAQ**: https://darnassus.sceen.net/~hurd-web/faq/
- **Debian Hurd Mailing List**: debian-hurd@lists.debian.org
- **IRC**: #hurd on Freenet, #debian-hurd on OFTC

---

## Quick Reference

```bash
# Hurd console
sudo console -d vga -d pc_mouse --repeat=mouse -d pc_kbd --repeat=kbd -c /dev/vcs

# X11 setup
sudo dpkg-reconfigure x11-common
sudo apt install xorg icewm

# Start X manually
startx /usr/bin/icewm

# LXDE
sudo apt install lxde-core
startx /usr/bin/startlxde

# Display manager
sudo apt install xdm
sudo service xdm start

# Keyboard layout
sudo dpkg-reconfigure keyboard-configuration
```

---

## See Also

- [TRANSLATORS.md](TRANSLATORS.md) - Hurd translator guide
- [INTERACTIVE-ACCESS.md](INTERACTIVE-ACCESS.md) - Accessing Hurd
- [../02-ARCHITECTURE/OVERVIEW.md](../02-ARCHITECTURE/OVERVIEW.md) - System architecture
- [../06-TROUBLESHOOTING/COMMON-ISSUES.md](../06-TROUBLESHOOTING/COMMON-ISSUES.md) - Troubleshooting

---

**Note**: GUI on Hurd is functional but not polished. Expect slower performance than Linux and some rough edges. For development work, SSH access may be more productive than GUI.
