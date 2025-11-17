#!/bin/bash
# GNU/Hurd Docker - QEMU CLI Control Script
# Demonstrates comprehensive CLI control of QEMU via monitor
# WHY: Enable programmatic control and automation of QEMU instances
# WHAT: QMP commands, snapshots, state management, debugging
# HOW: Telnet/netcat to QEMU monitor socket

MONITOR_PORT="${MONITOR_PORT:-9999}"
SERIAL_PORT="${SERIAL_PORT:-5555}"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

show_usage() {
    cat <<EOF
GNU/Hurd QEMU CLI Control Utility

Usage: $0 <command> [arguments]

Commands:
  status          - Show VM status
  info            - Show detailed VM information
  snapshot-list   - List available snapshots
  snapshot-create NAME - Create a new snapshot
  snapshot-load NAME   - Load a snapshot
  snapshot-delete NAME - Delete a snapshot
  pause           - Pause VM execution
  resume          - Resume VM execution
  reset           - Reset the VM
  powerdown       - Gracefully shutdown VM
  quit            - Force quit QEMU
  console         - Attach to serial console
  monitor         - Attach to QEMU monitor
  send CMD        - Send custom command to monitor

Examples:
  $0 status
  $0 snapshot-create before-test
  $0 snapshot-load before-test
  $0 send "info registers"

EOF
    exit 1
}

send_command() {
    local cmd="$1"
    echo -e "${BLUE}[QEMU Monitor]${NC} Sending: ${YELLOW}$cmd${NC}"
    echo "$cmd" | nc -q 1 localhost $MONITOR_PORT 2>/dev/null || {
        echo -e "${YELLOW}[WARNING]${NC} Monitor not available. Is QEMU running?"
        return 1
    }
}

case "${1:-}" in
    status)
        send_command "info status"
        ;;
    info)
        echo "=== VM Information ==="
        send_command "info version"
        send_command "info status"
        send_command "info kvm"
        send_command "info cpus"
        send_command "info block"
        ;;
    snapshot-list|snapshots)
        send_command "info snapshots"
        ;;
    snapshot-create)
        if [ -z "${2:-}" ]; then
            echo "Error: Snapshot name required"
            echo "Usage: $0 snapshot-create NAME"
            exit 1
        fi
        send_command "savevm $2"
        echo -e "${GREEN}[OK]${NC} Snapshot '$2' created"
        ;;
    snapshot-load)
        if [ -z "${2:-}" ]; then
            echo "Error: Snapshot name required"
            echo "Usage: $0 snapshot-load NAME"
            exit 1
        fi
        send_command "loadvm $2"
        echo -e "${GREEN}[OK]${NC} Snapshot '$2' loaded"
        ;;
    snapshot-delete)
        if [ -z "${2:-}" ]; then
            echo "Error: Snapshot name required"
            echo "Usage: $0 snapshot-delete NAME"
            exit 1
        fi
        send_command "delvm $2"
        echo -e "${GREEN}[OK]${NC} Snapshot '$2' deleted"
        ;;
    pause)
        send_command "stop"
        echo -e "${GREEN}[OK]${NC} VM paused"
        ;;
    resume)
        send_command "cont"
        echo -e "${GREEN}[OK]${NC} VM resumed"
        ;;
    reset)
        send_command "system_reset"
        echo -e "${GREEN}[OK]${NC} VM reset"
        ;;
    powerdown)
        send_command "system_powerdown"
        echo -e "${GREEN}[OK]${NC} Graceful shutdown initiated"
        ;;
    quit)
        send_command "quit"
        echo -e "${GREEN}[OK]${NC} QEMU quit command sent"
        ;;
    console)
        echo -e "${BLUE}[Serial Console]${NC} Connecting to localhost:$SERIAL_PORT"
        echo -e "${YELLOW}Press Ctrl-] then 'quit' to exit${NC}"
        telnet localhost $SERIAL_PORT
        ;;
    monitor)
        echo -e "${BLUE}[QEMU Monitor]${NC} Connecting to localhost:$MONITOR_PORT"
        echo -e "${YELLOW}Press Ctrl-] then 'quit' to exit${NC}"
        telnet localhost $MONITOR_PORT
        ;;
    send)
        if [ -z "${2:-}" ]; then
            echo "Error: Command required"
            echo "Usage: $0 send \"COMMAND\""
            exit 1
        fi
        send_command "$2"
        ;;
    *)
        show_usage
        ;;
esac
