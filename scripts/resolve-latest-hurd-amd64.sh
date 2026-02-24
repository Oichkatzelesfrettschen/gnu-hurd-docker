#!/bin/bash
set -euo pipefail

# Resolve the newest dated Debian GNU/Hurd amd64 image artifact from ports/latest.

BASE_URL="${BASE_URL:-https://cdimage.debian.org/cdimage/ports/latest/hurd-amd64}"
MODE="${1:-report}" # report | artifact | date

fetch_url_stdout() {
    local url="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url"
        return $?
    fi
    wget -qO- "$url"
}

listing="$(fetch_url_stdout "${BASE_URL}/" || true)"
if [[ -z "$listing" ]]; then
    echo "[ERROR] Failed to fetch listing from ${BASE_URL}/" >&2
    exit 1
fi

artifact="$(echo "$listing" | grep -oE 'debian-hurd-amd64-[0-9]{8}\.img\.tar\.xz' | sort -u | tail -n 1)"
if [[ -z "$artifact" ]]; then
    echo "[ERROR] No dated hurd-amd64 artifact found at ${BASE_URL}/" >&2
    exit 1
fi

build_date="$(echo "$artifact" | sed -E 's/.*-([0-9]{8})\.img\.tar\.xz/\1/')"
checksum_type=""
checksum=""
sha_line="$(fetch_url_stdout "${BASE_URL}/SHA256SUMS" 2>/dev/null | grep -E "${artifact}\$" || true)"
if [[ -n "$sha_line" ]]; then
    checksum_type="sha256"
    checksum="$(echo "$sha_line" | awk '{print $1}')"
else
    md5_line="$(fetch_url_stdout "${BASE_URL}/MD5SUMS" 2>/dev/null | grep -E "${artifact}\$" || true)"
    if [[ -n "$md5_line" ]]; then
        checksum_type="md5"
        checksum="$(echo "$md5_line" | awk '{print $1}')"
    fi
fi

case "$MODE" in
    artifact)
        echo "$artifact"
        ;;
    date)
        echo "$build_date"
        ;;
    report)
        echo "BASE_URL=${BASE_URL}"
        echo "ARTIFACT=${artifact}"
        echo "BUILD_DATE=${build_date}"
        if [[ -n "$checksum" ]]; then
            echo "CHECKSUM_TYPE=${checksum_type}"
            echo "CHECKSUM=${checksum}"
        fi
        ;;
    *)
        echo "[ERROR] Unknown mode '$MODE' (supported: report, artifact, date)" >&2
        exit 1
        ;;
esac
