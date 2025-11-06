# Local QEMU Testing Guide - GNU/Hurd Setup

**Date:** 2025-11-05
**Purpose:** Test Hurd locally before optimizing Docker config

---

## QEMU Instance Running

**Status:** ✅ QEMU started with PID in background
**Display:** GTK window should be open on your desktop
**Monitor:** stdio (type commands in terminal)

### Current QEMU Configuration

```bash
qemu-system-i386 \
  -enable-kvm \
  -m 2048 \
  -cpu pentium3 \
  -drive file=debian-hurd-i386-20250807.qcow2,format=qcow2,cache=writeback,aio=threads,if=ide \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device e1000,netdev=net0 \
  -display gtk \
  -monitor stdio
```

---

## What You Should See in the QEMU Window

### Boot Sequence (First Boot)

1. **GRUB Bootloader** (10-15 seconds)
   - Menu showing "GNU/Hurd" options
   - Default entry should boot automatically
   - You can press Enter to boot immediately

2. **GNU Mach Kernel Messages** (30-60 seconds)
   ```
   GNU Mach 1.8
   ...
   Probing devices...
   ```

3. **Hurd Bootstrap** (1-3 minutes)
   ```
   Starting the Hurd ...
   Hurd bootstrap: ... translator...
   ```

4. **System Initialization** (2-5 minutes on first boot)
   ```
   Starting services...
   eth0: link up
   ```

5. **Login Prompt**
   ```
   Debian GNU/Hurd ...

   localhost login: _
   ```

### If Boot Appears Stuck

- Wait at least 5 minutes (first boot is slow)
- Look for any error messages
- Check if there's disk activity (QCOW2 initialization)

---

## Manual Login and Setup Process

### Step 1: Login as Root

At the login prompt:

```
localhost login: root
Password: [press Enter - try empty password first]
```

**Alternative passwords to try:**
- Empty (just press Enter)
- `root`
- `toor`
- Check Debian Hurd docs

### Step 2: Check Network

```bash
# Check network interfaces
ifconfig

# Expected output:
# eth0: inet 10.0.2.15 ...

# If no IP, get one via DHCP
dhclient eth0

# Test connectivity
ping -c 3 8.8.8.8
```

### Step 3: Check SSH Server

```bash
# Check if SSH is running
ps aux | grep sshd

# If not running, start it
/etc/init.d/ssh start

# Enable on boot
update-rc.d ssh enable

# Verify SSH is listening
netstat -tulpn | grep :22
```

### Step 4: Test SSH from Host

**Open a NEW terminal on your host** (keep QEMU window visible):

```bash
# Try SSH connection
ssh -p 2222 root@localhost

# If it connects, SUCCESS!
# If it asks for password, try empty or "root"
```

### Step 5: Set Root Password

Inside Hurd (via QEMU window or SSH):

```bash
# Set root password to "root"
passwd root
# Enter new password: root
# Retype: root

# Force change on first SSH login
chage -d 0 root
```

### Step 6: Create agents User

```bash
# Create user
useradd -m -s /bin/bash -G sudo agents

# Set password
passwd agents
# Password: agents
# Retype: agents

# Force change on first login
chage -d 0 agents

# Configure sudo NOPASSWD
echo 'agents ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/agents
chmod 0440 /etc/sudoers.d/agents
```

### Step 7: Update Package Lists

```bash
# Update apt
apt-get update

# If this fails with network errors, check:
ping -c 3 deb.debian.org
# If DNS fails, add nameserver:
echo "nameserver 8.8.8.8" >> /etc/resolv.conf
```

### Step 8: Install Development Tools

Run these commands **one by one** and note any errors:

```bash
# Core tools
apt-get install -y gcc g++ make cmake autoconf automake libtool pkg-config flex bison texinfo

# Compilers
apt-get install -y clang llvm lld binutils-dev libelf-dev

# MACH-SPECIFIC (CRITICAL!)
apt-get install -y gnumach-dev hurd-dev mig hurd-doc

# Debug tools
apt-get install -y gdb strace ltrace sysstat

# Build systems
apt-get install -y meson ninja-build

# VCS
apt-get install -y git

# Editors
apt-get install -y vim emacs-nox

# Docs
apt-get install -y doxygen graphviz

# Utilities
apt-get install -y tmux screen curl wget netcat-openbsd
```

**Document which commands succeed and which fail!**

### Step 9: Verify Mach Tools

```bash
# Check MIG (Mach Interface Generator)
which mig
mig --version || mig -h

# Check Mach headers
ls -la /usr/include/mach/

# Check Hurd headers
ls -la /usr/include/hurd/

# Check installed packages
dpkg -l | grep -E "gnumach|hurd-dev|mig"
```

### Step 10: Configure Shell Environment

```bash
# Add to /root/.bashrc
cat >> /root/.bashrc << 'EOF'

# GNU/Hurd Development Environment
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"
export MACH_INCLUDE="/usr/include/mach"
export HURD_INCLUDE="/usr/include/hurd"
export PKG_CONFIG_PATH="/usr/lib/pkgconfig"

# Mach aliases
alias mig='mig'
alias mach-info='cat /proc/mach/version'

# Dev aliases
alias ll='ls -lah'
alias la='ls -A'

# Prompt
export PS1='\[\033[01;32m\]\u@hurd\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
EOF

# Source it
source /root/.bashrc

# Copy to agents
cp /root/.bashrc /home/agents/.bashrc
chown agents:agents /home/agents/.bashrc
```

---

## Testing Checklist

### Basic System

- [ ] Hurd boots to login prompt
- [ ] Can login as root
- [ ] Network interface has IP (10.0.2.15)
- [ ] Can ping 8.8.8.8
- [ ] DNS resolution works (ping google.com)

### SSH

- [ ] SSH server is running (`ps aux | grep sshd`)
- [ ] SSH listening on port 22 (`netstat -tulpn | grep :22`)
- [ ] Can connect from host: `ssh -p 2222 root@localhost`
- [ ] Root password is set correctly

### User Accounts

- [ ] agents user created
- [ ] agents can sudo without password
- [ ] Both passwords force change on first login

### Package Management

- [ ] `apt-get update` succeeds
- [ ] Can install packages
- [ ] No missing dependencies

### Development Tools

- [ ] GCC installed: `gcc --version`
- [ ] Make installed: `make --version`
- [ ] MIG installed: `which mig`
- [ ] GDB installed: `gdb --version`
- [ ] Git installed: `git --version`

### **Mach-Specific (MOST IMPORTANT!)**

- [ ] gnumach-dev package installed
- [ ] hurd-dev package installed
- [ ] mig command available
- [ ] /usr/include/mach/ directory exists with headers
- [ ] /usr/include/hurd/ directory exists with headers

### Shell Environment

- [ ] .bashrc configured
- [ ] Mach environment variables set
- [ ] Prompt customized

---

## Commands to Document

As you go through setup, **copy and save**:

1. **Exact package installation commands that work**
2. **Any errors encountered and fixes**
3. **Default root password (if not empty)**
4. **Time taken for each step**
5. **Any additional configuration needed**

Create a file: `LOCAL-TESTING-NOTES.txt` with your findings.

---

## When Setup is Complete

### Create Clean Snapshot

```bash
# In QEMU monitor (type in terminal where QEMU is running):
savevm fully-configured

# Or shutdown cleanly first:
# In Hurd:
shutdown -h now

# Then in QEMU monitor:
quit
```

### Extract Configuration

Document the following for Docker optimization:

1. **Network config:**
   ```bash
   cat /etc/network/interfaces
   ```

2. **SSH config:**
   ```bash
   cat /etc/ssh/sshd_config | grep -v "^#"
   ```

3. **Installed packages:**
   ```bash
   dpkg -l | grep "^ii" > installed-packages.txt
   ```

4. **Services enabled:**
   ```bash
   ls /etc/rc*.d/ | grep ssh
   ```

5. **User configuration:**
   ```bash
   cat /etc/passwd | grep -E "root|agents"
   cat /etc/group | grep -E "root|agents|sudo"
   ```

---

## Next Steps After Local Testing

Once you have a fully working Hurd system locally:

1. **Document all findings** in `LOCAL-TESTING-NOTES.txt`
2. **Create optimized Docker config** based on what works
3. **Possibly pre-configure QCOW2** with SSH enabled and users created
4. **Update entrypoint.sh** with any needed tweaks
5. **Create automated setup script** that actually works
6. **Test final Docker setup** end-to-end

---

## Stopping QEMU

When you're done testing:

```bash
# In the terminal where QEMU is running (monitor):
quit

# Or find the PID:
ps aux | grep qemu-system-i386 | grep -v grep

# Kill it:
kill <PID>
```

---

## Troubleshooting

### QEMU Window Doesn't Appear

```bash
# Check if QEMU is running:
ps aux | grep qemu-system-i386

# Check display:
echo $DISPLAY

# Try different display mode:
# Kill current QEMU and restart with SDL:
qemu-system-i386 ... -display sdl
```

### Boot Hangs

- Wait at least 10 minutes (first boot is VERY slow)
- Check QEMU monitor for errors
- Try VNC instead: `-vnc :1` then connect with `vncviewer localhost:5901`

### Network Not Working

```bash
# Check QEMU network:
# In QEMU monitor:
info network

# Should show: user network with hostfwd tcp::2222-:22

# In Hurd:
dhclient eth0
ifconfig eth0
```

---

**Status:** Local testing in progress
**Goal:** Get complete working configuration to optimize Docker
**Date:** 2025-11-05
