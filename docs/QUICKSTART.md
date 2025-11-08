# GNU/Hurd Docker - Quick Start Guide
**Last Updated:** 2025-11-06

---

## 🚀 Start the System (Ready to Go!)

### Using the 80GB Pre-Configured Image

```bash
# 1. Start QEMU with VNC (for GUI)
docker-compose up -d

# Wait 60 seconds for boot
sleep 60

# 2. Connect via VNC
vncviewer localhost:5901

# 3. Login
#    Username: root
#    Password: root

# 4. Start XFCE Desktop (if GUI packages installed)
startxfce4
```

---

## 📋 System Credentials

```
Username: root
Password: root

VNC Port: 5901
SSH Port: 2222 (if SSH installed)
Serial Console: telnet localhost 5555
```

---

## 🎯 Current Configuration

```yaml
Image: debian-hurd-i386-80gb.qcow2 (80GB virtual, ~2.4GB actual)
System: Debian GNU/Hurd 13 i386
CPU: Pentium 3 (1 core for stability)
RAM: 4 GB
Acceleration: KVM (if available)
Display: VNC on port 5901
```

---

## ✅ What's Included

### Development Tools
- gcc, g++, make, cmake, autoconf, automake
- git, gdb
- Python 3, Perl
- Hurd-specific: hurd-dev, gnumach-dev, mig

### GUI (If Installed)
- XFCE4 desktop environment
- xinit (for quick X11 start)
- firefox-esr, gimp, geany
- xfce4-terminal, mousepad, thunar

### Custom Shell Features
- Colorized prompt with Git branch
- Mach-specific aliases (mig-version, mach-info, etc.)
- Development shortcuts (cmake-debug, configure-release, etc.)
- Custom functions (mach-rebuild, mach-sysinfo, mach-doc)

---

## 🖥️ Starting the GUI

### Method 1: Simple (Recommended)
```bash
startxfce4
```

### Method 2: Using xinit
```bash
xinit /usr/bin/startxfce4 -- :0
```

### Method 3: Custom .xinitrc
```bash
echo "exec startxfce4" > ~/.xinitrc
chmod +x ~/.xinitrc
startx
```

---

## 🔧 Custom Shell Commands

After login, these custom commands are available:

```bash
# System Information
mach-sysinfo          # Complete Hurd system info
mach-info             # CPU and kernel info
mach-memory           # Memory usage
mig-version           # MIG version

# Development
mach-rebuild          # Auto-detect and rebuild project
cmake-debug           # Configure cmake in debug mode
cmake-release         # Configure cmake in release mode
configure-debug       # Configure autotools in debug
configure-release     # Configure autotools in release

# Git Shortcuts
gs                    # git status
ga                    # git add
gc                    # git commit
gp                    # git push
gl                    # git log --oneline --graph
gd                    # git diff

# File Operations
ll                    # ls -lahF --color
la                    # ls -AF --color

# Safety (interactive prompts)
rm, cp, mv            # All ask for confirmation
```

---

## 📂 File Sharing (Host ↔ Guest)

### Share Files from Host

```bash
# On host machine:
cp myfile.txt share/

# Inside Hurd VM:
mount /mnt/host
ls /mnt/host
cat /mnt/host/myfile.txt
```

### 9p Mount Details
```
Tag: scripts
Host Path: ./share/
Guest Mount: /mnt/host
Protocol: 9p over virtio
```

---

## 🌐 Network Ports

```
SSH:    localhost:2222 → guest:22   (if SSH installed)
HTTP:   localhost:8080 → guest:80
Custom: localhost:9999 → guest:9999
VNC:    localhost:5901
Serial: localhost:5555  (telnet)
```

---

## 📊 Verify Installation

```bash
# Check Hurd packages
dpkg -l | grep -E "hurd-dev|gnumach|mig"

# Check development tools
which gcc g++ make cmake git gdb python3

# Check GUI components
which startxfce4 startx xinit

# Test custom functions
type mach-rebuild mach-sysinfo

# View custom aliases
alias | grep mach-
```

---

## 🛠️ Common Tasks

### Update Packages
```bash
apt-get update
apt-get upgrade
```

### Install Additional Packages
```bash
apt-get install <package-name>
```

### Create New User
```bash
adduser myuser
usermod -aG sudo myuser
```

### Install SSH Server (If Not Present)
```bash
apt-get install openssh-server random-egd
systemctl enable ssh
systemctl start ssh

# Test from host:
ssh -p 2222 root@localhost
```

---

## 🔍 Troubleshooting

### VNC Not Connecting
```bash
# Check QEMU is running
docker-compose ps

# Check VNC port is open
ss -tlnp | grep 5901

# Restart container
docker-compose restart
```

### GUI Won't Start
```bash
# Check X11 installed
which startx xinit

# Check XFCE installed
which startxfce4

# Try manual X start
startx -- :0
```

### Shell Customizations Not Loading
```bash
# Reload .bashrc
source ~/.bashrc

# Verify customizations present
grep "Mach development" ~/.bashrc
```

### 9p Mount Not Working
```bash
# Manual mount
mount -t 9p -o trans=virtio scripts /mnt/host

# Check QEMU config
docker-compose logs | grep virtfs

# Verify fstab entry
cat /etc/fstab | grep 9p
```

---

## 📚 Documentation

- **System Audit:** `HURD-SYSTEM-AUDIT.md`
- **Custom Features:** `CUSTOM-HURD-FEATURES.md`
- **Comprehensive Guide:** `COMPREHENSIVE-IMAGE-GUIDE.md`
- **Scripts Reference:** `scripts/` directory

---

## 🎓 Next Steps

1. ✅ **Login:** root / root
2. ✅ **Test commands:** `mach-sysinfo`
3. ✅ **Start GUI:** `startxfce4`
4. ⬜ **Mount shared files:** `mount /mnt/host`
5. ⬜ **Create workspace:** `cd ~/workspace && mkdir myproject`
6. ⬜ **Start developing!**

---

## ❓ Need Help?

### Official Documentation
- GNU Hurd: https://www.gnu.org/software/hurd/
- Debian Hurd: https://www.debian.org/ports/hurd/
- FAQ: https://www.gnu.org/software/hurd/faq.html

### Scripts Help
```bash
./scripts/<script-name>.sh --help
```

### Container Logs
```bash
docker-compose logs -f
```

---

## 🎉 You're Ready!

The **Debian GNU/Hurd 13 i386** system is fully configured and ready for:
- Microkernel development
- Hurd-specific research
- GUI application testing
- General i386 development
- Educational purposes

**Enjoy exploring the GNU Hurd!** 🐃

---

**Repository:** gnu-hurd-docker
**Maintainer:** Oaich
**Generated:** 2025-11-06
