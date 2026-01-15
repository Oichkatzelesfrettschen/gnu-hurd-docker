#!/bin/bash
set -euo pipefail

# Run a single QEMU HMP (monitor) command over telnet and print the response.
# Requires: expect, telnet
#
# Usage:
#   MONITOR_PORT=9998 ./scripts/qemu-monitor-command.sh "info status"

if [[ $# -lt 1 ]]; then
  echo "Usage: MONITOR_PORT=9998 ./scripts/qemu-monitor-command.sh \"info status\"" >&2
  exit 2
fi

HOST="${MONITOR_HOST:-127.0.0.1}"
PORT="${MONITOR_PORT:-9999}"
CMD="$1"

if ! command -v expect >/dev/null 2>&1; then
  echo "[ERROR] expect not found" >&2
  exit 1
fi
if ! command -v telnet >/dev/null 2>&1; then
  echo "[ERROR] telnet not found" >&2
  exit 1
fi

expect -c "
  set timeout 4
  spawn telnet ${HOST} ${PORT}
  expect -re {\\(qemu\\)}
  send \"${CMD}\\r\"
  expect -re {\\(qemu\\)}
" | perl -pe 's/\\e\\[[0-9;]*[A-Za-z]//g' | tr -d '\r'
