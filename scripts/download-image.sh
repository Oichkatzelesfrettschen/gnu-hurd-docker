#!/bin/bash
set -euo pipefail

# GNU/Hurd Docker - Image Download Script
# Downloads and converts Debian GNU/Hurd system image
# WHY: Clean up incomplete downloads on error or interrupt
# WHAT: Track temp files created during download/extract/convert
# HOW: cleanup() removes temp files only if download incomplete

echo "=========================================="
echo "GNU/Hurd System Image Downloader"
echo "=========================================="
echo ""

# Configuration
# Official Debian GNU/Hurd images (Debian ports/13.0, hurd-amd64)
BASE_URL="https://cdimage.debian.org/cdimage/ports/13.0/hurd-amd64"
IMAGE_DIR="${IMAGE_DIR:-images}"

# Prefer the latest dated artifact so SHA256SUMS verification works.
# You may override by setting COMPRESSED_FILE explicitly, e.g.:
#   COMPRESSED_FILE=debian-hurd.img.tar.xz SKIP_CHECKSUM=1 ./scripts/download-image.sh
COMPRESSED_FILE="${COMPRESSED_FILE:-}"
QCOW2_IMAGE="debian-hurd-amd64.qcow2"
COMPRESSED_PATH=""
QCOW2_PATH="${IMAGE_DIR}/${QCOW2_IMAGE}"
WORKDIR=""

# Track cleanup state
CLEANUP_NEEDED=false
TEMP_FILES=()

cleanup() {
    local exit_code=$?
    
    if [ "$CLEANUP_NEEDED" = true ]; then
        echo ""
        echo "[INFO] Cleaning up incomplete downloads..."
        
        # Remove incomplete temp files / temporary work directory
        for file in "${TEMP_FILES[@]}"; do
            if [ -e "$file" ]; then
                echo "  [INFO] Removing: $file"
                rm -rf "$file"
            fi
        done
    fi
    
    exit $exit_code
}

trap cleanup EXIT INT TERM

echo "Configuration:"
echo "  Base URL:  $BASE_URL"
echo "  Output Dir: $IMAGE_DIR"
echo "  QCOW2 Image: $QCOW2_PATH"
echo ""

# Fetch URL content to stdout using curl or wget (whichever is available).
fetch_url_stdout() {
    local url="$1"
    if command -v curl &> /dev/null; then
        curl -fsSL "$url"
        return $?
    fi
    wget -qO- "$url"
}

# Decide which upstream artifact to download.
detect_latest_dated_artifact() {
    local listing
    listing="$(fetch_url_stdout "${BASE_URL}/" || true)"
    if [ -z "$listing" ]; then
        return 1
    fi

    local latest
    latest="$(echo "$listing" | grep -oE 'debian-hurd-amd64-[0-9]{8}\.img\.tar\.xz' | sort -u | tail -n 1)"
    if [ -z "$latest" ]; then
        return 1
    fi
    echo "$latest"
}

if [ -z "$COMPRESSED_FILE" ]; then
    COMPRESSED_FILE="$(detect_latest_dated_artifact || true)"
    if [ -z "$COMPRESSED_FILE" ]; then
        COMPRESSED_FILE="debian-hurd.img.tar.xz"
        echo "[WARN] Could not detect latest dated image; falling back to ${COMPRESSED_FILE}"
        echo "[WARN] Note: SHA256SUMS may not list the generic filename; set SKIP_CHECKSUM=1 if needed"
    fi
fi

DEBIAN_URL="${BASE_URL}/${COMPRESSED_FILE}"
COMPRESSED_PATH="${IMAGE_DIR}/${COMPRESSED_FILE}"

echo "Selected upstream artifact:"
echo "  Source URL:  $DEBIAN_URL"
echo "  Compressed:  $COMPRESSED_PATH"
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

if ! command -v sha256sum &> /dev/null; then
    echo "[WARN] sha256sum not found - checksum verification will be skipped"
fi

echo "[OK] All prerequisites found"
echo ""

# Check disk space
echo "Checking disk space..."
REQUIRED_SPACE=$((8 * 1024))  # 8GB in MB
mkdir -p "$IMAGE_DIR"
AVAILABLE=$(df -m "$IMAGE_DIR" | tail -1 | awk '{print $4}')

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

if [ -f "$COMPRESSED_PATH" ]; then
    echo "[SKIP] $COMPRESSED_PATH already exists"
else
    TEMP_FILES+=("$COMPRESSED_PATH")
    CLEANUP_NEEDED=true
    
    if command -v wget &> /dev/null; then
        wget -O "$COMPRESSED_PATH" "$DEBIAN_URL"
    else
        curl -fL --retry 3 -o "$COMPRESSED_PATH" "$DEBIAN_URL"
    fi
    
    if [ ! -f "$COMPRESSED_PATH" ]; then
        echo "[ERROR] Failed to download image"
        exit 1
    fi
fi

echo "[OK] Image downloaded"
echo ""

# Verify checksum (if possible)
if command -v sha256sum &> /dev/null && [ "${SKIP_CHECKSUM:-0}" != "1" ]; then
    echo "Verifying checksum (SHA256SUMS)..."
    SUMS_URL="$(dirname "$DEBIAN_URL")/SHA256SUMS"
    EXPECTED_LINE="$(fetch_url_stdout "$SUMS_URL" | grep -E "${COMPRESSED_FILE}\$" || true)"

    if [ -z "$EXPECTED_LINE" ]; then
        echo "[ERROR] Could not find ${COMPRESSED_FILE} in SHA256SUMS; refusing to skip verification"
        echo "[ERROR] Hint: set SKIP_CHECKSUM=1 (not recommended), or use a dated artifact that appears in SHA256SUMS"
        exit 1
    else
        EXPECTED_SHA="$(echo "$EXPECTED_LINE" | awk '{print $1}')"
        ACTUAL_SHA="$(sha256sum "$COMPRESSED_PATH" | awk '{print $1}')"
        if [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
            echo "[ERROR] SHA256 mismatch for ${COMPRESSED_PATH}"
            echo "  Expected: $EXPECTED_SHA"
            echo "  Actual:   $ACTUAL_SHA"
            exit 1
        fi
        echo "[OK] SHA256 verified"
    fi
    echo ""
fi

# Extract image
echo "Extracting compressed image..."
echo "This may take a few minutes..."
echo ""

WORKDIR="$(mktemp -d)"
TEMP_FILES+=("$WORKDIR")
CLEANUP_NEEDED=true

tar -C "$WORKDIR" -xf "$COMPRESSED_PATH"

RAW_PATH="$(find "$WORKDIR" -maxdepth 1 -type f -name '*.img' -print -quit)"
if [ -z "$RAW_PATH" ] || [ ! -f "$RAW_PATH" ]; then
    echo "[ERROR] Failed to extract image (no .img found in archive)"
    exit 1
fi

SIZE=$(du -h "$RAW_PATH" | cut -f1)
echo "[OK] Image extracted to temp dir ($SIZE)"
echo ""

# Convert to QCOW2
echo "Converting to QCOW2 format..."
echo "This may take 5-10 minutes..."
echo ""

if [ -f "$QCOW2_PATH" ]; then
    echo "[SKIP] $QCOW2_PATH already exists"
else
    qemu-img convert -f raw -O qcow2 "$RAW_PATH" "$QCOW2_PATH"
    
    if [ ! -f "$QCOW2_PATH" ]; then
        echo "[ERROR] Failed to convert image"
        exit 1
    fi
fi

SIZE=$(du -h "$QCOW2_PATH" | cut -f1)
echo "[OK] QCOW2 image created ($SIZE)"
echo ""

# Verify QCOW2
echo "Verifying QCOW2 integrity..."
if qemu-img check "$QCOW2_PATH" > /dev/null 2>&1; then
    echo "[OK] QCOW2 image is valid"
else
    echo "[ERROR] QCOW2 image check failed: $QCOW2_PATH"
    echo "[ERROR] Refusing to proceed (treating warnings as errors)."
    echo "[ERROR] Hint: delete the QCOW2 and retry (it may be a partial or corrupt conversion)."
    exit 1
fi

echo ""
echo "=========================================="
echo "Download Complete"
echo "=========================================="
echo ""
echo "Successfully prepared:"
echo "  $QCOW2_PATH"
echo ""
echo "Next steps:"
echo "  1. Validate configuration: ./scripts/validate-config.sh"
echo "  2. Build container image: make build"
echo "  3. Deploy container:      ./scripts/docker-orchestration.sh up"
echo ""

# Mark success so trap doesn't remove outputs
CLEANUP_NEEDED=false
