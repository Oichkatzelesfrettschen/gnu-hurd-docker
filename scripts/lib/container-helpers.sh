#!/bin/sh
# lib/container-helpers.sh - Docker/QEMU container management
# WHY: Eliminate duplicated container status checking across multiple scripts
# WHAT: Functions to check container status, QEMU process, wait for boot
# HOW: Source this file: source "$(dirname "$0")/lib/container-helpers.sh"

# Check if container is running
# Usage: is_container_running <container_name>
is_container_running() {
    local container_name="${1:-gnu-hurd-dev}"

    if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        return 0
    else
        return 1
    fi
}

# Ensure container is running, start if not
# Usage: ensure_container_running <container_name>
ensure_container_running() {
    local container_name="${1:-gnu-hurd-dev}"

    if is_container_running "$container_name"; then
        echo "Container $container_name is already running"
        return 0
    else
        echo "Starting container $container_name..."
        docker compose up -d
        sleep 5

        if is_container_running "$container_name"; then
            echo "Container $container_name started successfully"
            return 0
        else
            echo "ERROR: Failed to start container $container_name"
            return 1
        fi
    fi
}

# Check if QEMU process is running
# Usage: is_qemu_running
is_qemu_running() {
    if pgrep -f "qemu-system" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Get QEMU PID
# Usage: get_qemu_pid
get_qemu_pid() {
    pgrep -f "qemu-system" | head -1
}

# Export functions for subshells
export -f is_container_running ensure_container_running is_qemu_running get_qemu_pid 2>/dev/null || true
