#!/bin/bash
# GNU/Hurd Docker - Optimized Package Installation Script
# Installs recommended packages for CLI and GUI development on Debian GNU/Hurd 2025

set -euo pipefail

# Source libraries
# shellcheck source=lib/colors.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/colors.sh"

echo ""
echo "================================================================"
echo "  Debian GNU/Hurd 2025 - Optimized Package Installation"
echo "================================================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo_warning "This script should be run as root or with sudo"
    echo "Run: sudo $0"
    exit 1
fi

# Update package lists
echo_info "Updating package lists..."
apt-get update

# Core Development Tools
echo ""
echo_info "Installing core development tools..."
apt-get install -y \
    build-essential \
    gcc g++ \
    make cmake \
    autoconf automake libtool \
    pkg-config \
    git \
    gdb \
    manpages-dev \
    dpkg-dev \
    || echo_warning "Some development tools may not be available on Hurd"

echo_success "Core development tools installed"

# Additional Programming Languages
echo ""
echo_info "Installing additional programming languages..."
apt-get install -y \
    python3 python3-pip python3-dev \
    perl libperl-dev \
    || echo_warning "Some language packages may not be available"

# Try to install optional languages
apt-get install -y ruby-full 2>/dev/null || echo_warning "Ruby not available"
apt-get install -y golang 2>/dev/null || echo_warning "Go not available"
apt-get install -y openjdk-17-jdk 2>/dev/null || echo_warning "Java not available"

echo_success "Programming languages installed"

# System Utilities
echo ""
echo_info "Installing system utilities..."
apt-get install -y \
    curl wget \
    htop \
    screen tmux \
    rsync \
    zip unzip \
    tree \
    net-tools \
    dnsutils \
    ca-certificates \
    vim \
    less \
    || echo_warning "Some utilities may not be available"

echo_success "System utilities installed"

# Hurd-Specific Packages
echo ""
echo_info "Installing Hurd-specific development packages..."
apt-get install -y \
    hurd-dev \
    gnumach-dev \
    mig \
    2>/dev/null || echo_warning "Some Hurd development packages not available"

echo_success "Hurd development packages installed"

# GUI Packages (optional)
echo ""
read -p "Install GUI packages (Xfce)? This will take significant time and space. [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo_info "Installing X11 and Xfce..."
    
    # X11 essentials
    apt-get install -y \
        xorg \
        x11-xserver-utils \
        xterm \
        xinit \
        || echo_warning "Some X11 packages not available"
    
    # Xfce desktop
    apt-get install -y \
        xfce4 \
        xfce4-goodies \
        xfce4-terminal \
        thunar \
        mousepad \
        || echo_warning "Some Xfce packages not available"
    
    # Development IDEs
    apt-get install -y \
        emacs \
        geany \
        2>/dev/null || echo_warning "Some IDE packages not available"
    
    # Graphics applications
    apt-get install -y \
        firefox-esr \
        gimp \
        2>/dev/null || echo_warning "Some graphics applications not available"
    
    echo_success "GUI packages installed"
    
    echo ""
    echo_info "To start Xfce, run: startxfce4"
fi

# Create development directories
echo ""
echo_info "Creating development directories..."
mkdir -p /home/*/workspace
mkdir -p /home/*/projects
mkdir -p /usr/local/src

echo_success "Development directories created"

# Configure bash aliases
echo ""
echo_info "Configuring bash aliases..."
for home_dir in /home/*/ /root/; do
    if [ -d "$home_dir" ]; then
        cat >> "${home_dir}.bashrc" << 'EOF'

# GNU/Hurd Development Aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias gs='git status'
alias gl='git log --oneline -10'
alias gd='git diff'
EOF
        echo_success "Configured aliases for $home_dir"
    fi
done

# Set up 9p mount point
echo ""
echo_info "Setting up 9p mount point for host filesystem sharing..."
mkdir -p /mnt/host
cat >> /etc/fstab << 'EOF'
# 9p filesystem sharing from Docker host
scripts /mnt/host 9p trans=virtio,version=9p2000.L,nofail 0 0
EOF

echo_success "9p mount point configured at /mnt/host"
echo_info "Mount with: mount /mnt/host"

# System optimizations
echo ""
echo_info "Applying system optimizations..."

# Increase file descriptor limits
cat >> /etc/security/limits.conf << 'EOF'
# Increased limits for development
* soft nofile 4096
* hard nofile 8192
EOF

echo_success "System optimizations applied"

# Display summary
echo ""
echo "================================================================"
echo "  Installation Complete!"
echo "================================================================"
echo ""
echo "Installed packages:"
echo "  ✓ Core development tools (gcc, make, cmake, git, gdb)"
echo "  ✓ Programming languages (Python, Perl, and more)"
echo "  ✓ System utilities (curl, htop, screen, vim)"
echo "  ✓ Hurd development packages"
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "  ✓ GUI packages (X11, Xfce, Firefox)"
fi
echo ""
echo "Next steps:"
echo "  1. Mount shared filesystem: mount /mnt/host"
echo "  2. Test development tools: gcc --version"
echo "  3. Start GUI (if installed): startxfce4"
echo "  4. Create your projects in ~/workspace/ or ~/projects/"
echo ""
echo "Configuration:"
echo "  - Bash aliases configured in ~/.bashrc"
echo "  - 9p mount point: /mnt/host"
echo "  - Development directories: ~/workspace, ~/projects"
echo ""
echo "For more information, see:"
echo "  /usr/share/doc/gnu-hurd-docker/QEMU-OPTIMIZATION-2025.md"
echo ""
echo "================================================================"
