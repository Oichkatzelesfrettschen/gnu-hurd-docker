#!/usr/bin/env bash
# lib/container-helpers.sh - Docker/QEMU container management
# WHY: Eliminate duplicated container status checking across multiple scripts
# WHAT: Functions to check container status, QEMU process, wait for boot
# HOW: Source this file: source "$(dirname "$0")/lib/container-helpers.sh"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=container-runtime.sh
source "${SCRIPT_DIR}/container-runtime.sh"

# Check if container is running
# Usage: is_container_running <container_name>
is_container_running() {
    local container_name="${1:-gnu-hurd-dev}"
    local runtime
    runtime="$(get_container_runtime)"

    if "$runtime" ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
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
        "${REPO_ROOT}/scripts/docker-orchestration.sh" up
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
# Usage: is_qemu_running [container_name]
is_qemu_running() {
    local container_name="${1:-gnu-hurd-dev}"
    local runtime
    runtime="$(get_container_runtime)"

    "$runtime" exec "$container_name" pgrep -x qemu-system-x86_64 >/dev/null 2>&1
}

# Get QEMU PID
# Usage: get_qemu_pid [container_name]
get_qemu_pid() {
    local container_name="${1:-gnu-hurd-dev}"
    local runtime
    runtime="$(get_container_runtime)"

    "$runtime" exec "$container_name" pgrep -o qemu-system-x86_64
}

# Export functions for subshells
export -f is_container_running ensure_container_running is_qemu_running get_qemu_pid 2>/dev/null || true
