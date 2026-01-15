#!/bin/bash
set -euo pipefail

# Capture a QEMU "screendump" via the monitor and store a PNG on the host.
# Works even when we can't drive a real browser for noVNC.
#
# Requires:
# - expect + telnet on host
# - docker (or podman) to copy the ppm out of the container
# - ImageMagick (convert) OR Python Pillow (PIL) for PPM->PNG
#
# Usage:
#   MONITOR_PORT=9998 SERVICE_NAME=gnu-hurd-dev ./scripts/qemu-screenshot.sh
#
# Output:
#   logs/screenshots/<timestamp>.png

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=lib/container-runtime.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/container-runtime.sh"

SERVICE_NAME="${SERVICE_NAME:-gnu-hurd-dev}"
MONITOR_HOST="${MONITOR_HOST:-127.0.0.1}"
MONITOR_PORT="${MONITOR_PORT:-9999}"

ts="$(date +%Y%m%d-%H%M%S)"
out_dir="${OUT_DIR:-logs/screenshots}"
mkdir -p "$out_dir"

ppm_in_container="/tmp/qemu-screendump-${ts}.ppm"
ppm_on_host="${out_dir}/qemu-${ts}.ppm"
png_on_host="${out_dir}/qemu-${ts}.png"

echo "[*] Requesting screendump -> ${ppm_in_container}"
monitor_out="$(MONITOR_HOST="${MONITOR_HOST}" MONITOR_PORT="${MONITOR_PORT}" ./scripts/qemu-monitor-command.sh "screendump ${ppm_in_container}" || true)"
if [[ -n "${monitor_out}" ]]; then
  # Only show monitor output on failure; it is often noisy due to telnet echo.
  true
fi

runtime="$(get_container_runtime)"
echo "[*] Copying PPM out of container (${SERVICE_NAME})..."
for attempt in 1 2 3 4 5; do
  if "$runtime" exec "${SERVICE_NAME}" test -s "${ppm_in_container}" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done

if ! "$runtime" exec "${SERVICE_NAME}" test -s "${ppm_in_container}" >/dev/null 2>&1; then
  echo "[ERROR] QEMU did not create screendump file: ${ppm_in_container}" >&2
  if [[ -n "${monitor_out}" ]]; then
    echo "[ERROR] Monitor output:" >&2
    echo "${monitor_out}" >&2
  fi
  exit 1
fi

"$runtime" cp "${SERVICE_NAME}:${ppm_in_container}" "${ppm_on_host}"

echo "[*] Converting to PNG..."
if command -v magick >/dev/null 2>&1; then
  magick "${ppm_on_host}" "${png_on_host}"
elif command -v convert >/dev/null 2>&1; then
  convert "${ppm_on_host}" "${png_on_host}"
else
  PPM="${ppm_on_host}" PNG="${png_on_host}" python3 - <<'PY'
import os
from PIL import Image

ppm = os.environ["PPM"]
png = os.environ["PNG"]
im = Image.open(ppm)
im.save(png, format="PNG")
PY
fi

echo "[OK] ${png_on_host}"
echo "${png_on_host}"
