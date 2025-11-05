#!/bin/bash
set -e

# GNU/Hurd Docker - Image Download Script
# Downloads and converts Debian GNU/Hurd system image

echo "=========================================="
echo "GNU/Hurd System Image Downloader"
echo "=========================================="
echo ""

# Configuration
DEBIAN_URL="https://cdimage.debian.org/cdimage/ports/latest/hurd-i386/debian-hurd.img.tar.xz"
COMPRESSED_FILE="debian-hurd.img.tar.xz"
RAW_IMAGE="debian-hurd-i386-20250807.img"
QCOW2_IMAGE="debian-hurd-i386-20250807.qcow2"

echo "Configuration:"
echo "  Source URL: $DEBIAN_URL"
echo "  Compressed: $COMPRESSED_FILE"
echo "  Raw Image: $RAW_IMAGE"
echo "  QCOW2 Image: $QCOW2_IMAGE"
echo ""

# Check for required tools
echo "Checking prerequisites..."
echo ""

if ! command -v wget &> /dev/null && ! command -v curl &> /dev/null; then
    echo "[ERROR] Neither wget nor curl found. Please install one."
    exit 1
fi

if ! command -v tar &> /dev/null; then
    echo "[ERROR] tar not found. Please install tar."
    exit 1
fi

if ! command -v qemu-img &> /dev/null; then
    echo "[ERROR] qemu-img not found. Please install qemu-utils."
    exit 1
fi

echo "[OK] All prerequisites found"
echo ""

# Check disk space
echo "Checking disk space..."
REQUIRED_SPACE=$((8 * 1024))  # 8GB in MB
AVAILABLE=$(df -m . | tail -1 | awk '{print $4}')

if [ "$AVAILABLE" -lt "$REQUIRED_SPACE" ]; then
    echo "[ERROR] Insufficient disk space. Need $REQUIRED_SPACE MB, have $AVAILABLE MB"
    exit 1
fi

echo "[OK] Sufficient disk space available ($AVAILABLE MB)"
echo ""

# Download image
echo "Downloading system image..."
echo "Size: ~355 MB (compressed) -> 4.2 GB (raw) -> 2.1 GB (QCOW2)"
echo ""

if [ -f "$COMPRESSED_FILE" ]; then
    echo "[SKIP] $COMPRESSED_FILE already exists"
else
    if command -v wget &> /dev/null; then
        wget -O "$COMPRESSED_FILE" "$DEBIAN_URL"
    else
        curl -L -o "$COMPRESSED_FILE" "$DEBIAN_URL"
    fi
    
    if [ ! -f "$COMPRESSED_FILE" ]; then
        echo "[ERROR] Failed to download image"
        exit 1
    fi
fi

echo "[OK] Image downloaded"
echo ""

# Extract image
echo "Extracting compressed image..."
echo "This may take a few minutes..."
echo ""

if [ -f "$RAW_IMAGE" ]; then
    echo "[SKIP] $RAW_IMAGE already exists"
else
    tar xf "$COMPRESSED_FILE"
    
    if [ ! -f "$RAW_IMAGE" ]; then
        echo "[ERROR] Failed to extract image"
        exit 1
    fi
fi

SIZE=$(du -h "$RAW_IMAGE" | cut -f1)
echo "[OK] Image extracted ($SIZE)"
echo ""

# Convert to QCOW2
echo "Converting to QCOW2 format..."
echo "This may take 5-10 minutes..."
echo ""

if [ -f "$QCOW2_IMAGE" ]; then
    echo "[SKIP] $QCOW2_IMAGE already exists"
else
    qemu-img convert -f raw -O qcow2 "$RAW_IMAGE" "$QCOW2_IMAGE"
    
    if [ ! -f "$QCOW2_IMAGE" ]; then
        echo "[ERROR] Failed to convert image"
        exit 1
    fi
fi

SIZE=$(du -h "$QCOW2_IMAGE" | cut -f1)
echo "[OK] QCOW2 image created ($SIZE)"
echo ""

# Verify QCOW2
echo "Verifying QCOW2 integrity..."
if qemu-img check "$QCOW2_IMAGE" > /dev/null 2>&1; then
    echo "[OK] QCOW2 image is valid"
else
    echo "[WARN] QCOW2 image may have errors (non-critical)"
fi

echo ""
echo "=========================================="
echo "Download Complete"
echo "=========================================="
echo ""
echo "Successfully prepared:"
echo "  $QCOW2_IMAGE"
echo ""
echo "Next steps:"
echo "  1. Validate configuration: ./scripts/validate-config.sh"
echo "  2. Build Docker image:    docker-compose build"
echo "  3. Deploy container:      docker-compose up -d"
echo ""
