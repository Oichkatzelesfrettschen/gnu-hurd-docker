#!/bin/bash
set -euo pipefail

# Resolve the newest Debian installer daily build for hurd-amd64 and report
# a pinned mini.iso URL with checksum metadata when available.

MODE="${1:-report}"
DAILY_ROOT="${DAILY_ROOT:-https://d-i.debian.org/daily-images/hurd-amd64}"
ARTIFACT_PATH="${ARTIFACT_PATH:-netboot/mini.iso}"

index_html="$(curl -fsSL "${DAILY_ROOT}/")"
latest_build="$(
    printf '%s\n' "$index_html" \
        | grep -Eo '[0-9]{8}-[0-9]{2}:[0-9]{2}/' \
        | tr -d '/' \
        | sort -u \
        | tail -1
)"

if [ -z "$latest_build" ]; then
    echo "[ERROR] Could not resolve latest build from ${DAILY_ROOT}/" >&2
    exit 1
fi

build_date="${latest_build%%-*}"
pinned_base_url="${DAILY_ROOT}/${latest_build}"
moving_base_url="${DAILY_ROOT}/daily"
artifact_url="${pinned_base_url}/${ARTIFACT_PATH}"

sha256=""
sha256sums="$(curl -fsSL "${pinned_base_url}/SHA256SUMS" 2>/dev/null || true)"
if [ -n "$sha256sums" ]; then
    sha256="$(
        printf '%s\n' "$sha256sums" \
            | awk -v p1="./${ARTIFACT_PATH}" -v p2="${ARTIFACT_PATH}" '$2==p1 || $2==p2 {print $1; exit}'
    )"
fi

case "$MODE" in
    report)
        echo "DAILY_ROOT=${DAILY_ROOT}"
        echo "LATEST_BUILD=${latest_build}"
        echo "BUILD_DATE=${build_date}"
        echo "PINNED_BASE_URL=${pinned_base_url}"
        echo "MOVING_BASE_URL=${moving_base_url}"
        echo "ARTIFACT_PATH=${ARTIFACT_PATH}"
        echo "ARTIFACT_URL=${artifact_url}"
        if [ -n "$sha256" ]; then
            echo "SHA256=${sha256}"
        fi
        ;;
    build)
        echo "$latest_build"
        ;;
    date)
        echo "$build_date"
        ;;
    url)
        echo "$artifact_url"
        ;;
    sha256)
        if [ -n "$sha256" ]; then
            echo "$sha256"
        fi
        ;;
    *)
        echo "[ERROR] Usage: $0 [report|build|date|url|sha256]" >&2
        exit 2
        ;;
esac
