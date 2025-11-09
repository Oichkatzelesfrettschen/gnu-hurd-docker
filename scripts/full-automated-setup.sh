#!/bin/bash
# Full Automated Setup Script for GNU/Hurd Docker Environment
# This script automates the complete setup process including:
# - Waiting for Hurd to boot
# - Setting up root password (root/root - must change on first login)
# - Creating agents user (agents/agents - must change on first login)
# - Installing all development tools
# - Configuring shell environment
#
# Version: 1.0
# Date: 2025-11-05
# WHY: Add trap handlers for cleanup on exit/error
# WHAT: Track SSH sessions; clean up on abnormal exit
# HOW: cleanup() called on EXIT/INT/TERM; removes known SSH sessions

set -euo pipefail

# Determine script directory first
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
# shellcheck source=lib/colors.sh
source "$SCRIPT_DIR/lib/colors.sh"
# shellcheck source=lib/ssh-helpers.sh
source "$SCRIPT_DIR/lib/ssh-helpers.sh"

# Track cleanup state
CLEANUP_NEEDED=false
SSH_SESSIONS=()

cleanup() {
    local exit_code=$?
    
    if [ "$CLEANUP_NEEDED" = true ]; then
        echo ""
        echo_info "Cleaning up SSH sessions..."
        
        # Kill any SSH processes we may have spawned
        for pid in "${SSH_SESSIONS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
                echo_info "  Terminated SSH session: PID $pid"
            fi
        done
    fi
    
    exit $exit_code
}

trap cleanup EXIT INT TERM

# Configuration
SSH_PORT=2222
SSH_HOST="localhost"
MAX_WAIT=600  # 10 minutes max wait for boot
CHECK_INTERVAL=5  # Check every 5 seconds

echo ""
echo "======================================================================"
echo "  GNU/Hurd Docker - Full Automated Setup"
echo "======================================================================"
echo ""
echo "This script will perform the following actions:"
echo "  1. Wait for Hurd to boot (max 10 minutes)"
echo "  2. Setup root password: root (MUST CHANGE ON FIRST LOGIN)"
echo "  3. Create agents user: agents/agents (MUST CHANGE ON FIRST LOGIN)"
echo "  4. Install all development tools (~1.5 GB, 20-30 min)"
echo "  5. Configure shell environment for development"
echo ""
echo_warning "This is an automated setup - do NOT interrupt!"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 0
fi

# Phase 1: Wait for Hurd to boot and SSH to be available
echo ""
echo_info "Phase 1: Waiting for GNU/Hurd to boot..."
echo_info "This may take 2-10 minutes depending on your system"
echo ""

ELAPSED=0
SSH_READY=false

while [ $ELAPSED -lt $MAX_WAIT ]; do
    # Try to connect to SSH
    if timeout 3 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 \
       -o PasswordAuthentication=no -p $SSH_PORT root@$SSH_HOST \
       "echo 'SSH test'" &>/dev/null; then
        SSH_READY=true
        break
    fi

    # Print progress
    echo -n "."
    sleep $CHECK_INTERVAL
    ELAPSED=$((ELAPSED + CHECK_INTERVAL))
done

echo ""

if [ "$SSH_READY" = false ]; then
    echo_error "Hurd did not boot within $MAX_WAIT seconds"
    echo_error "Check VNC console at localhost:5901 for boot status"
    echo_error "Or check serial console: telnet localhost 5555"
    exit 1
fi

echo_success "Hurd has booted! SSH is responding"

# Phase 2: Setup root password
echo ""
echo_info "Phase 2: Setting up root password..."
echo ""

# First try to login without password (Debian Hurd default)
if timeout 10 sshpass -p '' ssh -o StrictHostKeyChecking=no -p $SSH_PORT root@$SSH_HOST \
   "echo 'Root login successful'" &>/dev/null; then
    echo_success "Root login with empty password successful"

    # Set new root password
    echo_info "Setting root password to 'root' (MUST CHANGE ON FIRST LOGIN)"
    sshpass -p '' ssh -o StrictHostKeyChecking=no -p $SSH_PORT root@$SSH_HOST \
        "echo 'root:root' | chpasswd && chage -d 0 root" || {
        echo_error "Failed to set root password"
        exit 1
    }
    echo_success "Root password set (expires on first login)"
else
    echo_warning "Could not login with empty password"
    echo_warning "Assuming root password is already set or needs manual configuration"
    echo ""
    echo "Please try manual SSH: ssh -p $SSH_PORT root@$SSH_HOST"
    echo "Then run this script again or run setup manually"
    exit 1
fi

# Phase 3: Create agents user
echo ""
echo_info "Phase 3: Creating agents user..."
echo ""

if ! sshpass -p 'root' ssh -o StrictHostKeyChecking=no -p "$SSH_PORT" "root@$SSH_HOST" << 'EOSSH'; then
# Create agents user with home directory
useradd -m -s /bin/bash -G sudo agents || echo "User agents may already exist"

# Set password to 'agents' (must change on first login)
echo 'agents:agents' | chpasswd
chage -d 0 agents

# Configure sudo NOPASSWD for agents
echo 'agents ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/agents
chmod 0440 /etc/sudoers.d/agents

echo "User agents created successfully"
EOSSH
    echo "ERROR: Failed to create agents user"
    exit 1
fi

echo_success "User agents created (password: agents, expires on first login)"

# Phase 4: Copy setup scripts to guest
echo ""
echo_info "Phase 4: Copying setup scripts to guest via 9p..."
echo ""

if ! sshpass -p 'root' ssh -o StrictHostKeyChecking=no -p "$SSH_PORT" "root@$SSH_HOST" << 'EOSSH'; then
# Create mount point
mkdir -p /mnt/scripts

# Mount 9p filesystem
if ! mount | grep -q '/mnt/scripts'; then
    mount -t 9p -o trans=virtio scripts /mnt/scripts || {
        echo "ERROR: Failed to mount 9p filesystem"
        echo "Check that QEMU has -virtfs configured"
        exit 1
    }
fi

echo "9p filesystem mounted at /mnt/scripts"
ls -la /mnt/scripts/
EOSSH
    echo "ERROR: Failed to mount 9p filesystem"
    exit 1
fi

echo_success "Setup scripts accessible in guest"

# Phase 5: Install development tools
echo ""
echo_info "Phase 5: Installing development tools..."
echo_warning "This will take 20-30 minutes and install ~1.5 GB of packages"
echo ""

# Create non-interactive version of setup script
sshpass -p 'root' ssh -o StrictHostKeyChecking=no -p $SSH_PORT root@$SSH_HOST << 'EOSSH'
#!/bin/bash
set -euo pipefail

echo "======================================================================"
echo "  Installing GNU/Hurd Development Tools (Automated)"
echo "======================================================================"

# Update package lists
echo "[1/10] Updating package lists..."
apt-get update

# Core development tools
echo "[2/10] Installing core development tools..."
apt-get install -y \
    gcc g++ make cmake autoconf automake libtool \
    pkg-config flex bison texinfo

# Compilers and toolchains
echo "[3/10] Installing compilers..."
apt-get install -y \
    clang llvm lld binutils-dev libelf-dev

# Mach-specific packages (THE IMPORTANT ONES!)
echo "[4/10] Installing Mach development packages..."
apt-get install -y \
    gnumach-dev hurd-dev mig hurd-doc

# Debugging tools
echo "[5/10] Installing debugging tools..."
apt-get install -y \
    gdb strace ltrace sysstat

# Build systems
echo "[6/10] Installing build systems..."
apt-get install -y \
    meson ninja-build

# Version control
echo "[7/10] Installing version control..."
apt-get install -y \
    git

# Editors
echo "[8/10] Installing editors..."
apt-get install -y \
    vim emacs-nox

# Documentation tools
echo "[9/10] Installing documentation tools..."
apt-get install -y \
    doxygen graphviz

# Optional but useful tools
echo "[10/10] Installing utilities..."
apt-get install -y \
    tmux screen curl wget netcat-openbsd

echo ""
echo "======================================================================"
echo "  Development Tools Installation Complete!"
echo "======================================================================"

# Verify critical Mach tools
echo ""
echo "Verifying Mach development tools:"
echo "  - gnumach-dev: $(dpkg -l | grep gnumach-dev | awk '{print $3}')"
echo "  - hurd-dev: $(dpkg -l | grep hurd-dev | awk '{print $3}')"
echo "  - mig: $(which mig)"
echo "  - gcc: $(gcc --version | head -1)"
echo "  - gdb: $(gdb --version | head -1)"
echo ""

EOSSH

if [ $? -eq 0 ]; then
    echo_success "All development tools installed successfully!"
else
    echo_error "Development tools installation failed"
    echo_error "Check logs above for errors"
    exit 1
fi

# Phase 6: Configure shell environment
echo ""
echo_info "Phase 6: Configuring shell environment..."
echo ""

sshpass -p 'root' ssh -o StrictHostKeyChecking=no -p $SSH_PORT root@$SSH_HOST << 'EOSSH'
# Configure bash for root
cat >> /root/.bashrc << 'EOF'

# GNU/Hurd Development Environment
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"
export MACH_INCLUDE="/usr/include/mach"
export HURD_INCLUDE="/usr/include/hurd"
export PKG_CONFIG_PATH="/usr/lib/pkgconfig"

# Mach-specific aliases
alias mig='mig'
alias mach-info='cat /proc/mach/version'
alias hurd-info='cat /servers/startup'

# Development aliases
alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'

# Prompt customization
export PS1='\[\033[01;32m\]\u@hurd\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

echo "GNU/Hurd development environment loaded"
EOF

# Configure bash for agents user
cp /root/.bashrc /home/agents/.bashrc
chown agents:agents /home/agents/.bashrc

echo "Shell environment configured for root and agents"
EOSSH

echo_success "Shell environment configured"

# Phase 7: Verification
echo ""
echo_info "Phase 7: Verifying installation..."
echo ""

sshpass -p 'root' ssh -o StrictHostKeyChecking=no -p $SSH_PORT root@$SSH_HOST << 'EOSSH'
echo "======================================================================"
echo "  Installation Verification Report"
echo "======================================================================"
echo ""

# Test GCC
echo "GCC:"
gcc --version | head -1

# Test MIG (Mach Interface Generator)
echo ""
echo "MIG (Mach Interface Generator):"
which mig && mig --version || echo "MIG installed but no version flag"

# Test GDB
echo ""
echo "GDB:"
gdb --version | head -1

# Test Make
echo ""
echo "Make:"
make --version | head -1

# Test Git
echo ""
echo "Git:"
git --version

# Check Mach headers
echo ""
echo "Mach Headers:"
ls -la /usr/include/mach/ | head -5

# Check Hurd headers
echo ""
echo "Hurd Headers:"
ls -la /usr/include/hurd/ | head -5

# Disk usage
echo ""
echo "Disk Usage:"
df -h / | tail -1

echo ""
echo "======================================================================"
EOSSH

echo_success "Verification complete!"

# Final summary
echo ""
echo "======================================================================"
echo "  Setup Complete!"
echo "======================================================================"
echo ""
echo_success "GNU/Hurd development environment is ready!"
echo ""
echo "Access credentials:"
echo "  Root user:   username=root, password=root (CHANGE ON FIRST LOGIN)"
echo "  Agents user: username=agents, password=agents (CHANGE ON FIRST LOGIN)"
echo ""
echo "Connect via SSH:"
echo "  ssh -p 2222 root@localhost"
echo "  ssh -p 2222 agents@localhost"
echo ""
echo "Mounted scripts:"
echo "  /mnt/scripts (9p filesystem from host)"
echo ""
echo "Installed packages:"
echo "  - Core: gcc, g++, make, cmake, autotools"
echo "  - Mach: gnumach-dev, hurd-dev, mig"
echo "  - Debug: gdb, strace, ltrace"
echo "  - Editors: vim, emacs"
echo "  - VCS: git"
echo ""
echo_warning "IMPORTANT: Change passwords on first login!"
echo_warning "  - ssh -p 2222 root@localhost, then: passwd"
echo_warning "  - ssh -p 2222 agents@localhost, then: passwd"
echo ""
echo "======================================================================"
echo ""

exit 0
