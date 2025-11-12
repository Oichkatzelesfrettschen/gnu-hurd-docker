#!/usr/bin/env bash
# lib/ssh-helpers.sh - SSH connection and waiting utilities
# WHY: Eliminate ~80 lines of duplicated SSH waiting logic across 5+ scripts
# WHAT: wait_for_ssh_port, ssh_exec functions with timeout and retry logic
# HOW: Source this file: source "$(dirname "$0")/lib/ssh-helpers.sh"

# Wait for SSH port to become available
# Usage: wait_for_ssh_port <host> <port> <timeout_seconds>
wait_for_ssh_port() {
    local host="${1:-localhost}"
    local port="${2:-2222}"
    local timeout="${3:-600}"
    local interval=5
    local elapsed=0

    echo "Waiting for SSH at $host:$port (timeout: ${timeout}s)..."

    while [ $elapsed -lt $timeout ]; do
        if timeout 3 nc -z "$host" "$port" 2>/dev/null; then
            echo "SSH port $port is ready!"
            return 0
        fi

        echo -n "."
        sleep $interval
        elapsed=$((elapsed + interval))
    done

    echo ""
    echo "ERROR: SSH port did not become available within ${timeout}s"
    return 1
}

# Execute SSH command with password authentication
# Usage: ssh_exec <host> <port> <password> <command>
ssh_exec() {
    local host="${1}"
    local port="${2}"
    local password="${3}"
    shift 3
    local command="$*"

    if [ -z "$command" ]; then
        echo "ERROR: No command specified for ssh_exec"
        return 1
    fi

    if command -v sshpass >/dev/null 2>&1; then
        sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "$host" "$command"
    else
        echo "ERROR: sshpass not installed. Install with: apt-get install sshpass"
        return 1
    fi
}

# Export functions for subshells
export -f wait_for_ssh_port ssh_exec 2>/dev/null || true
