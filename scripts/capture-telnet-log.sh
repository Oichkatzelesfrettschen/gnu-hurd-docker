#!/bin/bash
set -euo pipefail

# Capture output from a telnet-exposed QEMU chardev (serial/monitor) into a log file.
# Requires: expect, telnet
#
# Usage:
#   ./scripts/capture-telnet-log.sh --port 5555 --seconds 30 --out logs/serial.log
#
# Defaults:
#   host=127.0.0.1

usage() {
  cat <<'EOF'
Capture telnet stream to file.

Usage:
  ./scripts/capture-telnet-log.sh --port PORT --seconds N --out PATH [--host HOST] [--send DATA]
EOF
  exit 2
}

HOST="127.0.0.1"
PORT=""
SECONDS=""
OUT=""
SEND=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --seconds) SECONDS="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --send) SEND="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "[ERROR] Unknown arg: $1" >&2; usage ;;
  esac
done

if [[ -z "$PORT" || -z "$SECONDS" || -z "$OUT" ]]; then
  usage
fi

if ! command -v expect >/dev/null 2>&1; then
  echo "[ERROR] expect not found (required)" >&2
  exit 1
fi
if ! command -v telnet >/dev/null 2>&1; then
  echo "[ERROR] telnet not found (required)" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"

echo "[*] Capturing ${HOST}:${PORT} for ${SECONDS}s -> ${OUT}"

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

if ! wait_for_tcp "$HOST" "$PORT" 30; then
  echo "[ERROR] ${HOST}:${PORT} did not become reachable within 30s" >&2
  exit 1
fi

expect <<EOF
log_user 1
set timeout 1
set host "$HOST"
set port "$PORT"
set seconds "$SECONDS"
set out "$OUT"
set send_data "$SEND"

log_file -noappend \$out
spawn telnet \$host \$port

if {\$send_data ne ""} {
  send -- \$send_data
}

set end [expr {[clock seconds] + \$seconds}]
while {[clock seconds] < \$end} {
  expect {
    -re {.+} {}
    timeout {}
    eof {break}
  }
}

catch {close}
catch {wait}
EOF

# Normalize CRLF for readability.
tmp="\${OUT}.tmp.\$\$"
tr -d '\r' <"$OUT" >"$tmp" && mv "$tmp" "$OUT"

echo "[OK] Wrote $(wc -l <"$OUT") lines"
