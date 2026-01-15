#!/bin/bash
# Check common ports used by this repo for collisions on the host.
#
# Usage:
#   SSH_PORT=2222 HTTP_PORT=8080 SERIAL_PORT=5555 MONITOR_PORT=9999 VNC_PORT=5900 NOVNC_PORT=6080 ./scripts/check-ports.sh
#
set -euo pipefail

ports=(
  "${SSH_PORT:-2222}"
  "${HTTP_PORT:-8080}"
  "${SERIAL_PORT:-5555}"
  "${MONITOR_PORT:-9999}"
  "${VNC_PORT:-5900}"
  "${NOVNC_PORT:-6080}"
)

unique_ports=()
for p in "${ports[@]}"; do
  [[ "$p" =~ ^[0-9]+$ ]] || { echo "[ERROR] Invalid port: $p" >&2; exit 2; }
  unique_ports+=("$p")
done

echo "[*] Checking host port listeners..." >&2
if command -v ss >/dev/null 2>&1; then
  for p in "${unique_ports[@]}"; do
    if ss -ltnp 2>/dev/null | grep -qE ":[[:space:]]*${p}\\b|:${p}\\b"; then
      echo "[WARN] Port ${p} is already in use:" >&2
      ss -ltnp 2>/dev/null | grep -E ":${p}\\b" | sed 's/^/  /' >&2 || true
    else
      echo "[OK]   Port ${p} is free" >&2
    fi
  done
else
  echo "[WARN] 'ss' not found; cannot check ports" >&2
fi

