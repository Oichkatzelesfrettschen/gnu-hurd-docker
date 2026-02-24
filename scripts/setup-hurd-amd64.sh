#!/bin/bash
# Setup Debian GNU/Hurd x86_64 (amd64) disk image in ./images for Docker/Podman runs.
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo ""
echo "================================================================"
echo "  Debian GNU/Hurd x86_64 (amd64) Setup"
echo "================================================================"
echo ""

cd "$REPO_ROOT"

mkdir -p images

echo_info "Downloading and converting official Debian GNU/Hurd image..."
IMAGE_TRACK=release IMAGE_DIR=images "${SCRIPT_DIR}/download-image.sh"

if [ -f "images/debian-hurd-amd64.qcow2" ]; then
    echo ""
    echo_success "Image ready: images/debian-hurd-amd64.qcow2"
    if command -v qemu-img >/dev/null 2>&1; then
        echo_info "Image info:"
        qemu-img info images/debian-hurd-amd64.qcow2 | sed 's/^/  /'
    fi
else
    echo_warn "Expected images/debian-hurd-amd64.qcow2 not found after download"
    exit 1
fi

echo ""
echo_info "Next steps:"
echo "  1. Validate:   ./scripts/validate-config.sh"
echo "  2. Build:      make build"
echo "  3. Run (dev):  make up"
echo "  4. Run (KVM):  make up-kvm"
echo "  5. Run (vol):  make up-volume"
echo "  6. Latest prebuilt img: make setup-latest && make up-latest"
echo "  7. Fresh daily installer: make setup-daily-installer && make up-installer"
echo ""
