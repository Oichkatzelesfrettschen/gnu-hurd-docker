#!/bin/bash
set -euo pipefail

# Prepare the newest dated Debian GNU/Hurd amd64 image from ports/latest
# without clobbering the baseline pre-prepared image.

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE_DIR="${IMAGE_DIR:-images}"

cd "$REPO_ROOT"
mkdir -p "$IMAGE_DIR"

echo ""
echo "================================================================"
echo "  Debian GNU/Hurd x86_64 (amd64) Latest Track Setup"
echo "================================================================"
echo ""

resolver_report="$("${SCRIPT_DIR}/resolve-latest-hurd-amd64.sh" report)"
artifact="$(echo "$resolver_report" | awk -F= '/^ARTIFACT=/{print $2}')"
build_date="$(echo "$resolver_report" | awk -F= '/^BUILD_DATE=/{print $2}')"
checksum_type="$(echo "$resolver_report" | awk -F= '/^CHECKSUM_TYPE=/{print $2}')"
checksum="$(echo "$resolver_report" | awk -F= '/^CHECKSUM=/{print $2}')"
skip_checksum="${SKIP_CHECKSUM:-0}"

if [[ -z "$artifact" || -z "$build_date" ]]; then
    echo_warn "Could not resolve latest dated artifact from ports/latest"
    exit 1
fi

dated_qcow2="debian-hurd-amd64-${build_date}.qcow2"
latest_alias="debian-hurd-amd64.latest.qcow2"

echo_info "Resolved latest artifact: ${artifact}"
echo_info "Build date: ${build_date}"
if [[ -n "$checksum" ]]; then
    echo_info "Upstream checksum: ${checksum_type}:${checksum}"
else
    echo_warn "No upstream checksum entry found for ${artifact} on ports/latest"
    echo_warn "Proceeding with SKIP_CHECKSUM=1 for latest-track workflow"
    skip_checksum=1
fi
echo_info "Output image: ${IMAGE_DIR}/${dated_qcow2}"
echo ""

IMAGE_TRACK=latest \
COMPRESSED_FILE="${artifact}" \
QCOW2_IMAGE="${dated_qcow2}" \
SKIP_CHECKSUM="${skip_checksum}" \
IMAGE_DIR="${IMAGE_DIR}" \
"${SCRIPT_DIR}/download-image.sh"

(
    cd "${IMAGE_DIR}"
    ln -sfn "${dated_qcow2}" "${latest_alias}"
)

echo ""
echo_success "Latest image prepared:"
echo "  - ${IMAGE_DIR}/${dated_qcow2}"
echo "  - ${IMAGE_DIR}/${latest_alias} -> ${dated_qcow2}"
echo ""
echo_info "Run with latest image:"
echo "  HURD_IMAGE_BASENAME=${latest_alias} make up"
echo ""
echo_info "Run baseline pre-prepared image:"
echo "  make up"
echo ""
