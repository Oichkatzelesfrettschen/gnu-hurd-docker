#!/bin/bash
# QEMU Serial Console Connection Helper
# Automatically finds and connects to QEMU serial console
# Version: 1.0

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

CONTAINER_NAME="gnu-hurd-dev"
MONITOR_SOCKET="/tmp/qemu-monitor.sock"

usage() {
    cat << EOF
Usage: $(basename "$0") [options]

Options:
  -c, --container <name>  Docker container name (default: $CONTAINER_NAME)
  -m, --monitor           Connect to QEMU monitor instead of serial console
  -l, --logs              Show container logs to find PTY path
  -h, --help              Show this help message

Description:
  Automatically finds and connects to QEMU serial console or monitor.

  Serial console: Interactive terminal for GNU/Hurd
  Monitor: QEMU control interface (info, savevm, loadvm, etc.)

Examples:
  $(basename "$0")                 # Connect to serial console
  $(basename "$0") --monitor       # Connect to QEMU monitor
  $(basename "$0") --logs          # Show logs with PTY path

Requirements:
  - screen or socat (for connections)
  - Docker container must be running
  - QEMU must be started with -serial pty

Tips:
  - In screen: Ctrl+A then K to quit
  - In socat: Ctrl+C to quit
  - To send Ctrl+C to guest: Ctrl+C twice quickly
EOF
}

# Check if container is running
check_container() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$"; then
        echo -e "${RED}ERROR: Container '$CONTAINER_NAME' is not running${NC}"
        echo ""
        echo "Start container with:"
        echo "  docker-compose up -d"
        exit 1
    fi
}

# Find PTY device from container logs
find_pty() {
    echo -e "${YELLOW}Searching for serial console PTY...${NC}"

    local pty
    pty=$(docker logs "$CONTAINER_NAME" 2>&1 | \
                grep -oP "char device redirected to /dev/pts/\K[0-9]+" | \
                tail -1)

    if [ -z "$pty" ]; then
        echo -e "${RED}ERROR: Could not find PTY device${NC}"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Check if QEMU is running:"
        echo "     docker-compose logs | grep 'Starting QEMU'"
        echo ""
        echo "  2. Verify serial output in logs:"
        echo "     docker-compose logs | grep 'char device'"
        echo ""
        echo "  3. Check entrypoint.sh has '-serial pty'"
        exit 1
    fi

    echo "/dev/pts/$pty"
}

# Show container logs with PTY information
show_logs() {
    check_container

    echo -e "${BLUE}Container logs (last 50 lines):${NC}"
    echo ""
    docker logs --tail 50 "$CONTAINER_NAME" 2>&1
    echo ""

    local pty
    pty=$(docker logs "$CONTAINER_NAME" 2>&1 | \
                grep -oP "char device redirected to /dev/pts/\K[0-9]+" | \
                tail -1)

    if [ -n "$pty" ]; then
        echo -e "${GREEN}Found serial console: /dev/pts/$pty${NC}"
        echo ""
        echo "Connect with:"
        echo "  docker exec -it $CONTAINER_NAME screen /dev/pts/$pty"
    else
        echo -e "${YELLOW}Serial console PTY not found in logs${NC}"
    fi
}

# Connect to serial console
connect_serial() {
    check_container

    local pty
    pty=$(find_pty)

    echo -e "${GREEN}Found serial console: $pty${NC}"
    echo ""
    echo -e "${BLUE}Connecting to GNU/Hurd serial console...${NC}"
    echo "  (Press Ctrl+A then K to quit screen)"
    echo ""
    sleep 1

    # Check if screen is available
    if ! docker exec "$CONTAINER_NAME" which screen &>/dev/null; then
        echo -e "${YELLOW}WARNING: 'screen' not found, using direct PTY access${NC}"
        echo "  (Press Ctrl+C to disconnect, but this may not work cleanly)"
        echo ""
        docker exec -it "$CONTAINER_NAME" cat "$pty"
    else
        # Use screen for proper terminal handling
        docker exec -it "$CONTAINER_NAME" screen "$pty"
    fi
}

# Connect to QEMU monitor
connect_monitor() {
    check_container

    echo -e "${YELLOW}Connecting to QEMU monitor...${NC}"

    # Check if monitor socket exists
    if ! docker exec "$CONTAINER_NAME" test -S "$MONITOR_SOCKET"; then
        echo -e "${RED}ERROR: QEMU monitor socket not found${NC}"
        echo ""
        echo "Monitor socket: $MONITOR_SOCKET"
        echo ""
        echo "Verify entrypoint.sh has:"
        echo "  -monitor unix:$MONITOR_SOCKET,server,nowait"
        exit 1
    fi

    echo -e "${GREEN}Found QEMU monitor: $MONITOR_SOCKET${NC}"
    echo ""
    echo -e "${BLUE}QEMU Monitor Commands:${NC}"
    echo "  info status          - Show VM running state"
    echo "  info qtree           - Show device tree"
    echo "  stop                 - Pause VM"
    echo "  cont                 - Resume VM"
    echo "  savevm <name>        - Create VM snapshot"
    echo "  loadvm <name>        - Load VM snapshot"
    echo "  quit                 - Shutdown QEMU"
    echo ""
    echo "Press Ctrl+C to disconnect"
    echo ""
    sleep 2

    # Connect with socat
    if ! docker exec "$CONTAINER_NAME" which socat &>/dev/null; then
        echo -e "${RED}ERROR: 'socat' not found in container${NC}"
        echo ""
        echo "Install socat:"
        echo "  docker exec $CONTAINER_NAME apt-get update"
        echo "  docker exec $CONTAINER_NAME apt-get install -y socat"
        exit 1
    fi

    docker exec -it "$CONTAINER_NAME" socat -,echo=0,icanon=0 "unix-connect:$MONITOR_SOCKET"
}

# Main
main() {
    local mode="serial"

    while [ $# -gt 0 ]; do
        case "$1" in
            -c|--container)
                CONTAINER_NAME="$2"
                shift 2
                ;;
            -m|--monitor)
                mode="monitor"
                shift
                ;;
            -l|--logs)
                show_logs
                exit 0
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo -e "${RED}ERROR: Unknown option: $1${NC}"
                echo ""
                usage
                exit 1
                ;;
        esac
    done

    case "$mode" in
        serial)
            connect_serial
            ;;
        monitor)
            connect_monitor
            ;;
    esac
}

main "$@"
