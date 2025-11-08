# Complete Installation Guide for Debian GNU/Hurd Development Environment
**Date:** 2025-11-06
**Image:** debian-hurd-i386-80gb.qcow2

---

## 🎯 Quick Start

The installation scripts are now ready in the `share/` directory and accessible from inside the Hurd VM.

### Run All Installations (Inside Hurd VM)

```bash
# 1. Mount shared filesystem
mount -t 9p -o trans=virtio scripts /mnt/host

# 2. Go to scripts
cd /mnt/host

# 3. Run master installer
bash run-all-installations.sh
```

**OR run individually:**

```bash
# Essential tools first
bash install-essentials-hurd.sh

# Then Node.js
bash install-nodejs-hurd.sh

# Finally Claude Code
bash install-claude-code-hurd.sh
```

---

## 📦 What Gets Installed

### Phase 1: Essential Tools (`install-essentials-hurd.sh`)

**SSH Server:**
- openssh-server
- random-egd (entropy generator for Hurd)
- Configured for root login on port 22
- Auto-starts on boot

**Network Tools:**
- curl, wget (HTTP clients)
- net-tools (ifconfig, netstat, etc.)
- dnsutils (dig, nslookup)
- telnet, netcat-openbsd
- iputils-ping, traceroute
- ca-certificates

**Web Browsers:**
- lynx (text browser, primary)
- w3m (text browser, alternative)
- links, elinks (text browsers)
- firefox-esr (GUI browser, if available)

**Development Tools:**
- build-essential (gcc, g++, make)
- git (version control)
- vim, emacs-nox (editors)
- python3, python3-pip
- cmake, autoconf, automake
- libtool, pkg-config

**Custom Aliases Added:**
```bash
update          # apt-get update && apt-get upgrade
install         # apt-get install
search          # apt-cache search
web             # lynx (quick web browser)
myip            # curl -s ifconfig.me
ports           # ss -tulanp
pingtest        # ping -c 3 8.8.8.8
dnstest         # nslookup google.com
sshrestart      # service ssh restart
```

### Phase 2: Node.js (`install-nodejs-hurd.sh`)

**Installation Methods (in order of attempt):**

1. **Debian Repository** (Most Likely to Work)
   - Uses apt-get to install nodejs and npm
   - Version: Likely Node.js 12-18 (older but stable)
   - Advantage: Tested on Debian, should work on Hurd

2. **Build from Source** (Fallback)
   - Downloads Node.js v16.20.2 LTS source
   - Compiles with i386-specific flags
   - Takes 30-60 minutes
   - May fail due to Hurd incompatibilities

**NPM Global Configuration:**
```bash
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'
export PATH=$HOME/.npm-global/bin:$PATH
```

### Phase 3: Claude Code CLI (`install-claude-code-hurd.sh`)

**Installation Methods (in order of attempt):**

1. **Native Installer**
   ```bash
   curl -fsSL https://claude.ai/install.sh | bash
   ```
   - Requires glibc, likely amd64
   - **Will likely fail on Hurd**

2. **NPM Installation**
   ```bash
   npm install -g @anthropic-ai/claude-code
   ```
   - Requires Node.js 18+
   - Platform-specific binaries may not work on Hurd

**Expected Outcome:**
- ⚠️ Claude Code likely won't work on Hurd i386
- Reason: No official Hurd support, requires platform binaries
- Alternative: Use Claude Code from host machine

---

## 🚀 Step-by-Step Execution

### From Host Machine

```bash
# 1. Ensure Hurd VM is running
docker-compose ps

# 2. Verify share directory has scripts
ls -lh share/

# Expected output:
#   install-essentials-hurd.sh
#   install-nodejs-hurd.sh
#   install-claude-code-hurd.sh
#   run-all-installations.sh
```

### Inside Hurd VM (Via VNC or Serial Console)

```bash
# Login: root / root

# 1. Mount shared filesystem
mount -t 9p -o trans=virtio scripts /mnt/host

# 2. Verify scripts are accessible
ls -lh /mnt/host/

# 3. Run installations
cd /mnt/host
bash run-all-installations.sh

# OR run each phase individually:

# Phase 1: Essentials (required)
bash install-essentials-hurd.sh

# Phase 2: Node.js (optional, for Claude Code)
bash install-nodejs-hurd.sh

# Phase 3: Claude Code (optional, likely to fail)
bash install-claude-code-hurd.sh
```

---

## ✅ Verification

### Test SSH Connection (From Host)

```bash
# After Phase 1 completes
ssh -p 2222 root@localhost

# If connection refused, check inside VM:
service ssh status
service ssh start
```

### Test Network Tools (Inside Hurd)

```bash
# Ping test
ping -c 3 8.8.8.8

# DNS test
nslookup google.com

# HTTP test
curl https://www.gnu.org

# Web browsing
lynx https://www.debian.org/ports/hurd/
```

### Test Node.js (Inside Hurd)

```bash
# Check versions
node --version
npm --version

# Test npm
npm list -g --depth=0

# Test Node.js
node -e "console.log('Hello from Node.js on Hurd!')"
```

### Test Claude Code (Inside Hurd)

```bash
# Check installation
which claude
claude --version

# Authenticate
claude auth login

# Test
claude
```

---

## 🐛 Troubleshooting

### SSH Not Working

**Problem:** Cannot SSH from host

**Solutions:**
```bash
# Inside VM, check SSH status
service ssh status

# Restart SSH
service ssh restart

# Check if listening on port 22
ss -tlnp | grep :22

# Check logs
tail -f /var/log/auth.log
```

### Network Not Working

**Problem:** No internet connectivity

**Solutions:**
```bash
# Check network interface
ip addr show

# Check routing
ip route

# Test DNS
nslookup 8.8.8.8

# Check /etc/resolv.conf
cat /etc/resolv.conf
```

### Node.js Installation Fails

**Problem:** apt-get cannot find nodejs

**Solutions:**
```bash
# Update sources
apt-get update

# Search for nodejs
apt-cache search nodejs

# Try from testing repo
echo "deb http://deb.debian.org/debian testing main" >> /etc/apt/sources.list
apt-get update
apt-get install nodejs npm

# Or build from source (slow)
bash install-nodejs-hurd.sh
# Select option 2 (build from source)
```

### Claude Code Installation Fails

**Expected Behavior:**
- Claude Code is not officially supported on Hurd
- Installation will likely fail

**Alternatives:**
```bash
# Use Claude Code from host (recommended)
exit  # Exit Hurd VM
claude  # Run on host

# OR use Claude API directly
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2025-09-01" \
  -d '{
    "model": "claude-3-5-sonnet-20251022",
    "max_tokens": 1024,
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

---

## 📝 Post-Installation Configuration

### Set Up User Account (Optional)

```bash
# Create non-root user
adduser developer
usermod -aG sudo developer

# Switch to new user
su - developer
```

### Configure Git

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

### Set Up SSH Keys

```bash
# Generate SSH key
ssh-keygen -t ed25519 -C "hurd@example.com"

# Copy public key to clipboard (from host)
ssh -p 2222 root@localhost 'cat ~/.ssh/id_ed25519.pub'

# Add to GitHub: https://github.com/settings/keys
```

---

## 🎓 CI/CD Integration

See `CI-CD-GUIDE-HURD.md` for complete CI/CD setup instructions including:
- GitHub Actions workflows
- Self-hosted runners
- Docker-based CI
- Package building and release automation

---

## 📚 Documentation Index

- **HURD-SYSTEM-AUDIT.md** - System configuration audit
- **CUSTOM-HURD-FEATURES.md** - Custom features and configurations
- **QUICKSTART.md** - Quick reference guide
- **CI-CD-GUIDE-HURD.md** - CI/CD setup and best practices
- **THIS FILE** - Complete installation guide

---

## 🎯 Summary

**Created Scripts:**
1. ✅ `install-essentials-hurd.sh` - SSH, network, browsers, dev tools
2. ✅ `install-nodejs-hurd.sh` - Node.js installation (multiple methods)
3. ✅ `install-claude-code-hurd.sh` - Claude Code CLI (likely won't work)
4. ✅ `run-all-installations.sh` - Master installer

**Location:** `share/` directory (accessible from VM at `/mnt/host`)

**Expected Results:**
- ✅ SSH server: Will work
- ✅ Network tools: Will work
- ✅ Browsers: Will work (text browsers definitely, firefox maybe)
- ⚠️ Node.js: May work (from Debian repos) or require source build
- ❌ Claude Code: Likely won't work (Hurd not supported)

**Recommended Workflow:**
1. Run essentials installer (Phase 1) - **Always works**
2. Try Node.js from Debian repos (Phase 2) - **Usually works**
3. Skip Claude Code installer (Phase 3) - **Use from host instead**

---

## 🚦 Next Steps

1. ✅ **Mount /mnt/host:** `mount -t 9p -o trans=virtio scripts /mnt/host`
2. ✅ **Run installer:** `cd /mnt/host && bash run-all-installations.sh`
3. ✅ **Test SSH:** `ssh -p 2222 root@localhost` (from host)
4. ✅ **Browse web:** `lynx https://www.gnu.org`
5. ⬜ **Set up CI/CD:** See CI-CD-GUIDE-HURD.md
6. ⬜ **Start developing!**

---

**Generated:** 2025-11-06
**Repository:** gnu-hurd-docker
**Maintainer:** Oaich
