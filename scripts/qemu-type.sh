#!/bin/bash
set -euo pipefail

# Type ASCII text into the guest via the QEMU monitor `sendkey` command.
#
# This is a best-effort helper for situations where SSH is not yet working
# (common on some Debian GNU/Hurd images) and the serial console is blank.
#
# Notes:
# - This uses QEMU HMP `sendkey`, which is not a perfect text channel.
# - It supports a practical subset: letters, digits, space, basic punctuation,
#   newline, and tab.
#
# Usage:
#   MONITOR_PORT=9998 ./scripts/qemu-type.sh "root\n"
#   MONITOR_PORT=9998 ./scripts/qemu-type.sh --enter "root"
#   MONITOR_PORT=9998 ./scripts/qemu-type.sh --delay-ms 80 "apt-get update\n"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

delay_ms=150
append_enter=0
clear_line=0
text=""

usage() {
  cat <<'EOF'
Usage:
  MONITOR_PORT=9998 ./scripts/qemu-type.sh [options] "text"

Options:
  --delay-ms N     delay between keys (default: 150)
  --clear-line     send Ctrl+U before typing (best-effort)
  --enter          append a final Enter key
  -h, --help       show help

Examples:
  MONITOR_PORT=9998 ./scripts/qemu-type.sh "root\n"
  MONITOR_PORT=9998 ./scripts/qemu-type.sh --enter "root"
  MONITOR_PORT=9998 ./scripts/qemu-type.sh --delay-ms 80 "apt-get update\n"
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --delay-ms) delay_ms="${2:?}"; shift 2 ;;
    --clear-line) clear_line=1; shift ;;
    --enter) append_enter=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) text="$1"; shift; break ;;
  esac
done

if [ -z "$text" ]; then
  usage >&2
  exit 2
fi

msleep() {
  local ms="$1"
  python3 - <<PY
import time
time.sleep(${ms}/1000.0)
PY
}

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "[ERROR] Missing command: $1" >&2; exit 127; }; }
require_cmd expect
require_cmd telnet

key_file="$(mktemp -t qemu-type.keys.XXXXXX)"
cleanup() { rm -f "$key_file"; }
trap cleanup EXIT

emit_key() {
  printf '%s\n' "$1" >>"$key_file"
}

emit_shifted() {
  emit_key "shift-$1"
}

type_char() {
  local c="$1"
  case "$c" in
    $'\n') emit_key "ret" ;;
    $'\t') emit_key "tab" ;;
    " ") emit_key "spc" ;;
    [a-z]) emit_key "$c" ;;
    [A-Z]) emit_shifted "$(echo "$c" | tr 'A-Z' 'a-z')" ;;
    [0-9]) emit_key "$c" ;;
    ".") emit_key "dot" ;;
    ",") emit_key "comma" ;;
    "/") emit_key "slash" ;;
    "-") emit_key "minus" ;;
    "_") emit_shifted "minus" ;;
    "=") emit_key "equal" ;;
    "+") emit_shifted "equal" ;;
    ":") emit_shifted "semicolon" ;;
    ";") emit_key "semicolon" ;;
    "'") emit_key "apostrophe" ;;
    "\"") emit_shifted "apostrophe" ;;
    "\\") emit_key "backslash" ;;
    "|") emit_shifted "backslash" ;;
    "[") emit_key "bracket_left" ;;
    "]") emit_key "bracket_right" ;;
    "{") emit_shifted "bracket_left" ;;
    "}") emit_shifted "bracket_right" ;;
    "(") emit_shifted "9" ;;
    ")") emit_shifted "0" ;;
    "!") emit_shifted "1" ;;
    "@") emit_shifted "2" ;;
    "#") emit_shifted "3" ;;
    "$") emit_shifted "4" ;;
    "%") emit_shifted "5" ;;
    "^") emit_shifted "6" ;;
    "&") emit_shifted "7" ;;
    "*") emit_shifted "8" ;;
    "?") emit_shifted "slash" ;;
    "<") emit_shifted "comma" ;;
    ">") emit_shifted "dot" ;;
    *) echo "[WARN] Unsupported char for sendkey: $(printf %q "$c")" >&2 ;;
  esac
}

python3 - <<'PY' "$text" >"/tmp/qemu-type.chars"
import sys
s=sys.argv[1]
sys.stdout.write("\n".join(list(s)))
PY

if [ "$clear_line" = "1" ]; then
  # Many shells/gettys honor ^U as "kill line".
  # This reduces the odds of piling up garbage when the guest keyboard queue is slow.
  emit_key "ctrl-u"
fi

while IFS= read -r ch; do
  type_char "$ch"
done <"/tmp/qemu-type.chars"
rm -f "/tmp/qemu-type.chars"

if [ "$append_enter" = "1" ]; then
  emit_key "ret"
fi

HOST="${MONITOR_HOST:-127.0.0.1}"
PORT="${MONITOR_PORT:-9999}"

# Send keys via one telnet session (more reliable than reconnecting for every key).
expect -c "
  set timeout 4
  spawn telnet ${HOST} ${PORT}
  expect -re {\\(qemu\\)}
  set f [open \"$key_file\" r]
  while {[gets \$f line] >= 0} {
    if {\$line eq \"\"} { continue }
    send \"sendkey \$line\\r\"
    expect -re {\\(qemu\\)}
    after ${delay_ms}
  }
  close \$f
  send \"\\035\"
  expect -re {telnet>}
  send \"quit\\r\"
  expect eof
" >/dev/null

echo "[OK] typed $(python3 - <<'PY' "$text"
import sys
print(len(sys.argv[1]))
PY
) chars via QEMU monitor"
