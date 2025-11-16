# GNU/Hurd Docker - Pre-Provisioned Image Creation

**Last Updated**: 2025-11-07
**Consolidated From**:
- CI-CD-PROVISIONED-IMAGE.md (provisioning workflow)
- scripts/bringup-and-provision.sh (orchestration)
- scripts/install-*.sh (installation scripts)

**Purpose**: Complete guide for creating and using pre-provisioned GNU/Hurd images for fast CI/CD

**Scope**: Debian GNU/Hurd x86_64 only (i386 deprecated 2025-11-07)

---

## Overview

Pre-provisioned images dramatically reduce CI/CD run times by pre-installing SSH, development tools, and dependencies.

**Performance Comparison**:

| Approach | Boot Time | Provision Time | Total Time | Success Rate |
|----------|-----------|----------------|------------|--------------|
| Fresh Image + Serial Automation | 5-10 min | 10-20 min | 15-30 min | 60-80% |
| Pre-Provisioned Image | 5-10 min | 0 min | 5-10 min | 95%+ |

**Speedup**: 3-6x faster, 15-35% higher success rate

---

## Provisioning Architecture

### Three-Layer Approach

```
┌─────────────────────────────────────────────────────┐
│ Layer 1: Base Image (Debian GNU/Hurd x86_64)       │
│   - Fresh Debian Hurd 2025 installation             │
│   - Minimal package set                             │
│   - No SSH server (serial console only)             │
│   - Size: ~4 GB                                     │
└─────────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────┐
│ Layer 2: Provisioned Image (SSH + Essentials)      │
│   - SSH server installed and enabled               │
│   - Network tools (curl, wget, git)                │
│   - Development tools (gcc, make, cmake)            │
│   - Text browsers (lynx, w3m)                       │
│   - Root password set                               │
│   - Size: ~5-6 GB                                   │
└─────────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────┐
│ Layer 3: CI-Ready Image (Optional: CI Tools)       │
│   - GitHub CLI (gh)                                 │
│   - Docker client (for DinD workflows)              │
│   - Node.js (for npm-based tools)                   │
│   - Custom project dependencies                     │
│   - Size: ~7-8 GB                                   │
└─────────────────────────────────────────────────────┘
```

### Installation Scripts

**Location**: `scripts/install-*.sh`

1. **install-ssh-hurd.sh** - SSH server via serial console
2. **install-essentials-hurd.sh** - Core development environment
3. **install-nodejs-hurd.sh** - Node.js runtime (optional)
4. **install-claude-code-hurd.sh** - Claude Code CLI (experimental)

---

## Quick Start: Create Pre-Provisioned Image

### Method 1: Automated (Recommended)

**Prerequisites**:
- Docker and docker-compose installed
- KVM access (Linux) or TCG fallback (macOS/Windows)
- 20 GB free disk space
- 30-60 minutes time (KVM) or 2-4 hours (TCG)

**Steps**:

```bash
# 1. Clone repository
git clone https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker.git
cd gnu-hurd-docker

# 2. Download base x86_64 image
./scripts/setup-hurd-amd64.sh
# Downloads: debian-hurd-amd64-20251105.img.tar.xz (~355 MB)
# Extracts to: debian-hurd-amd64-80gb.qcow2 (~4 GB)

# 3. Build provisioning environment
docker-compose build

# 4. Start VM and wait for boot (5-10 minutes)
docker-compose up -d
sleep 600  # Adjust based on your system

# 5. Install SSH server via serial console
export ROOT_PASS=root
export AGENTS_PASS=agents
./scripts/install-ssh-hurd.sh
# Uses expect to automate serial console interaction
# Installs: openssh-server, random-egd
# Configures: password auth, root login
# Time: 5-10 minutes

# 6. Install essentials via SSH
ssh -p 2222 root@localhost "bash -s" < ./share/install-essentials-hurd.sh
# Installs: network tools, browsers, gcc, git, vim
# Time: 10-20 minutes (depends on network speed)

# 7. Shutdown gracefully
ssh -p 2222 root@localhost "shutdown -h now"
sleep 30
docker-compose down

# 8. Create provisioned image
cp debian-hurd-amd64-80gb.qcow2 debian-hurd-amd64-provisioned.qcow2

# 9. Compress for distribution
tar czf debian-hurd-amd64-provisioned.qcow2.tar.gz \
    debian-hurd-amd64-provisioned.qcow2

# 10. Generate checksum
sha256sum debian-hurd-amd64-provisioned.qcow2.tar.gz | \
    tee debian-hurd-amd64-provisioned.qcow2.tar.gz.sha256
```

**Result**: Pre-provisioned image ready for CI/CD or local development.

---

## Installation Scripts Reference

### 1. install-ssh-hurd.sh

**Purpose**: Automated SSH server installation via serial console

**Method**: Uses `expect` to automate telnet interaction with QEMU serial port

**Environment Variables**:
```bash
SERIAL_PORT=${SERIAL_PORT:-5555}    # Serial console port
SERIAL_HOST=${SERIAL_HOST:-localhost}
```

**What It Does**:
1. Connects to telnet serial console (port 5555)
2. Sends wake-up characters to detect login prompt
3. Logs in as root (default: no password)
4. Runs `apt-get update`
5. Installs `openssh-server` and `random-egd` (entropy daemon)
6. Starts SSH daemon: `/etc/init.d/ssh start`
7. Enables SSH on boot: `update-rc.d ssh defaults`
8. Configures sshd for password authentication:
   - `PermitRootLogin yes`
   - `PasswordAuthentication yes`
   - `UsePAM yes`
9. Sets root password: `echo 'root:root' | chpasswd`
10. Restarts SSH: `/etc/init.d/ssh restart`

**Expected Output**:
```
========================================================================
  SSH Installation Complete!
========================================================================

SSH server is now running. Test with:
  ssh -p 2222 root@localhost

Default credentials:
  Username: root
  Password: root

SECURITY: Change the password after first login!
```

**Timeout**: 600 seconds (10 minutes) for package installation

**Error Handling**:
- If login prompt not detected: timeout after 10 minutes
- If apt-get times out: manual intervention required
- If SSH not listening: check logs with `docker-compose logs`

**Usage**:
```bash
# Standalone usage
export SERIAL_PORT=5555
./scripts/install-ssh-hurd.sh

# Or via orchestration script
ROOT_PASS=root AGENTS_PASS=agents ./scripts/bringup-and-provision.sh
```

---

### 2. install-essentials-hurd.sh

**Purpose**: Install core development environment and networking tools

**Must Run**: As root inside GNU/Hurd guest

**7 Phases**:

#### Phase 1: Update Package Lists
```bash
apt-get update
```

#### Phase 2: SSH Server
- `openssh-server` - SSH daemon
- `random-egd` - Entropy generator for Hurd
- Configures: `/etc/ssh/sshd_config` (PermitRootLogin yes)
- Sets root password if not set

#### Phase 3: Network Tools
Packages installed:
```bash
curl wget net-tools dnsutils telnet netcat-openbsd
iputils-ping traceroute iproute2 ca-certificates
```

#### Phase 4: Web Browsers
```bash
# Text-based (always installed)
lynx w3m links elinks

# GUI (optional, if X11 available)
firefox-esr  # May not be in repos
```

#### Phase 5: Development Essentials
```bash
build-essential git vim emacs-nox python3 python3-pip
make cmake autoconf automake libtool pkg-config
```

#### Phase 6: Verification
Checks:
- SSH server running: `systemctl is-active ssh`
- SSH listening on port 22: `ss -tlnp | grep :22`
- Commands available: `curl`, `wget`, `git`, `vim`
- Browsers installed: `lynx`, `w3m`, `links`

#### Phase 7: Post-Install Configuration

**Adds useful aliases to /root/.bashrc**:
```bash
alias update='apt-get update && apt-get upgrade'
alias install='apt-get install'
alias search='apt-cache search'
alias web='lynx'
alias myip='curl -s ifconfig.me'
alias ports='ss -tulanp'
alias sshrestart='service ssh restart'
alias pingtest='ping -c 3 8.8.8.8'
alias dnstest='nslookup google.com'
```

**Creates login banner (/etc/motd)**:
```
╔══════════════════════════════════════════════════════════════════╗
║                 Debian GNU/Hurd 2025 Development VM              ║
╚══════════════════════════════════════════════════════════════════╝

Welcome to Debian GNU/Hurd! This is the GNU Mach microkernel.

Quick Commands:
  - Update packages:     apt-get update && apt-get upgrade
  - Install package:     apt-get install <package>
  - Search packages:     apt-cache search <term>
  - Web browser:         lynx https://www.gnu.org
  - System info:         uname -a && free -h

Installed Tools:
  ✓ SSH Server (openssh-server)
  ✓ Network tools (curl, wget, ping, telnet)
  ✓ Web browsers (lynx, w3m, links)
  ✓ Development tools (gcc, git, vim, python3)
```

**Time**: 10-20 minutes (network-dependent)

**Disk Space**: ~1-2 GB additional

**Usage**:
```bash
# Inside guest (after SSH enabled)
ssh -p 2222 root@localhost
bash /mnt/host/install-essentials-hurd.sh

# Or remote execution
ssh -p 2222 root@localhost "bash -s" < ./share/install-essentials-hurd.sh
```

---

### 3. install-nodejs-hurd.sh

**Purpose**: Install Node.js runtime (for npm-based tools)

**Status**: Experimental (Node.js support on Hurd varies)

**Methods** (tried in order):

#### Method 1: Debian Repository (Recommended)
```bash
apt-get update
apt-get install -y nodejs npm
```

**Pros**:
- Most reliable on Hurd
- Works out of the box

**Cons**:
- Older version (Node 12-18 typical)
- May not support latest npm packages

**Configuration**:
```bash
# Set npm global directory (avoid sudo for npm install -g)
mkdir -p /root/.npm-global
npm config set prefix '/root/.npm-global'
echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> /root/.bashrc
```

#### Method 2: Build from Source (Advanced)
```bash
# Install build dependencies
apt-get install -y build-essential python3 curl git libssl-dev

# Download Node.js source (x86_64-compatible version)
NODE_VERSION="v18.20.0"  # Update for x86_64
curl -fsSL "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION.tar.gz" | tar xz
cd node-$NODE_VERSION

# Configure for x86_64
./configure \
    --prefix=/usr/local \
    --without-intl \
    --dest-cpu=x64  # x64 for x86_64 (was ia32 for i386)

# Build (30-60 minutes)
make -j$(nproc)
make install
```

**Pros**:
- Latest Node.js version
- Full control over build flags

**Cons**:
- Time-consuming (30-60 minutes)
- May fail on Hurd due to platform quirks
- Requires significant disk space (~5 GB)

**Note**: Original script targets i386 (--dest-cpu=ia32); use x64 for x86_64.

**Usage**:
```bash
# Inside guest
bash /mnt/host/install-nodejs-hurd.sh
# Follow interactive prompts

# Non-interactive (Debian repos only)
apt-get install -y nodejs npm
```

---

### 4. install-claude-code-hurd.sh

**Purpose**: Install Claude Code CLI (experimental)

**Status**: May not work on GNU/Hurd (platform compatibility issues)

**Requirements**:
- Node.js 18+ (install with install-nodejs-hurd.sh first)
- npm configured with global prefix

**Methods**:

#### Method 1: Native Installer
```bash
curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh
chmod +x /tmp/claude-install.sh
bash /tmp/claude-install.sh
```

**Issue**: Native installer targets glibc + amd64/arm64, not Hurd.

#### Method 2: NPM Installation (Fallback)
```bash
# Configure npm
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'
export PATH=$HOME/.npm-global/bin:$PATH

# Install Claude Code
npm install -g @anthropic-ai/claude-code

# Verify
claude --version
```

**Known Issues**:
- Claude Code requires platform-specific binaries (likely incompatible with Hurd)
- Best used from host machine, not inside VM

**Alternatives**:
1. Use Claude Code from host (not inside VM)
2. Use Claude web interface: https://claude.ai
3. Use Anthropic API directly with curl/python

---

## Provisioning Orchestration

### bringup-and-provision.sh

**Purpose**: Orchestrate full provisioning workflow

**Environment Variables**:
```bash
ROOT_PASS=${ROOT_PASS:-root}          # Root password
AGENTS_PASS=${AGENTS_PASS:-agents}    # Non-root user password
SSH_PORT=${SSH_PORT:-2222}             # SSH port (host mapping)
SERIAL_PORT=${SERIAL_PORT:-5555}       # Serial console port
HOST=${HOST:-localhost}                # SSH target host
```

**Workflow**:

```bash
#!/bin/bash
set -e

ROOT_PASS=${ROOT_PASS:-root}
AGENTS_PASS=${AGENTS_PASS:-agents}
SSH_PORT=2222
SERIAL_PORT=${SERIAL_PORT:-5555}
HOST=localhost

echo "Starting provisioning with credentials:"
echo "  Root password: $ROOT_PASS"
echo "  Agents password: $AGENTS_PASS"

# Step 1: Install SSH via serial
./scripts/install-ssh-hurd.sh

# Step 2: Wait for SSH to be fully ready
sleep 30

# Step 3: Create sudo user 'agents'
sshpass -p "$ROOT_PASS" ssh -p "$SSH_PORT" \
    -o StrictHostKeyChecking=no \
    root@"$HOST" bash -s <<EOSSH
useradd -m -s /bin/bash -G sudo agents
printf 'agents:%s\n' "$AGENTS_PASS" | chpasswd
echo "User 'agents' created with sudo access"
EOSSH

# Step 4: Install essentials
sshpass -p "$ROOT_PASS" ssh -p "$SSH_PORT" root@"$HOST" \
    "bash -s" < ./share/install-essentials-hurd.sh

echo "Provisioning complete!"
echo "  SSH: ssh -p $SSH_PORT root@$HOST (password: $ROOT_PASS)"
echo "  User: ssh -p $SSH_PORT agents@$HOST (password: $AGENTS_PASS)"
```

**Usage**:
```bash
# Use default passwords (root/agents)
./scripts/bringup-and-provision.sh

# Custom passwords
ROOT_PASS=mysecretroot AGENTS_PASS=mysecretagents \
    ./scripts/bringup-and-provision.sh
```

**Security Note**: Change default passwords for production use.

---

## CI/CD Integration

### GitHub Actions Workflow

**Use pre-provisioned image in CI**:

```yaml
name: Test with Pre-Provisioned Hurd

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

env:
  PROVISIONED_IMAGE_URL: "https://github.com/YOUR_ORG/gnu-hurd-docker/releases/download/v1.0.0-provisioned/debian-hurd-amd64-provisioned.qcow2.tar.gz"
  PROVISIONED_IMAGE_SHA256: "your_sha256_checksum_here"

jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 30

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Download provisioned image
        run: |
          curl -L "$PROVISIONED_IMAGE_URL" -o provisioned.tar.gz
          echo "$PROVISIONED_IMAGE_SHA256  provisioned.tar.gz" | sha256sum -c
          tar xzf provisioned.tar.gz

      - name: Rename image to expected path
        run: |
          mv debian-hurd-amd64-provisioned.qcow2 debian-hurd-amd64-80gb.qcow2

      - name: Start Hurd VM
        run: |
          docker-compose build
          docker-compose up -d

      - name: Wait for SSH (fast with pre-provisioned image)
        run: |
          for i in {1..60}; do
            if ssh -o StrictHostKeyChecking=no -p 2222 root@localhost true 2>/dev/null; then
              echo "SSH ready in $i attempts"
              exit 0
            fi
            sleep 5
          done
          echo "SSH timeout"
          exit 1

      - name: Run tests
        run: |
          ssh -o StrictHostKeyChecking=no -p 2222 root@localhost << 'EOF'
          uname -a
          gcc --version
          git --version
          curl --version
          EOF

      - name: Cleanup
        if: always()
        run: docker-compose down
```

**Performance**: Boot + SSH ready in 5-10 minutes (vs 15-30 minutes with fresh image).

---

## Creating Layered Images

### Layer 1: Base Image (Provided by Debian)

```bash
# Download official Debian GNU/Hurd x86_64 image
wget https://cdimage.debian.org/cdimage/ports/latest/hurd-amd64/debian-hurd-amd64-20251105.img.tar.xz

# Extract
tar xJf debian-hurd-amd64-20251105.img.tar.xz
# Creates: debian-hurd-amd64-20251105.img (~4 GB)

# Convert to QCOW2 (if raw)
qemu-img convert -f raw -O qcow2 \
    debian-hurd-amd64-20251105.img \
    debian-hurd-amd64-80gb.qcow2

# Or resize existing qcow2
qemu-img resize debian-hurd-amd64-80gb.qcow2 +76G
```

### Layer 2: Provisioned Image (SSH + Essentials)

```bash
# Start VM
docker-compose up -d
sleep 600  # Wait for boot

# Install SSH
./scripts/install-ssh-hurd.sh

# Install essentials
ssh -p 2222 root@localhost "bash -s" < ./share/install-essentials-hurd.sh

# Shutdown
ssh -p 2222 root@localhost "shutdown -h now"
sleep 30
docker-compose down

# Create provisioned snapshot
cp debian-hurd-amd64-80gb.qcow2 debian-hurd-amd64-provisioned.qcow2
```

### Layer 3: CI-Ready Image (Project Dependencies)

```bash
# Start from provisioned image
QEMU_DRIVE=debian-hurd-amd64-provisioned.qcow2 docker-compose up -d
sleep 300

# Install project-specific dependencies
ssh -p 2222 root@localhost << 'EOF'
apt-get update
apt-get install -y postgresql-client redis-tools

# Install Node.js 18+ (if needed)
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

# Install project npm packages globally
npm install -g prettier eslint jest
EOF

# Shutdown
ssh -p 2222 root@localhost "shutdown -h now"
docker-compose down

# Create CI-ready snapshot
cp debian-hurd-amd64-provisioned.qcow2 debian-hurd-amd64-ci-ready.qcow2
```

---

## Image Publishing

### Compress and Checksum

```bash
# Compress (QCOW2 already has internal compression, but tar.gz reduces size further)
tar czf debian-hurd-amd64-provisioned.qcow2.tar.gz \
    debian-hurd-amd64-provisioned.qcow2

# Generate checksum
sha256sum debian-hurd-amd64-provisioned.qcow2.tar.gz | \
    tee debian-hurd-amd64-provisioned.qcow2.tar.gz.sha256
```

### Upload to GitHub Releases

```bash
# Create release
gh release create v1.0.0-provisioned \
    --title "Pre-Provisioned Debian GNU/Hurd x86_64 Image" \
    --notes "SSH enabled, development tools installed, ready for CI/CD" \
    debian-hurd-amd64-provisioned.qcow2.tar.gz \
    debian-hurd-amd64-provisioned.qcow2.tar.gz.sha256

# Verify upload
gh release view v1.0.0-provisioned
```

### Alternative: Self-Hosted Storage

```bash
# Upload to S3
aws s3 cp debian-hurd-amd64-provisioned.qcow2.tar.gz \
    s3://my-bucket/hurd-images/

# Upload to HTTP server
scp debian-hurd-amd64-provisioned.qcow2.tar.gz \
    user@myserver.com:/var/www/html/downloads/

# Generate public URL
echo "https://myserver.com/downloads/debian-hurd-amd64-provisioned.qcow2.tar.gz"
```

---

## Verification and Testing

### Test Provisioned Image Locally

```bash
# 1. Download and extract
curl -L "$PROVISIONED_IMAGE_URL" -o provisioned.tar.gz
echo "$PROVISIONED_IMAGE_SHA256  provisioned.tar.gz" | sha256sum -c
tar xzf provisioned.tar.gz

# 2. Rename to expected path
mv debian-hurd-amd64-provisioned.qcow2 debian-hurd-amd64-80gb.qcow2

# 3. Start VM
docker-compose up -d

# 4. Wait and test SSH
sleep 300
ssh -p 2222 root@localhost

# Inside guest:
uname -a
# Expected: GNU/Hurd ... x86_64

which ssh curl wget git gcc vim
# All should return paths

lynx --version
# Text browser available

exit

# 5. Cleanup
docker-compose down
```

### Verification Checklist

**Boot**:
- [ ] VM boots successfully
- [ ] SSH accessible within 5-10 minutes

**SSH**:
- [ ] Root login works (password: root)
- [ ] SSH listening on port 22 inside guest

**Network**:
- [ ] `ping 8.8.8.8` works
- [ ] `curl https://debian.org` works
- [ ] DNS resolution functional

**Tools**:
- [ ] gcc, g++, make, cmake installed
- [ ] git, vim, emacs available
- [ ] curl, wget, lynx, w3m installed
- [ ] Python 3 with pip

**System**:
- [ ] Root password set
- [ ] /etc/motd banner displayed on login
- [ ] Aliases in ~/.bashrc functional

---

## Troubleshooting Provisioning

### SSH Installation Fails (Serial Console)

**Symptom**: install-ssh-hurd.sh times out or doesn't detect login prompt

**Causes**:
1. VM hasn't finished booting (too early)
2. Serial console not exposed correctly
3. Login prompt format unexpected

**Fixes**:

```bash
# 1. Verify VM is running
docker-compose ps
# Expected: hurd-x86_64 running

# 2. Check serial console manually
telnet localhost 5555
# Press Enter a few times
# Expected: login prompt appears

# 3. Increase boot wait time
sleep 900  # Wait 15 minutes instead of 10

# 4. Check QEMU logs
docker-compose logs | grep -i "login\|boot"

# 5. Verify serial port in docker-compose.yml
grep "5555:5555" docker-compose.yml
```

### Package Installation Hangs

**Symptom**: apt-get install hangs during install-essentials-hurd.sh

**Causes**:
1. Network connectivity issues
2. Debian mirror slow or unavailable
3. Entropy exhaustion (random-egd not running)

**Fixes**:

```bash
# Inside guest:
# 1. Test network
ping -c 3 8.8.8.8
ping -c 3 deb.debian.org

# 2. Change Debian mirror
echo "deb http://ftp.us.debian.org/debian sid main" > /etc/apt/sources.list.d/us-mirror.list
apt-get update

# 3. Check entropy
cat /proc/sys/kernel/random/entropy_avail
# Should be > 100

# If low:
apt-get install -y random-egd haveged
service random-egd restart
```

### SSH Connects But Commands Hang

**Symptom**: SSH login succeeds but commands don't execute

**Causes**:
1. PTY allocation issues (Hurd-specific)
2. Shell not properly initialized

**Fixes**:

```bash
# Force PTY allocation
ssh -t -p 2222 root@localhost bash

# Or disable PTY
ssh -T -p 2222 root@localhost uname -a

# Check shell
ssh -p 2222 root@localhost "echo \$SHELL"
# Expected: /bin/bash
```

### Image Too Large After Provisioning

**Symptom**: Image grows beyond expected size

**Causes**:
1. QCOW2 not compressing efficiently
2. Package cache not cleaned
3. Logs accumulating

**Fixes**:

```bash
# Inside guest before shutdown:
apt-get clean
apt-get autoclean
rm -rf /var/cache/apt/archives/*.deb
rm -rf /tmp/*
journalctl --vacuum-size=50M

# On host after shutdown:
qemu-img convert -O qcow2 -c \
    debian-hurd-amd64-80gb.qcow2 \
    debian-hurd-amd64-provisioned-compressed.qcow2

# Check size reduction
ls -lh debian-hurd-amd64-*.qcow2
```

---

## Best Practices

### Security

1. **Change Default Passwords**:
   ```bash
   # In provisioning script
   ROOT_PASS=MySecureRootPass123
   AGENTS_PASS=MySecureAgentsPass456
   ```

2. **Disable Root SSH for Production**:
   ```bash
   # Inside guest
   sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
   service ssh restart
   ```

3. **Use SSH Keys Instead of Passwords**:
   ```bash
   # Generate key on host
   ssh-keygen -t ed25519 -f ~/.ssh/hurd_ed25519

   # Copy to guest
   ssh-copy-id -i ~/.ssh/hurd_ed25519.pub -p 2222 root@localhost

   # Disable password auth
   ssh -p 2222 root@localhost \
       "sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && service ssh restart"
   ```

### Performance

1. **Use KVM When Available**:
   ```yaml
   # docker-compose.yml
   devices:
     - /dev/kvm:/dev/kvm:rw
   ```

2. **Allocate Sufficient Resources**:
   ```yaml
   environment:
     QEMU_RAM: 8192  # 8 GB for faster provisioning
     QEMU_SMP: 4     # 4 CPUs
   ```

3. **Pre-Download Packages**:
   ```bash
   # Cache packages locally to speed up repeated provisioning
   apt-get install -y --download-only openssh-server random-egd curl wget git
   ```

### Reproducibility

1. **Pin Package Versions**:
   ```bash
   # Inside guest
   apt-get install -y openssh-server=1:9.2p1-2 random-egd=0.9.0-1
   ```

2. **Document Image Creation Date**:
   ```bash
   # Add to /etc/motd
   echo "Provisioned: $(date -u +%Y-%m-%d)" >> /etc/motd
   ```

3. **Track Installed Packages**:
   ```bash
   # Save package list
   dpkg --get-selections > /root/provisioned-packages.txt
   ```

---

## Reference

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ROOT_PASS` | `root` | Root user password |
| `AGENTS_PASS` | `agents` | Non-root user password |
| `SSH_PORT` | `2222` | SSH port (host side) |
| `SERIAL_PORT` | `5555` | Serial console port |
| `SERIAL_HOST` | `localhost` | Serial console host |
| `HOST` | `localhost` | SSH target host |
| `QEMU_RAM` | `4096` | RAM in MB |
| `QEMU_SMP` | `2` | CPU cores |

### File Paths

| Path | Description |
|------|-------------|
| `/scripts/install-ssh-hurd.sh` | SSH installation via serial |
| `/scripts/install-essentials-hurd.sh` | Core development tools |
| `/scripts/install-nodejs-hurd.sh` | Node.js runtime |
| `/scripts/bringup-and-provision.sh` | Orchestration script |
| `/share/install-*.sh` | Scripts accessible from guest via 9p |
| `/etc/motd` | Login banner (created by install-essentials) |
| `/root/.bashrc` | Shell aliases (created by install-essentials) |

### Useful Commands

```bash
# Check image size
qemu-img info debian-hurd-amd64-80gb.qcow2

# Compress image
qemu-img convert -O qcow2 -c input.qcow2 output.qcow2

# Check SSH status inside guest
systemctl status ssh
ss -tlnp | grep :22

# Test serial console
telnet localhost 5555

# Monitor provisioning
docker-compose logs -f

# Clean up after failed provisioning
docker-compose down
rm -f debian-hurd-amd64-80gb.qcow2
./scripts/setup-hurd-amd64.sh  # Re-download base image
```

---

**Status**: Production Ready (x86_64-only)
**Last Updated**: 2025-11-07
**Architecture**: Pure x86_64
