#!/bin/bash
# =============================================================================
# Download GNU/Hurd QEMU Image from GitHub Releases
# =============================================================================
# Downloads the latest or a specific version of the Debian GNU/Hurd x86_64
# QEMU image from GitHub Releases, verifies checksums, and extracts if needed.
# =============================================================================

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    echo -e "${BLUE}[SUCCESS]${NC} $*" >&2
}

# =============================================================================
# CONFIGURATION
# =============================================================================
REPO="${REPO:-Oichkatzelesfrettschen/gnu-hurd-docker}"
VERSION="${VERSION:-latest}"
OUTPUT_DIR="${OUTPUT_DIR:-./images}"
COMPRESSED="${COMPRESSED:-true}"  # Download compressed by default
VERIFY_CHECKSUM="${VERIFY_CHECKSUM:-true}"

# =============================================================================
# USAGE
# =============================================================================
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Download GNU/Hurd QEMU image from GitHub Releases.

OPTIONS:
    -v, --version VERSION    Download specific version (default: latest)
    -o, --output DIR         Output directory (default: ./images)
    -u, --uncompressed       Download uncompressed image (default: compressed)
    -n, --no-verify          Skip checksum verification
    -h, --help               Show this help message

ENVIRONMENT VARIABLES:
    REPO                Repository name (default: Oichkatzelesfrettschen/gnu-hurd-docker)
    VERSION             Release version (default: latest)
    OUTPUT_DIR          Output directory (default: ./images)
    COMPRESSED          Download compressed (default: true)
    VERIFY_CHECKSUM     Verify checksums (default: true)

EXAMPLES:
    # Download latest compressed image
    $0

    # Download specific version uncompressed
    $0 --version 1.0.0 --uncompressed

    # Download to custom directory
    $0 --output /data/images

    # Skip checksum verification (not recommended)
    $0 --no-verify

EOF
    exit 1
}

# =============================================================================
# PARSE ARGUMENTS
# =============================================================================
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -u|--uncompressed)
            COMPRESSED=false
            shift
            ;;
        -n|--no-verify)
            VERIFY_CHECKSUM=false
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# =============================================================================
# MAIN LOGIC
# =============================================================================
main() {
    echo ""
    echo "================================================================"
    echo "  GNU/Hurd QEMU Image Downloader"
    echo "================================================================"
    echo ""

    log_info "Configuration:"
    log_info "  Repository: ${REPO}"
    log_info "  Version: ${VERSION}"
    log_info "  Output: ${OUTPUT_DIR}"
    log_info "  Compressed: ${COMPRESSED}"
    log_info "  Verify Checksum: ${VERIFY_CHECKSUM}"
    echo ""

    # Create output directory
    mkdir -p "${OUTPUT_DIR}"
    cd "${OUTPUT_DIR}"

    # Determine download URL
    local base_url="https://github.com/${REPO}/releases"
    local tag_name

    if [ "${VERSION}" = "latest" ]; then
        log_info "Fetching latest release information..."
        tag_name="latest"
        download_url="${base_url}/latest/download"
    else
        tag_name="v${VERSION}"
        download_url="${base_url}/download/${tag_name}"
    fi

    # Determine filename
    local filename
    local checksum_file
    if [ "${COMPRESSED}" = "true" ]; then
        if [ "${VERSION}" = "latest" ]; then
            filename="debian-hurd-amd64-latest.qcow2.xz"
            checksum_file="debian-hurd-amd64-latest.qcow2.xz.sha256"
        else
            filename="debian-hurd-amd64-${VERSION}.qcow2.xz"
            checksum_file="debian-hurd-amd64-${VERSION}.qcow2.xz.sha256"
        fi
    else
        if [ "${VERSION}" = "latest" ]; then
            filename="debian-hurd-amd64-latest.qcow2"
            checksum_file="debian-hurd-amd64-latest.qcow2.sha256"
        else
            filename="debian-hurd-amd64-${VERSION}.qcow2"
            checksum_file="debian-hurd-amd64-${VERSION}.qcow2.sha256"
        fi
    fi

    # Download image
    log_info "Downloading ${filename}..."
    if ! curl -L -f -o "${filename}" "${download_url}/${filename}"; then
        log_error "Failed to download ${filename}"
        log_error "URL: ${download_url}/${filename}"
        exit 1
    fi
    log_success "Downloaded: ${filename}"

    # Download checksum
    if [ "${VERIFY_CHECKSUM}" = "true" ]; then
        log_info "Downloading checksum file..."
        if ! curl -L -f -o "${checksum_file}" "${download_url}/${checksum_file}"; then
            log_warn "Failed to download checksum file, skipping verification"
            VERIFY_CHECKSUM=false
        else
            log_success "Downloaded: ${checksum_file}"
        fi
    fi

    # Verify checksum
    if [ "${VERIFY_CHECKSUM}" = "true" ]; then
        log_info "Verifying checksum..."
        if sha256sum -c "${checksum_file}"; then
            log_success "Checksum verification passed"
        else
            log_error "Checksum verification failed!"
            log_error "The downloaded file may be corrupted or tampered with."
            exit 1
        fi
    else
        log_warn "Skipping checksum verification (not recommended)"
    fi

    # Extract if compressed
    if [ "${COMPRESSED}" = "true" ]; then
        log_info "Extracting compressed image (this may take several minutes)..."
        if ! xz -d -k -v "${filename}"; then
            log_error "Failed to extract ${filename}"
            exit 1
        fi

        local extracted_file="${filename%.xz}"
        log_success "Extracted: ${extracted_file}"

        # Rename to standard filename
        if [ "${VERSION}" = "latest" ]; then
            mv "${extracted_file}" "debian-hurd-amd64.qcow2"
            log_info "Renamed to: debian-hurd-amd64.qcow2"
        else
            mv "${extracted_file}" "debian-hurd-amd64.qcow2"
            log_info "Renamed to: debian-hurd-amd64.qcow2"
        fi
    else
        # Rename to standard filename
        if [ "${VERSION}" = "latest" ]; then
            mv "${filename}" "debian-hurd-amd64.qcow2"
            log_info "Renamed to: debian-hurd-amd64.qcow2"
        else
            mv "${filename}" "debian-hurd-amd64.qcow2"
            log_info "Renamed to: debian-hurd-amd64.qcow2"
        fi
    fi

    # Show final image info
    if command -v qemu-img &> /dev/null; then
        echo ""
        log_info "Image information:"
        qemu-img info debian-hurd-amd64.qcow2
    fi

    echo ""
    echo "================================================================"
    echo "  Download Complete!"
    echo "================================================================"
    echo ""
    log_success "Image ready: $(pwd)/debian-hurd-amd64.qcow2"
    echo ""
    log_info "Next steps:"
    log_info "  1. Start VM: docker compose up -d"
    log_info "  2. Connect: ssh -p 2222 root@localhost"
    log_info "  3. Default credentials: root (no password)"
    echo ""
    log_warn "SECURITY: Change root password after first login!"
    echo ""
}

# Run main function
main "$@"
