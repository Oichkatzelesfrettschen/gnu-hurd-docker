#!/bin/bash
set -euo pipefail

# Guest-level smoke test.
# Tries SSH first; if SSH is not available, falls back to serial "login:" prompt detection.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "$REPO_ROOT"

RUNTIME="${CONTAINER_RUNTIME:-docker}"
if [[ "$RUNTIME" == "podman" ]]; then
  SSH_PORT="${SSH_PORT:-2223}"
  SERIAL_PORT="${SERIAL_PORT:-5556}"
  MONITOR_PORT="${MONITOR_PORT:-9998}"
else
  SSH_PORT="${SSH_PORT:-2222}"
  SERIAL_PORT="${SERIAL_PORT:-5555}"
  MONITOR_PORT="${MONITOR_PORT:-9999}"
fi

SERVICE_NAME="${SERVICE_NAME:-gnu-hurd-dev}"
VNC_PORT="${VNC_PORT:-5900}"
NOVNC_PORT="${NOVNC_PORT:-6080}"

wait_for_tcp() {
  local host="$1"
  local port="$2"
  local seconds="$3"

  for _ in $(seq 1 "$seconds"); do
    if command -v nc >/dev/null 2>&1; then
      nc -z "$host" "$port" >/dev/null 2>&1 && return 0
    else
      (echo >/dev/tcp/"$host"/"$port") >/dev/null 2>&1 && return 0
    fi
    sleep 1
  done
  return 1
}

check_ssh_banner() {
  local host="$1"
  local port="$2"

  if command -v timeout >/dev/null 2>&1; then
    if command -v nc >/dev/null 2>&1; then
      timeout 3 nc "$host" "$port" </dev/null 2>/dev/null | tr -d '\r' | head -n 1 | grep -qE '^SSH-'
      return $?
    fi

    timeout 3 bash -lc "cat < /dev/tcp/${host}/${port}" 2>/dev/null | tr -d '\r' | head -n 1 | grep -qE '^SSH-'
    return $?
  fi

  return 1
}

query_monitor_status() {
  if ! command -v expect >/dev/null 2>&1; then
    return 1
  fi

  expect -c "
    set timeout 3
    spawn telnet 127.0.0.1 ${MONITOR_PORT}
    expect -re {\\(qemu\\)}
    send \"info status\\r\"
    expect -re {VM status:.*}
  " 2>/dev/null | tr -d '\r' | grep -oE 'VM status:.*' | head -n 1 || true
}

echo "[*] Starting container (KVM overlay if available)..."
CONTAINER_RUNTIME="$RUNTIME" make up-kvm || CONTAINER_RUNTIME="$RUNTIME" make up

echo ""
echo "[*] Waiting for SSH port ${SSH_PORT} to open..."
if wait_for_tcp 127.0.0.1 "$SSH_PORT" 180; then
  echo "[OK] SSH port is open"
  if check_ssh_banner 127.0.0.1 "$SSH_PORT"; then
    echo "[OK] SSH daemon banner detected (auth not validated)"
    exit 0
  fi
else
  echo "[WARN] SSH port did not open in time"
fi

echo ""
echo "[*] Attempting SSH command (best-effort)..."
if command -v ssh >/dev/null 2>&1; then
  if timeout 10 ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 root@localhost 'echo hurd-ssh-ok' 2>/dev/null | grep -q hurd-ssh-ok; then
    echo "[OK] SSH is functional"
    exit 0
  fi
fi

echo ""
echo "[WARN] SSH not confirmed; checking serial console prompt (telnet :${SERIAL_PORT})..."
if ! wait_for_tcp 127.0.0.1 "$SERIAL_PORT" 30; then
  echo "[ERROR] Serial port is not reachable on ${SERIAL_PORT}" >&2
  CONTAINER_RUNTIME="$RUNTIME" make logs >&2 || true
  exit 1
fi

if command -v timeout >/dev/null 2>&1 && command -v telnet >/dev/null 2>&1; then
  if timeout 15 telnet 127.0.0.1 "$SERIAL_PORT" 2>/dev/null | tr -d '\r' | grep -Eiq "login:|GNU|Mach|Hurd|Welcome"; then
    echo "[OK] Serial console shows a plausible boot/login prompt"
    exit 0
  fi
fi

echo "[ERROR] Could not confirm guest readiness via SSH or serial prompt" >&2
status_line="$(query_monitor_status || true)"
if [[ -n "${status_line:-}" ]]; then
  echo "[INFO] QEMU monitor: ${status_line}" >&2
fi
echo "[INFO] Next debugging steps:" >&2
echo "  - telnet localhost ${SERIAL_PORT} (serial)" >&2
echo "  - telnet localhost ${MONITOR_PORT} (monitor)" >&2
echo "  - CONTAINER_RUNTIME=${RUNTIME} make logs" >&2
echo "  - If serial stays blank, use VNC/noVNC:" >&2
echo "      CONTAINER_RUNTIME=${RUNTIME} make up-kvm-vnc" >&2
echo "      vncviewer localhost:${VNC_PORT} (or open http://localhost:${NOVNC_PORT}/vnc.html)" >&2
exit 1
