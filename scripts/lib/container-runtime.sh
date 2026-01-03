#!/bin/bash
# =============================================================================
# Container Runtime Abstraction Layer
# =============================================================================
# PURPOSE:
# - Provide unified interface for Docker and Podman
# - Auto-detect available container runtime
# - Handle runtime-specific quirks and differences
# - Enable true platform agnosticism across Linux, macOS, Windows, BSD
# =============================================================================

set -euo pipefail

# Source colors for output
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/colors.sh disable=SC1091
source "${SCRIPT_DIR}/colors.sh" 2>/dev/null || {
    # Fallback if colors.sh not available
    echo_info() { echo "[INFO] $*"; }
    echo_success() { echo "[SUCCESS] $*"; }
    echo_warning() { echo "[WARNING] $*"; }
    echo_error() { echo "[ERROR] $*" >&2; }
}

# =============================================================================
# Runtime Detection
# =============================================================================

# Detect available container runtime
# Returns: "docker", "podman", or "none"
detect_container_runtime() {
    local runtime=""
    
    # Check for explicit override
    if [[ -n "${CONTAINER_RUNTIME:-}" ]]; then
        runtime="$CONTAINER_RUNTIME"
        if command -v "$runtime" >/dev/null 2>&1; then
            echo "$runtime"
            return 0
        else
            echo_warning "CONTAINER_RUNTIME set to '$runtime' but not found in PATH"
        fi
    fi
    
    # Try Docker first (more common)
    if command -v docker >/dev/null 2>&1; then
        echo "docker"
        return 0
    fi
    
    # Try Podman
    if command -v podman >/dev/null 2>&1; then
        echo "podman"
        return 0
    fi
    
    echo "none"
    return 1
}

# Get the container runtime to use
# Exits with error if none available
get_container_runtime() {
    local runtime
    runtime=$(detect_container_runtime)
    
    if [[ "$runtime" == "none" ]]; then
        echo_error "No container runtime found. Please install Docker or Podman."
        echo_error "Visit: https://docs.docker.com/get-docker/ or https://podman.io/getting-started/installation"
        exit 1
    fi
    
    echo "$runtime"
}

# Get compose command for the runtime
# shellcheck disable=SC2120
get_compose_command() {
    local runtime="${1:-$(get_container_runtime)}"
    
    case "$runtime" in
        docker)
            # Try docker compose (v2, plugin-based) first
            if docker compose version >/dev/null 2>&1; then
                echo "docker compose"
            # Fall back to docker-compose (v1, standalone)
            elif command -v docker-compose >/dev/null 2>&1; then
                echo "docker-compose"
            else
                echo_error "Docker Compose not found. Please install Docker Compose v2."
                exit 1
            fi
            ;;
        podman)
            # Podman uses podman-compose
            if command -v podman-compose >/dev/null 2>&1; then
                echo "podman-compose"
            else
                echo_error "podman-compose not found. Install with: pip3 install podman-compose"
                exit 1
            fi
            ;;
        *)
            echo_error "Unknown container runtime: $runtime"
            exit 1
            ;;
    esac
}

# =============================================================================
# Runtime-Specific Adjustments
# =============================================================================

# Check if KVM is available (Linux only)
is_kvm_available() {
    local runtime="${1:-$(get_container_runtime)}"
    
    # KVM only available on Linux
    if [[ "$(uname -s)" != "Linux" ]]; then
        return 1
    fi
    
    # Check if /dev/kvm exists and is accessible
    if [[ ! -e /dev/kvm ]]; then
        return 1
    fi
    
    # For Podman, additional checks needed
    if [[ "$runtime" == "podman" ]]; then
        # Podman needs --device flag for KVM
        # Check if we have read/write access
        if [[ -r /dev/kvm ]] && [[ -w /dev/kvm ]]; then
            return 0
        else
            return 1
        fi
    fi
    
    # For Docker, check if accessible
    if [[ -r /dev/kvm ]] && [[ -w /dev/kvm ]]; then
        return 0
    fi
    
    return 1
}

# Get device flags for KVM
get_kvm_device_flags() {
    local runtime="${1:-$(get_container_runtime)}"
    
    if ! is_kvm_available "$runtime"; then
        echo ""
        return
    fi
    
    case "$runtime" in
        docker)
            echo "--device /dev/kvm"
            ;;
        podman)
            echo "--device /dev/kvm"
            ;;
    esac
}

# Get security options
get_security_opts() {
    local runtime="${1:-$(get_container_runtime)}"
    
    case "$runtime" in
        docker)
            # Docker uses seccomp and AppArmor by default
            echo ""
            ;;
        podman)
            # Podman may need additional security options for nested virtualization
            # Running as root with --privileged for QEMU
            echo "--security-opt label=disable"
            ;;
    esac
}

# Get user namespace handling
get_userns_opts() {
    local runtime="${1:-$(get_container_runtime)}"
    
    case "$runtime" in
        docker)
            # Docker handles user namespaces automatically
            echo ""
            ;;
        podman)
            # Podman may need to disable user namespaces for KVM access
            if is_kvm_available "$runtime"; then
                echo "--userns=host"
            else
                echo ""
            fi
            ;;
    esac
}

# =============================================================================
# Platform Detection
# =============================================================================

# Detect host platform
detect_platform() {
    local os
    os=$(uname -s)
    
    case "$os" in
        Linux)
            echo "linux"
            ;;
        Darwin)
            echo "macos"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "windows"
            ;;
        FreeBSD|OpenBSD|NetBSD|DragonFly)
            echo "bsd"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Get platform-specific recommendations
get_platform_notes() {
    local platform="${1:-$(detect_platform)}"
    local runtime="${2:-$(get_container_runtime)}"
    
    case "$platform" in
        linux)
            if is_kvm_available "$runtime"; then
                echo_success "KVM acceleration available - expect 30-60s boot time"
            else
                echo_warning "KVM not available - using TCG emulation (slower, 3-5min boot)"
                echo_info "To enable KVM: ensure /dev/kvm exists and you're in the 'kvm' group"
            fi
            ;;
        macos)
            echo_warning "Running on macOS - using TCG emulation (slower, 3-5min boot)"
            echo_info "Apple Silicon (M1/M2/M3) supported via multi-arch container"
            ;;
        windows)
            echo_warning "Running on Windows - using TCG emulation (slower, 3-5min boot)"
            echo_info "Windows Subsystem for Linux (WSL2) recommended for better performance"
            ;;
        bsd)
            echo_warning "Running on BSD - using TCG emulation (slower, 3-5min boot)"
            echo_info "Consider using bhyve for native BSD virtualization"
            ;;
    esac
}

# =============================================================================
# Container Operations
# =============================================================================

# Run container with appropriate flags
container_run() {
    local runtime
    local image="$1"
    shift
    local args=("$@")
    
    runtime=$(get_container_runtime)
    
    # Build command with runtime-specific flags
    local cmd=("$runtime" "run")
    
    # Add KVM device if available
    local kvm_flags
    kvm_flags=$(get_kvm_device_flags "$runtime")
    if [[ -n "$kvm_flags" ]]; then
        # Properly handle space-separated flags
        read -ra kvm_array <<< "$kvm_flags"
        cmd+=("${kvm_array[@]}")
    fi
    
    # Add security options
    local sec_opts
    sec_opts=$(get_security_opts "$runtime")
    if [[ -n "$sec_opts" ]]; then
        read -ra sec_array <<< "$sec_opts"
        cmd+=("${sec_array[@]}")
    fi
    
    # Add user namespace options
    local userns_opts
    userns_opts=$(get_userns_opts "$runtime")
    if [[ -n "$userns_opts" ]]; then
        read -ra userns_array <<< "$userns_opts"
        cmd+=("${userns_array[@]}")
    fi
    
    # Add user-provided args and image
    cmd+=("${args[@]}" "$image")
    
    # Execute
    echo_info "Running: ${cmd[*]}"
    "${cmd[@]}"
}

# Compose up with appropriate flags
container_compose_up() {
    local compose_cmd
    compose_cmd=$(get_compose_command)
    
    echo_info "Starting containers with: $compose_cmd"
    # Properly handle multi-word compose command
    read -ra cmd_array <<< "$compose_cmd"
    "${cmd_array[@]}" up "$@"
}

# Compose down
container_compose_down() {
    local compose_cmd
    compose_cmd=$(get_compose_command)
    
    echo_info "Stopping containers with: $compose_cmd"
    # Properly handle multi-word compose command
    read -ra cmd_array <<< "$compose_cmd"
    "${cmd_array[@]}" down "$@"
}

# =============================================================================
# Compatibility Checks
# =============================================================================

# Check if runtime is compatible with requirements
check_runtime_compatibility() {
    local runtime="${1:-$(get_container_runtime)}"
    local platform
    platform=$(detect_platform)
    
    echo_info "Container Runtime: $runtime"
    echo_info "Host Platform: $platform"
    
    get_platform_notes "$platform" "$runtime"
    
    # Version checks
    case "$runtime" in
        docker)
            local docker_version
            docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
            echo_info "Docker version: $docker_version"
            ;;
        podman)
            local podman_version
            podman_version=$(podman version --format '{{.Version}}' 2>/dev/null || echo "unknown")
            echo_info "Podman version: $podman_version"
            ;;
    esac
    
    return 0
}

# =============================================================================
# Export Functions
# =============================================================================

# Make functions available to sourcing scripts
export -f detect_container_runtime
export -f get_container_runtime
export -f get_compose_command
export -f is_kvm_available
export -f get_kvm_device_flags
export -f get_security_opts
export -f get_userns_opts
export -f detect_platform
export -f get_platform_notes
export -f container_run
export -f container_compose_up
export -f container_compose_down
export -f check_runtime_compatibility
