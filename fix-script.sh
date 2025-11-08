#!/bin/bash
# GNU/Hurd Docker Kernel Networking Fix Script
# Detects and applies the appropriate fix for nf_tables/iptables issues

set -e

echo "=========================================================================="
echo "GNU/Hurd Docker - Kernel Networking Fix Utility"
echo "=========================================================================="
echo ""

# Check prerequisites
if ! command -v docker &>/dev/null; then
    echo "[ERROR] Docker not installed. Install first: pacman -S docker"
    exit 1
fi

KERNEL_VER=$(uname -r)
echo "[INFO] Kernel version: $KERNEL_VER"
echo ""

# Check current networking status
echo "[INFO] Checking networking configuration..."
echo ""

# Function to check nf_tables
check_nf_tables() {
    if lsmod | grep -q "nf_tables"; then
        return 0
    else
        return 1
    fi
}

# Function to check iptables mode
check_iptables_mode() {
    if readlink /usr/bin/iptables 2>/dev/null | grep -q "iptables-legacy"; then
        echo "legacy"
    elif readlink /usr/bin/iptables 2>/dev/null | grep -q "iptables-nft"; then
        echo "nft"
    else
        echo "unknown"
    fi
}

# Test Docker daemon
test_docker() {
    if docker ps &>/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

IPTABLES_MODE=$(check_iptables_mode)
echo "[*] Current iptables mode: $IPTABLES_MODE"

if check_nf_tables; then
    echo "[OK] nf_tables module is loaded"
else
    echo "[WARN] nf_tables module NOT loaded"
fi

echo ""
echo "Testing Docker daemon..."
if test_docker; then
    echo "[OK] Docker daemon is functional"
    echo ""
    echo "No action required!"
    exit 0
else
    echo "[ERROR] Docker daemon is not responding"
fi

echo ""
echo "=========================================================================="
echo "Available Fix Options:"
echo "=========================================================================="
echo ""
echo "Option 1: Rebuild kernel with nf_tables support (RECOMMENDED - long-term)"
echo "  Requires: linux-headers, gcc, make (2-3 hour compile)"
echo "  Command: See /usr/share/doc/gnu-hurd-docker-kernel-fix/README.md"
echo ""
echo "Option 2: Load nf_tables kernel modules (QUICK - if modules exist)"
echo "  Command: sudo modprobe nf_tables nf_tables_ipv4 nft_masq nf_nat"
echo ""
echo "Option 3: Switch to iptables-legacy wrapper (WORKAROUND)"
echo "  Requires: iptables-legacy package"
echo "  Commands:"
echo "    sudo pacman -S iptables-legacy"
echo "    sudo update-alternatives --set iptables /usr/bin/iptables-legacy"
echo "    sudo update-alternatives --set ip6tables /usr/bin/ip6tables-legacy"
echo "    sudo systemctl restart docker"
echo ""
echo "=========================================================================="
echo ""
echo "See documentation at:"
echo "  /usr/share/doc/gnu-hurd-docker-kernel-fix/README.md"
echo "  https://github.com/oaich/gnu-hurd-docker"
echo ""
