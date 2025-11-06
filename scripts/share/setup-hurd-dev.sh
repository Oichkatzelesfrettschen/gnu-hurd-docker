#!/bin/bash
# GNU/Hurd Development Environment Setup Script
# Run this script inside the Hurd guest to install complete development toolchain
# Version: 1.0
# Date: 2025-11-05

set -e

echo "======================================================================"
echo "  GNU/Hurd Docker - Development Environment Setup"
echo "======================================================================"
echo ""
echo "This script will install a comprehensive development environment including:"
echo "  - Core compilation tools (GCC, Clang, Make, CMake)"
echo "  - Mach-specific utilities (MIG, GNU Mach headers)"
echo "  - Debugging and profiling tools (GDB, strace, valgrind)"
echo "  - Version control (Git)"
echo "  - Text editors (Vim, Emacs)"
echo "  - Build systems (Autotools, Meson, Ninja)"
echo "  - Documentation tools (Doxygen, Graphviz)"
echo ""
echo "Estimated disk space: ~1.5 GB"
echo "Estimated time: ~20-30 minutes (depends on mirror speed)"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 0
fi

echo ""
echo "[1/10] Updating package lists..."
apt-get update || { echo "ERROR: apt-get update failed"; exit 1; }

echo ""
echo "[2/10] Installing core development tools..."
apt-get install -y \
    gcc \
    g++ \
    make \
    cmake \
    autoconf \
    automake \
    libtool \
    pkg-config \
    flex \
    bison \
    texinfo \
    || { echo "ERROR: Core tools installation failed"; exit 1; }

echo ""
echo "[3/10] Installing compilers and toolchains..."
apt-get install -y \
    clang \
    llvm \
    lld \
    binutils-dev \
    libelf-dev \
    || { echo "ERROR: Compiler installation failed"; exit 1; }

echo ""
echo "[4/10] Installing Mach-specific development packages..."
apt-get install -y \
    gnumach-dev \
    hurd-dev \
    mig \
    hurd-doc \
    || { echo "ERROR: Mach tools installation failed"; exit 1; }

echo ""
echo "[5/10] Installing debuggers and profiling tools..."
apt-get install -y \
    gdb \
    strace \
    ltrace \
    sysstat \
    || { echo "ERROR: Debugging tools installation failed"; exit 1; }

echo ""
echo "[6/10] Installing version control and editors..."
apt-get install -y \
    git \
    vim \
    emacs-nox \
    nano \
    || { echo "ERROR: VCS/editor installation failed"; exit 1; }

echo ""
echo "[7/10] Installing build systems..."
apt-get install -y \
    ninja-build \
    meson \
    scons \
    || { echo "ERROR: Build system installation failed"; exit 1; }

echo ""
echo "[8/10] Installing documentation and analysis tools..."
apt-get install -y \
    doxygen \
    graphviz \
    man-db \
    manpages-dev \
    || { echo "ERROR: Documentation tools installation failed"; exit 1; }

echo ""
echo "[9/10] Installing networking and debugging utilities..."
apt-get install -y \
    netcat-openbsd \
    tcpdump \
    curl \
    wget \
    rsync \
    screen \
    tmux \
    || { echo "ERROR: Network utilities installation failed"; exit 1; }

echo ""
echo "[10/10] Cleaning up package cache..."
apt-get clean || echo "WARNING: Cache cleanup failed (non-fatal)"

echo ""
echo "======================================================================"
echo "  Development Environment Setup Complete!"
echo "======================================================================"
echo ""
echo "Installed tools:"
echo "  - GCC $(gcc --version | head -1 | awk '{print $NF}')"
echo "  - Clang $(clang --version | head -1 | awk '{print $NF}')"
echo "  - CMake $(cmake --version | head -1 | awk '{print $NF}')"
echo "  - MIG $(mig --version 2>&1 | head -1 | awk '{print $NF}')"
echo "  - GDB $(gdb --version | head -1 | awk '{print $NF}')"
echo "  - Git $(git --version | awk '{print $NF}')"
echo ""
echo "Next steps:"
echo "  1. Run ./configure-users.sh to setup accounts"
echo "  2. Run ./configure-shell.sh to customize shell environment"
echo "  3. Start developing!"
echo ""
echo "Test compilation:"
echo "  echo 'int main() { return 0; }' > test.c"
echo "  gcc test.c -o test && ./test && echo 'SUCCESS!'"
echo ""
