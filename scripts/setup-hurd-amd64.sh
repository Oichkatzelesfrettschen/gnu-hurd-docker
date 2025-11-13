#!/bin/bash
# Setup Debian GNU/Hurd x86_64 (amd64) with 80GB dynamic qcow2 disk
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
echo_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

echo ""
echo "================================================================"
echo "  Debian GNU/Hurd x86_64 (amd64) Setup"
echo "================================================================"
echo ""

# Download if not present
if [ ! -f "debian-hurd-amd64.img.tar.xz" ]; then
    echo_info "Downloading Debian GNU/Hurd amd64 image (~350MB)..."
    curl -L -o debian-hurd-amd64.img.tar.xz \
        https://cdimage.debian.org/cdimage/ports/latest/hurd-amd64/debian-hurd.img.tar.xz
    echo_success "Download complete"
fi

# Extract
if [ ! -f "debian-hurd.img" ]; then
    echo_info "Extracting image..."
    tar -xJf debian-hurd-amd64.img.tar.xz
    echo_success "Extraction complete"
fi

# Convert to qcow2 with 80GB dynamic expansion
if [ ! -f "debian-hurd-amd64-80gb.qcow2" ]; then
    echo_info "Converting to qcow2 with 80GB dynamic expansion..."
    qemu-img convert -f raw -O qcow2 debian-hurd.img debian-hurd-amd64-80gb-base.qcow2
    
    echo_info "Resizing to 80GB (dynamic expansion)..."
    qemu-img resize debian-hurd-amd64-80gb-base.qcow2 80G
    
    mv debian-hurd-amd64-80gb-base.qcow2 debian-hurd-amd64-80gb.qcow2
    echo_success "qcow2 image created: debian-hurd-amd64-80gb.qcow2"
fi

# Show image info
echo ""
echo_info "Image information:"
qemu-img info debian-hurd-amd64-80gb.qcow2

echo ""
echo "================================================================"
echo "  Setup Complete!"
echo "================================================================"
echo ""
echo_success "x86_64 Hurd image ready: debian-hurd-amd64-80gb.qcow2"
echo_info "Virtual size: 80GB (grows dynamically)"
echo_info "Actual size: $(du -h debian-hurd-amd64-80gb.qcow2 | cut -f1)"
echo ""
echo_info "To start x86_64 Hurd VM:"
echo "  docker compose -f docker-compose.amd64.yml up -d"
echo ""
echo_info "Configuration:"
echo "  - CPU: host passthrough (native x86_64)"
echo "  - Cores: 4"
echo "  - RAM: 8GB"
echo "  - Storage: virtio (high performance)"
echo "  - Network: virtio-net-pci"
echo "  - SSH: port 2223"
echo "  - VNC: port 5902"
echo ""
