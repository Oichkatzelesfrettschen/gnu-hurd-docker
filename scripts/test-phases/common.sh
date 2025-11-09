#!/bin/sh
# test-phases/common.sh - Shared test utilities and SSH helpers
# WHY: Centralize common test functions to reduce duplication across phase modules
# WHAT: SSH connection setup, result tracking, common test utilities
# HOW: Source this file in each phase module

set -euo pipefail

# Source color and SSH libraries
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/colors.sh
. "$SCRIPT_DIR/lib/colors.sh"
# shellcheck source=lib/ssh-helpers.sh
. "$SCRIPT_DIR/lib/ssh-helpers.sh"

# Default configuration (can be overridden by environment)
SSH_PORT="${SSH_PORT:-2222}"
SSH_HOST="${SSH_HOST:-localhost}"
ROOT_PASSWORD="${ROOT_PASSWORD:-root}"
AGENTS_PASSWORD="${AGENTS_PASSWORD:-agents}"

# Execute SSH command as root
ssh_root() {
    sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -p "$SSH_PORT" "root@$SSH_HOST" "$@" 2>/dev/null
}

# Execute SSH command as agents user
ssh_agents() {
    sshpass -p "$AGENTS_PASSWORD" ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -p "$SSH_PORT" "agents@$SSH_HOST" "$@" 2>/dev/null
}

# Execute SSH command as root with heredoc
ssh_root_heredoc() {
    sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -p "$SSH_PORT" "root@$SSH_HOST" 2>/dev/null
}

# Execute SSH command as agents user with heredoc
ssh_agents_heredoc() {
    sshpass -p "$AGENTS_PASSWORD" ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -p "$SSH_PORT" "agents@$SSH_HOST" 2>/dev/null
}

# Check if command exists on remote system
remote_command_exists() {
    local user="$1"
    local command="$2"
    
    if [ "$user" = "root" ]; then
        ssh_root "command -v $command >/dev/null 2>&1"
    else
        ssh_agents "command -v $command >/dev/null 2>&1"
    fi
}

# Export common variables and functions
export SSH_PORT SSH_HOST ROOT_PASSWORD AGENTS_PASSWORD
export -f ssh_root ssh_agents ssh_root_heredoc ssh_agents_heredoc remote_command_exists 2>/dev/null || true
