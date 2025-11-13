#!/bin/bash
# Node.js Installation for Debian GNU/Hurd x86_64 (amd64)
# Attempts multiple installation methods with fallbacks
# Version: 2.0

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
echo_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
echo_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo "================================================================"
echo "  Node.js Installation for Debian GNU/Hurd x86_64 (amd64)"
echo "================================================================"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo_error "This script must be run as root"
    exit 1
fi

# ============================================================================
# METHOD 1: Try Debian Repository (Most Likely to Work)
# ============================================================================

echo_info "METHOD 1: Attempting installation from Debian repositories..."
echo_info "This may install an older version (Node.js 12-18) but should work"
echo ""

if apt-get update; then
    echo_success "Package lists updated"
else
    echo_error "Failed to update package lists"
    exit 1
fi

# Check what's available
echo_info "Checking available Node.js packages..."
AVAILABLE_NODEJS=$(apt-cache search "^nodejs$" | grep "^nodejs ")

if [ -n "$AVAILABLE_NODEJS" ]; then
    echo_success "Found nodejs package in Debian repositories"
    echo_info "Package details:"
    apt-cache show nodejs | grep -E "^(Package|Version|Architecture):" | head -10
    echo ""

    read -p "Install nodejs from Debian repos? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo_info "Installing nodejs and npm..."
        if apt-get install -y nodejs npm; then
            echo_success "Node.js installed from Debian repositories"

            # Verify installation
            NODE_VERSION=$(node --version 2>/dev/null || echo "not found")
            NPM_VERSION=$(npm --version 2>/dev/null || echo "not found")

            echo_success "Node.js version: $NODE_VERSION"
            echo_success "npm version: $NPM_VERSION"

            # Create npm global directory for non-root installs
            mkdir -p /root/.npm-global
            npm config set prefix '/root/.npm-global'

            if ! grep -q "npm-global" /root/.bashrc; then
                echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> /root/.bashrc
                echo_success "Added npm global bin to PATH"
            fi

            echo ""
            echo_success "Node.js installation complete!"
            echo_info "Run: source ~/.bashrc to update PATH"
            exit 0
        else
            echo_error "Failed to install from Debian repos"
        fi
    fi
else
    echo_warning "nodejs package not found in Debian repositories"
fi

# ============================================================================
# METHOD 2: Build from Source (Advanced, Time-Consuming)
# ============================================================================

echo ""
echo_info "METHOD 2: Building Node.js from source..."
echo_warning "This will take 30-60 minutes and requires significant disk space"
echo ""

read -p "Build Node.js from source? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo_info "Installing build dependencies..."
    apt-get install -y \
        build-essential \
        python3 \
        curl \
        git \
        libssl-dev \
        || {
            echo_error "Failed to install build dependencies"
            exit 1
        }

    # Use LTS Node.js version compatible with x86_64
    NODE_VERSION="v18.20.0"  # LTS, x86_64-compatible
    NODE_DIR="/usr/local/src/node-$NODE_VERSION"

    echo_info "Downloading Node.js $NODE_VERSION source..."
    cd /usr/local/src

    if [ ! -d "$NODE_DIR" ]; then
        curl -fsSL "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION.tar.gz" | tar xz
    else
        echo_info "Source already downloaded"
    fi

    cd "$NODE_DIR"

    echo_info "Configuring Node.js build..."
    echo_warning "This may fail on GNU/Hurd due to platform incompatibilities"

    # Configure for x86_64 architecture
    ./configure \
        --prefix=/usr/local \
        --without-intl \
        || {
            echo_error "Configuration failed"
            echo_error "Node.js may not be fully compatible with GNU/Hurd x86_64"
            exit 1
        }

    echo_info "Building Node.js (this will take a long time)..."
    make -j"$(nproc)" || {
        echo_error "Build failed"
        echo_error "Trying without parallel build..."
        make || {
            echo_error "Build still failed. Node.js may not be compatible with Hurd"
            exit 1
        }
    }

    echo_info "Installing Node.js..."
    make install || {
        echo_error "Installation failed"
        exit 1
    }

    NODE_VERSION=$(node --version 2>/dev/null || echo "not found")
    NPM_VERSION=$(npm --version 2>/dev/null || echo "not found")

    echo_success "Node.js built from source!"
    echo_success "Node.js version: $NODE_VERSION"
    echo_success "npm version: $NPM_VERSION"

    exit 0
fi

# ============================================================================
# METHOD 3: Manual Binary Download (Unlikely to Work on Hurd)
# ============================================================================

echo ""
echo_warning "No automated installation methods succeeded"
echo ""
echo_info "Manual options:"
echo "  1. Check Debian testing/unstable repos:"
echo "     Add 'deb http://deb.debian.org/debian testing main' to /etc/apt/sources.list"
echo "     Then: apt-get update && apt-get install nodejs"
echo ""
echo "  2. Build from source manually:"
echo "     cd /usr/local/src"
echo "     curl -fsSL https://nodejs.org/dist/v18.20.0/node-v18.20.0.tar.gz | tar xz"
echo "     cd node-v18.20.0"
echo "     ./configure --prefix=/usr/local"
echo "     make -j$(nproc)"
echo "     make install"
echo ""
echo "  3. Use Python as alternative:"
echo "     Python 3 is already installed and works well on Hurd"
echo ""

exit 1
