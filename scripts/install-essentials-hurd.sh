#!/bin/bash
# GNU/Hurd Essential Packages Installer
# Installs: SSH server, networking tools, browsers, and dev essentials
# For use inside Debian GNU/Hurd 2025 VM
# Version: 1.0

set -euo pipefail

# Source libraries
# shellcheck source=lib/colors.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/colors.sh"

echo ""
echo "================================================================"
echo "  Debian GNU/Hurd 2025 - Essential Packages Installer"
echo "================================================================"
echo ""
echo "This script will install:"
echo "  1. SSH Server (openssh-server, random-egd)"
echo "  2. Network Tools (curl, wget, net-tools, dnsutils, telnet, nc)"
echo "  3. Web Browsers (lynx, w3m, links, firefox-esr if available)"
echo "  4. Development Essentials (build-essential, git, vim)"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo_error "This script must be run as root"
    echo "Run: sudo $0"
    exit 1
fi

# Verify we're on Hurd
if ! uname -a | grep -qi "GNU"; then
    echo_warning "This doesn't appear to be GNU/Hurd. Continuing anyway..."
fi

# ============================================================================
# PHASE 1: UPDATE PACKAGE LISTS
# ============================================================================

echo_info "Updating package lists..."
if apt-get update; then
    echo_success "Package lists updated"
else
    echo_error "Failed to update package lists. Check /etc/apt/sources.list"
    exit 1
fi

# ============================================================================
# PHASE 2: SSH SERVER
# ============================================================================

echo ""
echo_info "PHASE 2: Installing SSH Server..."

# Install SSH server
echo_info "Installing openssh-server..."
apt-get install -y openssh-server || {
    echo_error "Failed to install openssh-server"
    exit 1
}

# Install random-egd (entropy daemon for Hurd)
echo_info "Installing random-egd (entropy generator)..."
apt-get install -y random-egd || {
    echo_warning "random-egd not available, SSH may have entropy issues"
}

# Configure SSH to allow root login (change if needed)
echo_info "Configuring SSH..."
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config || true

# Set root password if not set
if ! passwd -S root 2>/dev/null | grep -q "P"; then
    echo_warning "Root password not set. Setting to 'root'..."
    echo "root:root" | chpasswd
fi

# Enable and start SSH
echo_info "Starting SSH service..."
if command -v systemctl >/dev/null 2>&1; then
    systemctl enable ssh || true
    systemctl restart ssh || true
else
    service ssh restart || true
fi

echo_success "SSH server installed and configured"
echo_info "  Login: ssh -p 2222 root@localhost (from host)"
echo_info "  Password: root (change with: passwd)"

# ============================================================================
# PHASE 3: NETWORK TOOLS
# ============================================================================

echo ""
echo_info "PHASE 3: Installing Network Tools..."

NETTOOLS=(
    "curl"
    "wget"
    "net-tools"
    "dnsutils"
    "telnet"
    "netcat-openbsd"
    "iputils-ping"
    "traceroute"
    "iproute2"
    "ca-certificates"
)

for tool in "${NETTOOLS[@]}"; do
    echo_info "Installing $tool..."
    apt-get install -y "$tool" 2>/dev/null || echo_warning "$tool not available"
done

echo_success "Network tools installed"

# ============================================================================
# PHASE 4: WEB BROWSERS
# ============================================================================

echo ""
echo_info "PHASE 4: Installing Web Browsers..."

# Text-based browsers (reliable on Hurd)
echo_info "Installing text-based browsers..."
apt-get install -y lynx w3m links elinks 2>/dev/null || {
    echo_warning "Some text browsers not available"
    apt-get install -y lynx || echo_warning "Could not install any text browser"
}

# GUI browser (if X11 available)
echo_info "Checking for GUI browser (firefox-esr)..."
if apt-cache search firefox-esr | grep -q firefox-esr; then
    echo_info "Installing firefox-esr..."
    apt-get install -y firefox-esr || echo_warning "firefox-esr installation failed"
else
    echo_warning "firefox-esr not available in repositories"
fi

echo_success "Browser installation complete"

# ============================================================================
# PHASE 5: DEVELOPMENT ESSENTIALS
# ============================================================================

echo ""
echo_info "PHASE 5: Installing Development Essentials..."

DEVTOOLS=(
    "build-essential"
    "git"
    "vim"
    "emacs-nox"
    "python3"
    "python3-pip"
    "make"
    "cmake"
    "autoconf"
    "automake"
    "libtool"
    "pkg-config"
)

for tool in "${DEVTOOLS[@]}"; do
    echo_info "Installing $tool..."
    apt-get install -y "$tool" 2>/dev/null || echo_warning "$tool not available"
done

echo_success "Development tools installed"

# ============================================================================
# PHASE 6: VERIFICATION
# ============================================================================

echo ""
echo_info "PHASE 6: Verifying Installation..."

# Check SSH
if systemctl is-active --quiet ssh 2>/dev/null || service ssh status 2>/dev/null | grep -q "running"; then
    echo_success "✓ SSH server is running"
else
    echo_warning "! SSH server may not be running. Start with: service ssh start"
fi

# Check SSH port
if ss -tlnp 2>/dev/null | grep -q ":22"; then
    echo_success "✓ SSH listening on port 22"
else
    echo_warning "! SSH not listening on port 22"
fi

# Check network tools
VERIFY_CMDS=("curl" "wget" "ping" "telnet" "nc" "git" "vim")
for cmd in "${VERIFY_CMDS[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo_success "✓ $cmd available"
    else
        echo_warning "✗ $cmd not found"
    fi
done

# Check browsers
BROWSERS=("lynx" "w3m" "links" "firefox-esr")
for browser in "${BROWSERS[@]}"; do
    if command -v "$browser" >/dev/null 2>&1; then
        echo_success "✓ $browser installed"
    else
        echo_warning "✗ $browser not found"
    fi
done

# ============================================================================
# PHASE 7: POST-INSTALL CONFIGURATION
# ============================================================================

echo ""
echo_info "PHASE 7: Post-Install Configuration..."

# Add useful aliases to root's .bashrc
if ! grep -q "# Essential Tools Aliases" /root/.bashrc; then
    cat >> /root/.bashrc << 'EOF'

# Essential Tools Aliases (added by install-essentials-hurd.sh)
alias update='apt-get update && apt-get upgrade'
alias install='apt-get install'
alias search='apt-cache search'
alias web='lynx'  # Quick text browser
alias myip='curl -s ifconfig.me'
alias ports='ss -tulanp'
alias sshrestart='service ssh restart'

# Network testing
alias pingtest='ping -c 3 8.8.8.8'
alias dnstest='nslookup google.com'

EOF
    echo_success "Added utility aliases to /root/.bashrc"
    echo_info "  Run: source ~/.bashrc to load them"
fi

# Create SSH welcome banner
cat > /etc/motd << 'EOF'
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

EOF

echo_success "Created login banner at /etc/motd"

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo "================================================================"
echo "  Installation Complete!"
echo "================================================================"
echo ""
echo_success "Installed Packages:"
echo "  ✓ SSH Server (openssh-server, random-egd)"
echo "  ✓ Network Tools (curl, wget, net-tools, dnsutils, etc.)"
echo "  ✓ Web Browsers (lynx, w3m, links, firefox-esr if available)"
echo "  ✓ Development Tools (build-essential, git, vim, python3)"
echo ""
echo_info "Next Steps:"
echo "  1. Test SSH from host:"
echo "     ssh -p 2222 root@localhost"
echo ""
echo "  2. Test network connectivity:"
echo "     ping -c 3 8.8.8.8"
echo "     curl https://www.gnu.org"
echo ""
echo "  3. Browse the web:"
echo "     lynx https://www.debian.org/ports/hurd/"
echo ""
echo "  4. Update packages:"
echo "     apt-get update && apt-get upgrade"
echo ""
echo_info "Useful aliases added to ~/.bashrc:"
echo "  - update, install, search, web, myip, ports, pingtest, dnstest"
echo ""
echo "================================================================"
echo ""
