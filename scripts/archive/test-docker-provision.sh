#!/bin/bash
# Test the Docker provisioning workflow locally
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
echo_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
echo_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

echo ""
echo "================================================================"
echo "  Testing Docker Provisioning Workflow"
echo "================================================================"
echo ""

# Check prerequisites
echo_info "Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    echo_warning "Docker not found. Install docker first."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo_warning "docker-compose not found. Install docker-compose first."
    exit 1
fi

if [ ! -e /dev/kvm ]; then
    echo_warning "KVM not available. Provisioning will be VERY slow."
    echo_warning "Consider enabling KVM for faster builds."
fi

echo_success "Prerequisites OK"

# Check for base image
echo_info "Checking for base image..."
if [ ! -f "images/debian-hurd-i386-80gb.qcow2" ]; then
    echo_warning "Base image not found: images/debian-hurd-i386-80gb.qcow2"
    echo_info "Looking for alternative images..."
    
    if [ -f "debian-hurd.img" ]; then
        echo_info "Found: debian-hurd.img"
        echo_info "Converting to qcow2..."
        mkdir -p images
        qemu-img convert -f raw -O qcow2 debian-hurd.img images/debian-hurd-i386-80gb.qcow2
        echo_success "Converted to qcow2"
    else
        echo_warning "No suitable base image found."
        echo_info "Please download a Debian GNU/Hurd image first."
        exit 1
    fi
else
    echo_success "Base image found"
fi

# Build Docker image
echo_info "Building provisioning Docker image..."
docker build -f Dockerfile.provision -t hurd-provision:latest .
echo_success "Docker image built"

# Run provisioning
echo ""
echo_info "Starting provisioning (this will take 10-15 minutes with KVM)..."
echo_info "Press Ctrl+C to cancel if needed"
echo ""

docker-compose -f docker-compose.provision.yml up

# Check result
echo ""
if [ -f "images/debian-hurd-i386-80gb-provisioned.qcow2" ]; then
    echo_success "Provisioned image created!"
    echo ""
    echo_info "Image details:"
    qemu-img info images/debian-hurd-i386-80gb-provisioned.qcow2
    echo ""
    echo_info "To test the provisioned image:"
    echo "  QEMU_DRIVE=images/debian-hurd-i386-80gb-provisioned.qcow2 docker-compose up -d"
    echo "  ssh -p 2222 root@localhost"
    echo "  # Password: root"
else
    echo_warning "Provisioned image not found. Check logs above for errors."
    exit 1
fi

echo ""
echo "================================================================"
echo "  Test Complete!"
echo "================================================================"
echo ""
