#!/bin/bash
# QEMU Performance Monitoring Script
# Monitors QEMU performance metrics in real-time
# Version: 1.0

set -euo pipefail
n# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/container-helpers.sh
source "$SCRIPT_DIR/lib/container-helpers.sh"

QEMU_PID_FILE="qemu.pid"
REFRESH_INTERVAL=2
MONITOR_SOCKET="/tmp/qemu-monitor.sock"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Find QEMU process
find_qemu_pid() {
    if [ -f "$QEMU_PID_FILE" ]; then
        cat "$QEMU_PID_FILE"
    else
        pgrep -f "qemu-system-x86_64" | head -1
    fi
}

# Check if QEMU is running
check_qemu_running() {
    local pid="$1"
    if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
        return 1
    fi
    return 0
}

# Get CPU usage
get_cpu_usage() {
    local pid="$1"
    ps -p "$pid" -o %cpu= 2>/dev/null || echo "0.0"
}

# Get memory usage
get_memory_usage() {
    local pid="$1"
    ps -p "$pid" -o %mem=,rss= 2>/dev/null || echo "0.0 0"
}

# Get QEMU runtime
get_runtime() {
    local pid="$1"
    ps -p "$pid" -o etime= 2>/dev/null | tr -d ' ' || echo "N/A"
}

# Query QEMU monitor
query_monitor() {
    local command="$1"
    if [ -S "$MONITOR_SOCKET" ]; then
        echo "$command" | socat - UNIX-CONNECT:"$MONITOR_SOCKET" 2>/dev/null || echo "N/A"
    else
        echo "Monitor socket not available"
    fi
}

# Display header
display_header() {
    clear
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}  GNU/Hurd Docker - QEMU Performance Monitor${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo ""
}

# Display metrics
display_metrics() {
    local pid="$1"

    # Get metrics
    local cpu_usage
    cpu_usage=$(get_cpu_usage "$pid")
    local mem_data
    mem_data=$(get_memory_usage "$pid")
    local mem_percent
    mem_percent=$(echo "$mem_data" | awk '{print $1}')
    local mem_rss
    mem_rss=$(echo "$mem_data" | awk '{print $2}')
    local mem_mb=$((mem_rss / 1024))
    local runtime
    runtime=$(get_runtime "$pid")

    # Display metrics
    echo -e "${GREEN}Process Information:${NC}"
    echo "  PID: $pid"
    echo "  Runtime: $runtime"
    echo ""

    echo -e "${GREEN}Resource Usage:${NC}"
    printf "  CPU: %5.1f%%\n" "$cpu_usage"
    printf "  Memory: %5.1f%% (%d MB)\n" "$mem_percent" "$mem_mb"
    echo ""

    # QEMU Monitor info (if available)
    if [ -S "$MONITOR_SOCKET" ]; then
        echo -e "${GREEN}QEMU Monitor Status:${NC}"
        echo "  Socket: $MONITOR_SOCKET"
        echo "  Status: Connected"
        echo ""

        # Try to get VM status
        echo -e "${GREEN}VM Information:${NC}"
        query_monitor "info status" | grep -E "VM status|running|paused" | head -3
    else
        echo -e "${YELLOW}QEMU Monitor: Not available${NC}"
        echo "  (Start QEMU with -monitor unix:/tmp/qemu-monitor.sock)"
    fi

    echo ""
    echo -e "${BLUE}----------------------------------------------------------------${NC}"
    echo "Press Ctrl+C to exit | Refresh every ${REFRESH_INTERVAL}s"
}

# Main monitoring loop
main() {
    echo "Searching for QEMU process..."

    local qemu_pid
    qemu_pid=$(find_qemu_pid)

    if ! check_qemu_running "$qemu_pid"; then
        echo -e "${RED}ERROR: QEMU process not found or not running${NC}"
        echo ""
        echo "Start QEMU with:"
        echo "  docker compose up -d"
        echo ""
        echo "Or run QEMU directly:"
        echo "  ./entrypoint.sh &"
        exit 1
    fi

    echo "Found QEMU process: PID $qemu_pid"
    sleep 1

    # Monitoring loop
    while true; do
        if ! check_qemu_running "$qemu_pid"; then
            display_header
            echo -e "${RED}QEMU process terminated (PID $qemu_pid)${NC}"
            exit 1
        fi

        display_header
        display_metrics "$qemu_pid"
        sleep "$REFRESH_INTERVAL"
    done
}

# Handle Ctrl+C gracefully
trap 'echo ""; echo "Monitoring stopped."; exit 0' INT TERM

# Run main
main "$@"
