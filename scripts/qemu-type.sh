#!/bin/bash
set -euo pipefail

# Type ASCII text into the guest via QEMU `sendkey`.
#
# This is a best-effort helper for situations where SSH is not yet working
# (common on some Debian GNU/Hurd images) and the serial console is blank.
#
# Notes:
# - HMP over telnet remains supported for manual monitor setups.
# - QMP is the preferred automation transport when a socket is available.
# - Supported text includes plain ASCII plus control tokens like <enter>,
#   <ctrl-c>, and <delay:0.2>.
#
# Usage:
#   MONITOR_PORT=9998 ./scripts/qemu-type.sh "root\n"
#   MONITOR_PORT=9998 ./scripts/qemu-type.sh --enter "root"
#   QMP_SOCKET=/tmp/qemu-qmp.sock ./scripts/qemu-type.sh "<ctrl-l>root<enter>"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

delay_ms=150
append_enter=0
clear_line=0
qmp_socket="${QMP_SOCKET:-}"
text=""

usage() {
  cat <<'EOF'
Usage:
  MONITOR_PORT=9998 ./scripts/qemu-type.sh [options] "text"
  QMP_SOCKET=/tmp/qemu-qmp.sock ./scripts/qemu-type.sh [options] "text"

Options:
  --delay-ms N     delay between keys (default: 150)
  --clear-line     send Ctrl+U before typing (best-effort)
  --enter          append a final Enter key
  --qmp-socket P   use QMP socket instead of telnet monitor
  -h, --help       show help

Examples:
  MONITOR_PORT=9998 ./scripts/qemu-type.sh "root\n"
  MONITOR_PORT=9998 ./scripts/qemu-type.sh --enter "root"
  MONITOR_PORT=9998 ./scripts/qemu-type.sh --delay-ms 80 "apt-get update\n"
  QMP_SOCKET=/tmp/qemu-qmp.sock ./scripts/qemu-type.sh "<ctrl-l>root<enter>"

Special sequences in text:
  <enter> <tab> <esc> <space> <ctrl-c> <ctrl-d> <ctrl-l> <ctrl-u>
  <backspace> <delete> <up> <down> <left> <right> <delay:N>
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --delay-ms) delay_ms="${2:?}"; shift 2 ;;
    --clear-line) clear_line=1; shift ;;
    --enter) append_enter=1; shift ;;
    --qmp-socket) qmp_socket="${2:?}"; shift 2 ;;
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
require_cmd python3

key_file="$(mktemp -t qemu-type.keys.XXXXXX)"
cleanup() { rm -f "$key_file"; }
trap cleanup EXIT

python3 - "$text" "$clear_line" "$append_enter" >"$key_file" <<'PY'
import re
import sys

text = sys.argv[1]
clear_line = sys.argv[2] == "1"
append_enter = sys.argv[3] == "1"

CHAR_MAP = {
    "\n": "ret",
    "\t": "tab",
    " ": "spc",
    ".": "dot",
    ",": "comma",
    "/": "slash",
    "-": "minus",
    "_": "shift-minus",
    "=": "equal",
    "+": "shift-equal",
    ":": "shift-semicolon",
    ";": "semicolon",
    "'": "apostrophe",
    '"': "shift-apostrophe",
    "\\": "backslash",
    "|": "shift-backslash",
    "[": "bracket_left",
    "]": "bracket_right",
    "{": "shift-bracket_left",
    "}": "shift-bracket_right",
    "(": "shift-9",
    ")": "shift-0",
    "!": "shift-1",
    "@": "shift-2",
    "#": "shift-3",
    "$": "shift-4",
    "%": "shift-5",
    "^": "shift-6",
    "&": "shift-7",
    "*": "shift-8",
    "?": "shift-slash",
    "<": "shift-comma",
    ">": "shift-dot",
    "`": "grave_accent",
    "~": "shift-grave_accent",
}

SPECIAL_MAP = {
    "enter": "ret",
    "ret": "ret",
    "return": "ret",
    "tab": "tab",
    "esc": "esc",
    "escape": "esc",
    "space": "spc",
    "spc": "spc",
    "ctrl-c": "ctrl-c",
    "ctrl-d": "ctrl-d",
    "ctrl-l": "ctrl-l",
    "ctrl-u": "ctrl-u",
    "backspace": "backspace",
    "bs": "backspace",
    "delete": "delete",
    "del": "delete",
    "up": "up",
    "down": "down",
    "left": "left",
    "right": "right",
}


def emit(item: str) -> None:
    print(item)


def emit_char(ch: str) -> None:
    if "a" <= ch <= "z":
        emit(ch)
        return
    if "A" <= ch <= "Z":
        emit(f"shift-{ch.lower()}")
        return
    if "0" <= ch <= "9":
        emit(ch)
        return
    key = CHAR_MAP.get(ch)
    if key:
        emit(key)
        return
    print(f"[WARN] Unsupported char for sendkey: {ch!r}", file=sys.stderr)


if clear_line:
    emit("ctrl-u")

i = 0
while i < len(text):
    if text[i] == "<":
        end = text.find(">", i + 1)
        if end != -1:
            token = text[i + 1 : end].strip().lower()
            if token in SPECIAL_MAP:
                emit(SPECIAL_MAP[token])
                i = end + 1
                continue
            if token.startswith("delay:"):
                value = token.split(":", 1)[1]
                if re.fullmatch(r"[0-9]+(?:\.[0-9]+)?", value):
                    emit(f"__delay__:{value}")
                    i = end + 1
                    continue
        emit_char(text[i])
        i += 1
        continue

    emit_char(text[i])
    i += 1

if append_enter:
    emit("ret")
PY

send_via_qmp() {
  require_cmd socat
  if [ ! -S "$qmp_socket" ]; then
    echo "[ERROR] QMP socket not found: $qmp_socket" >&2
    exit 2
  fi
  printf '%s\n' '{"execute":"qmp_capabilities"}' | socat - UNIX-CONNECT:"$qmp_socket" >/dev/null
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      __delay__:* )
        msleep "$(python3 - "$line" <<'PY'
import sys
value = sys.argv[1].split(":", 1)[1]
print(int(float(value) * 1000))
PY
)"
        ;;
      * )
        printf '{"execute":"human-monitor-command","arguments":{"command-line":"sendkey %s"}}\n' "$line" \
          | socat - UNIX-CONNECT:"$qmp_socket" >/dev/null
        msleep "$delay_ms"
        ;;
    esac
  done <"$key_file"
}

send_via_hmp() {
  require_cmd expect
  require_cmd telnet
  local host="${MONITOR_HOST:-127.0.0.1}"
  local port="${MONITOR_PORT:-9999}"
  expect -c "
  set timeout 4
  spawn telnet ${host} ${port}
  expect -re {\\(qemu\\)}
  set f [open \"$key_file\" r]
  while {[gets \$f line] >= 0} {
    if {\$line eq \"\"} { continue }
    if {[string match {__delay__:*} \$line]} {
      set delay_secs [string range \$line 10 end]
      after [expr {int(double(\$delay_secs) * 1000)}]
    } else {
      send \"sendkey \$line\\r\"
      expect -re {\\(qemu\\)}
      after ${delay_ms}
    }
  }
  close \$f
  send \"\\035\"
  expect -re {telnet>}
  send \"quit\\r\"
  expect eof
" >/dev/null
}

if [ -n "$qmp_socket" ]; then
  send_via_qmp
else
  send_via_hmp
fi

echo "[OK] typed $(python3 - <<'PY' "$text"
import sys
print(len(sys.argv[1]))
PY
) chars via QEMU monitor"
